#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json);
use FindBin qw($Bin);

my $PRICING_MANIFEST_PATH = $ENV{STATUSLINE_PRICING_MANIFEST} // "$Bin/anthropic_pricing.json";
my %PRICING_BY_KEY;
my @PRICING_RULES;
my %FALLBACK_PRICING_KEYS;
my %WARNED_UNKNOWN_MODELS;

sub usage {
    die "usage: $0 cold-scan | refresh-state <state_path> <now> <out_path>\n";
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

sub usage_fields_from_line {
    my ($line) = @_;
    my $data = eval { decode_json($line) };
    return unless $data && ref($data) eq 'HASH';
    return unless ($data->{type} // '') eq 'message';
    return unless ref($data->{usage}) eq 'HASH';

    my $input = usage_int_field($data->{usage}, 'input_tokens');
    my $output = usage_int_field($data->{usage}, 'output_tokens');
    my $cache_write = usage_int_field($data->{usage}, 'cache_creation_input_tokens');
    my $cache_read = usage_int_field($data->{usage}, 'cache_read_input_tokens');
    my $total_tokens = $input + $output + $cache_write + $cache_read;
    my $cost_units = cost_units_for_line(
        $data->{model},
        $input,
        $output,
        $cache_write,
        $cache_read,
    );

    return ($total_tokens, $cost_units, $input, $output, $cache_write, $cache_read);
}

sub zero_summary {
    return (0, 0, 0, 0, 0, 0);
}

sub summarize_handle {
    my ($fh) = @_;
    my ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr) = zero_summary();

    while (my $line = <$fh>) {
        my @fields = usage_fields_from_line($line);
        next unless @fields;

        $total_tokens += $fields[0];
        $total_cost_units += $fields[1];
        $total_input += $fields[2];
        $total_output += $fields[3];
        $total_cw += $fields[4];
        $total_cr += $fields[5];
    }

    return ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr);
}

sub parse_usage_file {
    my ($path, $start_pos) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    seek($fh, $start_pos, 0) if $start_pos;
    my @summary = summarize_handle($fh);
    close $fh;
    return @summary;
}

sub print_summary {
    my (@summary) = @_;
    print join(' ', @summary);
}

sub read_nul_paths {
    binmode STDIN;
    local $/ = undef;
    my $raw = <STDIN> // '';
    return sort grep { length } split /\0/, $raw;
}

sub load_prior_state {
    my ($state_path) = @_;
    my %old;

    if (open my $state_fh, '<', $state_path) {
        scalar <$state_fh>;
        scalar <$state_fh>;
        while (my $line = <$state_fh>) {
            chomp $line;
            my ($mtime, $size, $tokens, $cost_units, $input, $output, $cw, $cr, $path) =
                split /\t/, $line, 9;
            next unless defined $path;
            $old{$path} = {
                mtime => $mtime + 0,
                size => $size + 0,
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

    return \%old;
}

sub run_cold_scan {
    my @summary = summarize_handle(*STDIN);
    print_summary(@summary);
    return 0;
}

sub run_refresh_state {
    my ($state_path, $now, $out_path) = @_;
    usage() unless defined $state_path && defined $now && defined $out_path;

    my $old = load_prior_state($state_path);
    my @paths = read_nul_paths();
    my @records;
    my ($total_tokens, $total_cost_units, $total_input, $total_output, $total_cw, $total_cr) = zero_summary();

    for my $path (@paths) {
        my @stat = stat($path);
        next unless @stat;

        my ($mtime, $size) = ($stat[9], $stat[7]);
        my ($tokens, $cost_units, $input, $output, $cw, $cr);
        my $prev = $old->{$path};

        if ($prev && $size == $prev->{size} && $mtime == $prev->{mtime}) {
            ($tokens, $cost_units, $input, $output, $cw, $cr) =
                @{$prev}{qw(tokens cost_units input output cw cr)};
        } elsif ($prev && $size >= $prev->{size}) {
            my @delta = parse_usage_file($path, $prev->{size});
            $tokens = $prev->{tokens} + $delta[0];
            $cost_units = $prev->{cost_units} + $delta[1];
            $input = $prev->{input} + $delta[2];
            $output = $prev->{output} + $delta[3];
            $cw = $prev->{cw} + $delta[4];
            $cr = $prev->{cr} + $delta[5];
        } else {
            ($tokens, $cost_units, $input, $output, $cw, $cr) = parse_usage_file($path, 0);
        }

        push @records, join("\t", $mtime, $size, $tokens, $cost_units, $input, $output, $cw, $cr, $path);
        $total_tokens += $tokens;
        $total_cost_units += $cost_units;
        $total_input += $input;
        $total_output += $output;
        $total_cw += $cw;
        $total_cr += $cr;
    }

    open my $out_fh, '>', $out_path or die "open $out_path: $!";
    print {$out_fh} "$now\n";
    print {$out_fh} "$total_tokens $total_cost_units $total_input $total_output $total_cw $total_cr\n";
    print {$out_fh} "$_\n" for @records;
    close $out_fh;

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

usage();
