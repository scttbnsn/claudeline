#!/usr/bin/env perl
use strict;
use warnings;

use constant {
    SONNET_INPUT_COST_UNITS       => 300,
    SONNET_OUTPUT_COST_UNITS      => 1500,
    SONNET_CACHE_WRITE_COST_UNITS => 375,
    SONNET_CACHE_READ_COST_UNITS  => 30,
    OPUS_INPUT_COST_UNITS         => 1500,
    OPUS_OUTPUT_COST_UNITS        => 7500,
    OPUS_CACHE_WRITE_COST_UNITS   => 1875,
    OPUS_CACHE_READ_COST_UNITS    => 150,
};

sub usage {
    die "usage: $0 cold-scan | refresh-state <state_path> <now> <out_path>\n";
}

sub is_usage_line {
    my ($line) = @_;
    return $line =~ /"message".*"usage"/;
}

sub is_opus_model {
    my ($line) = @_;
    return $line =~ /claude-opus|opus-4/ ? 1 : 0;
}

sub cost_units_for_line {
    my ($is_opus, $input, $output, $cache_write, $cache_read) = @_;

    if ($is_opus) {
        return $input * OPUS_INPUT_COST_UNITS
            + $output * OPUS_OUTPUT_COST_UNITS
            + $cache_write * OPUS_CACHE_WRITE_COST_UNITS
            + $cache_read * OPUS_CACHE_READ_COST_UNITS;
    }

    return $input * SONNET_INPUT_COST_UNITS
        + $output * SONNET_OUTPUT_COST_UNITS
        + $cache_write * SONNET_CACHE_WRITE_COST_UNITS
        + $cache_read * SONNET_CACHE_READ_COST_UNITS;
}

sub usage_fields_from_line {
    my ($line) = @_;
    return unless is_usage_line($line);

    my $input = $line =~ /"input_tokens":(\d+)/ ? $1 : 0;
    my $output = $line =~ /"output_tokens":(\d+)/ ? $1 : 0;
    my $cache_write = $line =~ /"cache_creation_input_tokens":(\d+)/ ? $1 : 0;
    my $cache_read = $line =~ /"cache_read_input_tokens":(\d+)/ ? $1 : 0;
    my $total_tokens = $input + $output + $cache_write + $cache_read;
    my $cost_units = cost_units_for_line(
        is_opus_model($line),
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

if ($mode eq 'cold-scan') {
    exit run_cold_scan();
}

if ($mode eq 'refresh-state') {
    exit run_refresh_state(@ARGV);
}

usage();
