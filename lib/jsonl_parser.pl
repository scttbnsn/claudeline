#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use FindBin qw($Bin);
use Fcntl qw(O_CREAT O_RDWR);
use File::Temp qw(tempdir);
use SDBM_File;
use Time::Local qw(timegm timelocal);

my $PRICING_MANIFEST_PATH = $ENV{STATUSLINE_PRICING_MANIFEST} // "$Bin/anthropic_pricing.json";
my %PRICING_BY_KEY;
my @PRICING_RULES;
my %FALLBACK_PRICING_KEYS;
my %WARNED_UNKNOWN_MODELS;
my $DEDUP_RETENTION_SECONDS = 86_400;

sub usage {
    die "usage: $0 cold-scan | refresh-state <state_path> <now> <out_path> | window-scan <now> <current_dir> [block_seconds]\n";
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content // '';
}

sub compile_manifest_regex {
    my ($match_value, $path) = @_;

    die "invalid regex rule in $path: unsupported pattern $match_value\n"
        unless $match_value =~ /\A\^(?:[A-Za-z0-9.-]+|\\d\{(?:[1-9]|[1-9]\d)\})+\$\z/;

    return qr/$match_value/;
}

sub load_pricing_manifest {
    my $doc = decode_json(slurp($PRICING_MANIFEST_PATH));

    die "pricing manifest $PRICING_MANIFEST_PATH is missing a pricing map\n"
        unless ref($doc->{pricing}) eq 'HASH';
    die "pricing manifest $PRICING_MANIFEST_PATH is missing rules\n"
        unless ref($doc->{rules}) eq 'ARRAY';
    die "pricing manifest $PRICING_MANIFEST_PATH is missing fallback pricing keys\n"
        unless ref($doc->{fallback_pricing_keys}) eq 'HASH';

    %PRICING_BY_KEY = %{$doc->{pricing}};
    @PRICING_RULES = map {
        my $pricing_key = $_->{pricing_key} // '';
        my $match_kind = $_->{match_kind} // '';
        my $match_value = $_->{match_value} // '';

        die "invalid pricing rule in $PRICING_MANIFEST_PATH\n"
            unless length $pricing_key
            && ($match_kind eq 'exact' || $match_kind eq 'regex')
            && length $match_value
            && exists $PRICING_BY_KEY{$pricing_key};

        {
            pricing_key => $pricing_key,
            match_kind => $match_kind,
            match_value => $match_value,
            compiled_regex => $match_kind eq 'regex'
                ? compile_manifest_regex($match_value, $PRICING_MANIFEST_PATH)
                : undef,
        };
    } @{$doc->{rules}};

    %FALLBACK_PRICING_KEYS = %{$doc->{fallback_pricing_keys}};
    for my $family (qw(default opus sonnet haiku)) {
        die "pricing manifest $PRICING_MANIFEST_PATH is missing fallback key for $family\n"
            unless exists $FALLBACK_PRICING_KEYS{$family}
            && exists $PRICING_BY_KEY{$FALLBACK_PRICING_KEYS{$family}};
    }
}

sub warn_unknown_model_once {
    my ($model) = @_;
    return if !defined $model || $WARNED_UNKNOWN_MODELS{$model}++;

    my $fallback_key = fallback_pricing_key_for_model($model);
    warn "Unknown Claude model $model; falling back to $fallback_key pricing\n";
}

sub fallback_pricing_key_for_model {
    my ($model) = @_;

    return $FALLBACK_PRICING_KEYS{opus}
        if defined $model && $model =~ /opus/i;
    return $FALLBACK_PRICING_KEYS{haiku}
        if defined $model && $model =~ /haiku/i;
    return $FALLBACK_PRICING_KEYS{sonnet}
        if defined $model && $model =~ /sonnet/i;
    return $FALLBACK_PRICING_KEYS{default};
}

sub pricing_key_for_model {
    my ($model) = @_;

    if (defined $model) {
        for my $rule (@PRICING_RULES) {
            if ($rule->{match_kind} eq 'exact' && $model eq $rule->{match_value}) {
                return $rule->{pricing_key};
            }
            if ($rule->{match_kind} eq 'regex' && $model =~ $rule->{compiled_regex}) {
                return $rule->{pricing_key};
            }
        }
    }

    warn_unknown_model_once($model // '<missing>');
    return fallback_pricing_key_for_model($model);
}

sub usage_int_field {
    my ($usage, $key) = @_;
    return 0 unless ref($usage) eq 'HASH';

    my $value = $usage->{$key};
    return 0 unless defined $value && $value =~ /\A\d+\z/;
    return $value + 0;
}

sub cost_units_for_line {
    my ($model, $input, $output, $cache_write, $cache_read) = @_;
    my $pricing_key = pricing_key_for_model($model);
    my $pricing = $PRICING_BY_KEY{$pricing_key}
        or die "missing pricing entry $pricing_key in $PRICING_MANIFEST_PATH\n";

    return $input * $pricing->{input_cost_units}
        + $output * $pricing->{output_cost_units}
        + $cache_write * $pricing->{cache_write_cost_units}
        + $cache_read * $pricing->{cache_read_cost_units};
}

sub usage_record_from_line {
    my ($line) = @_;
    my $data = eval { decode_json($line) };
    return unless $data && ref($data) eq 'HASH';

    my $message = $data;
    if (($data->{type} // '') eq 'assistant' && ref($data->{message}) eq 'HASH') {
        $message = $data->{message};
    } elsif (($data->{type} // '') ne 'message') {
        return;
    }

    return unless ($message->{type} // 'message') eq 'message';
    return unless ref($message->{usage}) eq 'HASH';

    my $input = usage_int_field($message->{usage}, 'input_tokens');
    my $output = usage_int_field($message->{usage}, 'output_tokens');
    my $cache_write = usage_int_field($message->{usage}, 'cache_creation_input_tokens');
    my $cache_read = usage_int_field($message->{usage}, 'cache_read_input_tokens');
    my $total_tokens = $input + $output + $cache_write + $cache_read;
    my $cost_units = cost_units_for_line(
        $message->{model} // $data->{model},
        $input,
        $output,
        $cache_write,
        $cache_read,
    );
    my $message_id = $message->{id};
    $message_id = undef unless defined $message_id && length $message_id;
    my $workspace_cwd = ref($data->{workspace}) eq 'HASH' ? $data->{workspace}{current_dir} : undef;

    return {
        id => $message_id,
        timestamp => $data->{timestamp} // $message->{timestamp},
        cwd => $data->{cwd} // $workspace_cwd // $message->{cwd},
        fields => [$total_tokens, $cost_units, $input, $output, $cache_write, $cache_read],
    };
}

sub zero_summary {
    return (0, 0, 0, 0, 0, 0);
}

sub summarize_handle {
    my ($fh) = @_;
    my ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr) = zero_summary();
    my %seen_message_ids;

    while (my $line = <$fh>) {
        my $record = usage_record_from_line($line);
        next unless $record;
        next if defined $record->{id} && $seen_message_ids{$record->{id}}++;
        my @fields = @{$record->{fields}};

        $total_tokens += $fields[0];
        $total_cost_units += $fields[1];
        $total_input += $fields[2];
        $total_output += $fields[3];
        $total_cw += $fields[4];
        $total_cr += $fields[5];
    }

    return ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr);
}

sub parse_complete_usage_file {
    my ($path, $start_pos, $seen_message_ids, $now) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    seek($fh, $start_pos, 0) or die "seek $path to $start_pos: $!" if $start_pos;

    my @summary = zero_summary();
    my $parsed_pos = $start_pos;
    while (my $line = <$fh>) {
        last unless $line =~ /\n\z/;
        $parsed_pos = tell($fh);

        my $record = usage_record_from_line($line);
        next unless $record;
        if (defined $record->{id}) {
            my $record_epoch = timestamp_epoch($record->{timestamp}) // $now;
            if (exists $seen_message_ids->{$record->{id}}) {
                $seen_message_ids->{$record->{id}} = $record_epoch
                    if $record_epoch > $seen_message_ids->{$record->{id}};
                next;
            }
            $seen_message_ids->{$record->{id}} = $record_epoch;
        }

        for my $index (0 .. 5) {
            $summary[$index] += $record->{fields}[$index];
        }
    }

    close $fh;
    return (@summary, $parsed_pos);
}

sub has_record_boundary_at {
    my ($path, $parsed_pos) = @_;
    return 1 unless $parsed_pos;

    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    my $at_boundary = 0;
    if (seek($fh, $parsed_pos - 1, 0)) {
        my $byte = '';
        my $read = read($fh, $byte, 1);
        $at_boundary = defined $read && $read == 1 && $byte eq "\n";
    }
    close $fh;
    return $at_boundary;
}

sub print_summary {
    my (@summary) = @_;
    print join(' ', @summary);
}

sub cost_units_to_cents {
    my ($cost_units) = @_;
    return int(($cost_units + 500_000) / 1_000_000);
}

sub timestamp_epoch {
    my ($timestamp) = @_;
    return unless defined $timestamp;
    return unless $timestamp =~ /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/;
    return eval { timegm($6, $5, $4, $3, $2 - 1, $1) };
}

sub local_day_start_epoch {
    my ($now) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($now);
    return timelocal(0, 0, 0, $mday, $mon, $year);
}

sub read_nul_paths {
    binmode STDIN;
    local $/ = undef;
    my $raw = <STDIN> // '';
    return sort grep { length } split /\0/, $raw;
}

sub load_prior_state {
    my ($state_path, $seen_message_ids, $now) = @_;
    my %old;
    my $needs_dedup_rebuild = 0;

    if (open my $state_fh, '<', $state_path) {
        scalar <$state_fh>;
        scalar <$state_fh>;
        while (my $line = <$state_fh>) {
            chomp $line;
            if ($line =~ /\AI\t(?:(\d+)\t)?(.*)\z/) {
                my ($seen_epoch, $encoded_id) = ($1, $2);
                my $message_id = eval { decode_json($encoded_id) };
                $seen_message_ids->{$message_id} = defined $seen_epoch ? $seen_epoch : $now
                    if defined $message_id && !ref($message_id) && length $message_id;
                next;
            }

            my @fields = split /\t/, $line, 10;
            my ($mtime, $size, $parsed_pos, $tokens, $cost_units, $input, $output, $cw, $cr, $path);
            if (@fields == 10) {
                ($mtime, $size, $parsed_pos, $tokens, $cost_units, $input, $output, $cw, $cr, $path) = @fields;
            } else {
                ($mtime, $size, $tokens, $cost_units, $input, $output, $cw, $cr, $path) =
                    split /\t/, $line, 9;
                $parsed_pos = $size;
                $needs_dedup_rebuild = 1;
            }
            next unless defined $path;
            $old{$path} = {
                mtime => $mtime + 0,
                size => $size + 0,
                parsed_pos => $parsed_pos + 0,
                tokens => $tokens + 0,
                cost_units => $cost_units + 0,
                input => $input + 0,
                output => $output + 0,
                cw => $cw + 0,
                cr => $cr + 0,
            };
        }
        close $state_fh;
    }

    return (\%old, $needs_dedup_rebuild);
}

sub run_cold_scan {
    my @summary = summarize_handle(*STDIN);
    print_summary(@summary);
    return 0;
}

sub run_window_scan {
    my ($now, $current_dir, $block_seconds) = @_;
    usage() unless defined $now && $now =~ /\A\d+\z/ && defined $current_dir;
    $block_seconds = 18_000 unless defined $block_seconds && $block_seconds =~ /\A\d+\z/ && $block_seconds > 0;

    my $day_start = local_day_start_epoch($now);
    my $block_start = $now - $block_seconds;
    my ($today_tokens, $today_cost_units, $block_tokens, $block_cost_units) = (0, 0, 0, 0);
    my %seen_message_ids;

    while (my $line = <STDIN>) {
        my $record = usage_record_from_line($line);
        next unless $record;
        next if defined $record->{id} && $seen_message_ids{$record->{id}}++;

        my $tokens = $record->{fields}[0];
        my $cost_units = $record->{fields}[1];
        my $epoch = timestamp_epoch($record->{timestamp});
        if (defined $epoch) {
            if ($epoch >= $day_start && $epoch <= $now) {
                $today_tokens += $tokens;
                $today_cost_units += $cost_units;
            }
            if ($epoch >= $block_start && $epoch <= $now) {
                $block_tokens += $tokens;
                $block_cost_units += $cost_units;
            }
        }
    }

    print join(' ',
        $today_tokens,
        cost_units_to_cents($today_cost_units),
        $block_tokens,
        cost_units_to_cents($block_cost_units),
    );
    return 0;
}

sub run_refresh_state {
    my ($state_path, $now, $out_path) = @_;
    usage() unless defined $state_path && defined $now && defined $out_path;

    my $dedup_dir = tempdir(CLEANUP => 1);
    my %seen_message_ids;
    tie %seen_message_ids, 'SDBM_File', "$dedup_dir/message-ids", O_RDWR | O_CREAT, 0600
        or die "create refresh dedup index: $!";

    my ($old, $needs_dedup_rebuild) = load_prior_state($state_path, \%seen_message_ids, $now);
    my @paths = read_nul_paths();
    my @records;
    my ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr) = zero_summary();

    my %current_stats;
    for my $path (@paths) {
        my @stat = stat($path);
        $current_stats{$path} = [$stat[9], $stat[7]] if @stat;
    }

    my $full_reparse = $needs_dedup_rebuild || grep { !exists $current_stats{$_} } keys %{$old};
    if (!$full_reparse) {
        for my $path (@paths) {
            next unless exists $current_stats{$path} && exists $old->{$path};
            my ($mtime, $size) = @{$current_stats{$path}};
            my $prev = $old->{$path};
            if ($size < $prev->{size}
                    || ($size == $prev->{size} && $mtime != $prev->{mtime})
                    || ($size > $prev->{size} && !has_record_boundary_at($path, $prev->{parsed_pos}))) {
                $full_reparse = 1;
                last;
            }
        }
    }
    %seen_message_ids = () if $full_reparse;

    for my $path (@paths) {
        next unless exists $current_stats{$path};

        my ($mtime, $size) = @{$current_stats{$path}};
        my ($tokens, $cost_units, $input, $output, $cw, $cr, $parsed_pos);
        my $prev = $old->{$path};

        if (!$full_reparse && $prev && $size == $prev->{size} && $mtime == $prev->{mtime}) {
            ($tokens, $cost_units, $input, $output, $cw, $cr) =
                @{$prev}{qw(tokens cost_units input output cw cr)};
            $parsed_pos = $prev->{parsed_pos};
        } elsif (!$full_reparse && $prev && $size >= $prev->{size}) {
            my @delta = parse_complete_usage_file($path, $prev->{parsed_pos}, \%seen_message_ids, $now);
            $tokens = $prev->{tokens} + $delta[0];
            $cost_units = $prev->{cost_units} + $delta[1];
            $input = $prev->{input} + $delta[2];
            $output = $prev->{output} + $delta[3];
            $cw = $prev->{cw} + $delta[4];
            $cr = $prev->{cr} + $delta[5];
            $parsed_pos = $delta[6];
        } else {
            ($tokens, $cost_units, $input, $output, $cw, $cr, $parsed_pos) =
                parse_complete_usage_file($path, 0, \%seen_message_ids, $now);
        }

        push @records, join("\t", $mtime, $size, $parsed_pos, $tokens, $cost_units, $input, $output, $cw, $cr, $path);
        $total_tokens += $tokens;
        $total_cost_units += $cost_units;
        $total_input += $input;
        $total_output += $output;
        $total_cw += $cw;
        $total_cr += $cr;
    }

    open my $out_fh, '>', $out_path or die "open $out_path: $!";
    my $write_ok = print {$out_fh} "$now\n";
    $write_ok = 0 unless print {$out_fh} "$total_tokens $total_cost_units $total_input $total_output $total_cw $total_cr\n";
    for my $record (@records) {
        $write_ok = 0, last unless print {$out_fh} "$record\n";
    }
    my $dedup_cutoff = $now - $DEDUP_RETENTION_SECONDS;
    if ($write_ok) {
        while (my ($message_id, $seen_epoch) = each %seen_message_ids) {
            next if $seen_epoch < $dedup_cutoff;
            $write_ok = 0, last
                unless print {$out_fh} "I\t$seen_epoch\t", encode_json($message_id), "\n";
        }
    }
    my $close_ok = close $out_fh;

    untie %seen_message_ids;
    die "write $out_path: $!\n" unless $write_ok && $close_ok;

    print_summary($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr);
    return 0;
}

my $mode = shift @ARGV // usage();
load_pricing_manifest();

if ($mode eq 'cold-scan') {
    exit run_cold_scan();
}

if ($mode eq 'refresh-state') {
    exit run_refresh_state(@ARGV);
}

if ($mode eq 'window-scan') {
    exit run_window_scan(@ARGV);
}

usage();
