#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use HTTP::Tiny;
use JSON::PP qw(encode_json);

my $PRICING_URL = 'https://platform.claude.com/docs/en/about-claude/pricing';
my $DEFAULT_OUTPUT = 'lib/anthropic_pricing.json';

my @RULE_SPECS = (
    {
        pricing_key => 'claude-opus-4-6',
        pricing_name => 'Claude Opus 4.6',
        matches => [
            { kind => 'exact', value => 'claude-opus-4-6' },
            { kind => 'regex', value => '^claude-opus-4-6-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-opus-4-5',
        pricing_name => 'Claude Opus 4.5',
        matches => [
            { kind => 'exact', value => 'claude-opus-4-5' },
            { kind => 'regex', value => '^claude-opus-4-5-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-opus-4-1',
        pricing_name => 'Claude Opus 4.1',
        matches => [
            { kind => 'exact', value => 'claude-opus-4-1' },
            { kind => 'regex', value => '^claude-opus-4-1-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-opus-4',
        pricing_name => 'Claude Opus 4',
        matches => [
            { kind => 'exact', value => 'claude-opus-4' },
            { kind => 'exact', value => 'claude-opus-4-0' },
            { kind => 'exact', value => 'claude-opus-4-20250514' },
        ],
    },
    {
        pricing_key => 'claude-sonnet-4-6',
        pricing_name => 'Claude Sonnet 4.6',
        matches => [
            { kind => 'exact', value => 'claude-sonnet-4-6' },
            { kind => 'regex', value => '^claude-sonnet-4-6-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-sonnet-4-5',
        pricing_name => 'Claude Sonnet 4.5',
        matches => [
            { kind => 'exact', value => 'claude-sonnet-4-5' },
            { kind => 'regex', value => '^claude-sonnet-4-5-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-sonnet-4',
        pricing_name => 'Claude Sonnet 4',
        matches => [
            { kind => 'exact', value => 'claude-sonnet-4' },
            { kind => 'exact', value => 'claude-sonnet-4-0' },
            { kind => 'exact', value => 'claude-sonnet-4-20250514' },
        ],
    },
    {
        pricing_key => 'claude-sonnet-3-7',
        pricing_name => 'Claude Sonnet 3.7',
        matches => [
            { kind => 'regex', value => '^claude-3-7-sonnet-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-haiku-4-5',
        pricing_name => 'Claude Haiku 4.5',
        matches => [
            { kind => 'exact', value => 'claude-haiku-4-5' },
            { kind => 'regex', value => '^claude-haiku-4-5-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-haiku-3-5',
        pricing_name => 'Claude Haiku 3.5',
        matches => [
            { kind => 'regex', value => '^claude-3-5-haiku-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-opus-3',
        pricing_name => 'Claude Opus 3',
        matches => [
            { kind => 'regex', value => '^claude-3-opus-\d{8}$' },
        ],
    },
    {
        pricing_key => 'claude-haiku-3',
        pricing_name => 'Claude Haiku 3',
        matches => [
            { kind => 'regex', value => '^claude-3-haiku-\d{8}$' },
        ],
    },
);

sub usage {
    die "usage: $0 [--pricing-html PATH] [--output PATH] [--generated-at ISO8601]\n";
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content // '';
}

sub fetch_pricing_html {
    my $http = HTTP::Tiny->new(
        agent => "claudeline-pricing-updater/1.0",
        timeout => 20,
    );
    my $response = $http->get($PRICING_URL);
    die "failed to fetch $PRICING_URL: $response->{status} $response->{reason}\n"
        unless $response->{success};
    return $response->{content};
}

sub html_unescape {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/&amp;/&/g;
    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/&quot;/"/g;
    $value =~ s/&#x27;/'/g;
    $value =~ s/&#39;/'/g;
    return $value;
}

sub normalize_cell_text {
    my ($value) = @_;
    $value = html_unescape($value);
    $value =~ s/<[^>]+>/ /g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub dollars_per_mtok_to_units {
    my ($value) = @_;
    die "missing dollars/MTok value\n" unless defined $value && length $value;
    $value =~ s/^\$//;
    $value =~ s/\s*\/\s*MTok$//;
    $value =~ s/\s+//g;
    die "invalid dollars/MTok value: $value\n" unless $value =~ /\A\d+(?:\.\d+)?\z/;

    my ($int_part, $frac_part) = split /\./, $value, 2;
    $frac_part //= '';
    $frac_part .= '00';
    $frac_part = substr($frac_part, 0, 2);
    return ($int_part * 100) + $frac_part;
}

sub extract_pricing_rows {
    my ($html) = @_;
    my ($table) = $html =~ m{
        (<table\b.*?</table>)
    }six;
    die "unable to locate pricing table in Anthropic pricing docs\n"
        unless defined $table
        && $table =~ /Base Input Tokens/
        && $table =~ /5m Cache Writes/
        && $table =~ /1h Cache Writes/
        && $table =~ /Cache Hits(?: &amp; | and )Refreshes/
        && $table =~ /Output Tokens/;

    my %rows;
    while ($table =~ m{<tr\b[^>]*>(.*?)</tr>}sg) {
        my $row = $1;
        my @cells = map { normalize_cell_text($_) } ($row =~ m{<t[dh]\b[^>]*>(.*?)</t[dh]>}sg);
        next unless @cells == 6;
        next if $cells[0] eq 'Model';

        my $model_name = $cells[0];
        $model_name =~ s/\s+\( deprecated \)$//;

        $rows{$model_name} = {
            display_name => $model_name,
            input_cost_units => dollars_per_mtok_to_units($cells[1]),
            cache_write_cost_units => dollars_per_mtok_to_units($cells[2]),
            cache_write_1h_cost_units => dollars_per_mtok_to_units($cells[3]),
            cache_read_cost_units => dollars_per_mtok_to_units($cells[4]),
            output_cost_units => dollars_per_mtok_to_units($cells[5]),
        };
    }

    return \%rows;
}

sub build_manifest {
    my ($rows, $generated_at) = @_;
    my %pricing;
    my @rules;

    for my $spec (@RULE_SPECS) {
        my $row = $rows->{$spec->{pricing_name}}
            or die "pricing docs are missing row for $spec->{pricing_name}\n";

        $pricing{$spec->{pricing_key}} = {
            display_name => $row->{display_name},
            input_cost_units => $row->{input_cost_units},
            cache_write_cost_units => $row->{cache_write_cost_units},
            cache_write_1h_cost_units => $row->{cache_write_1h_cost_units},
            cache_read_cost_units => $row->{cache_read_cost_units},
            output_cost_units => $row->{output_cost_units},
        };

        for my $match (@{$spec->{matches}}) {
            push @rules, {
                pricing_key => $spec->{pricing_key},
                match_kind => $match->{kind},
                match_value => $match->{value},
            };
        }
    }

    return {
        generated_at => $generated_at,
        pricing_source_url => $PRICING_URL,
        jsonl_usage_notes => {
            cache_creation_input_tokens => 'Mapped to the 5-minute prompt cache write rate because Claude Code JSONL usage does not expose cache duration.',
            cache_read_input_tokens => 'Mapped to the prompt cache hit/refresh rate from Anthropic pricing docs.',
        },
        fallback_pricing_keys => {
            default => 'claude-sonnet-4-6',
            opus => 'claude-opus-4-6',
            sonnet => 'claude-sonnet-4-6',
            haiku => 'claude-haiku-4-5',
        },
        pricing => \%pricing,
        rules => \@rules,
    };
}

my $pricing_html_path = '';
my $output_path = $DEFAULT_OUTPUT;
my $generated_at = '';

GetOptions(
    'pricing-html=s' => \$pricing_html_path,
    'output=s' => \$output_path,
    'generated-at=s' => \$generated_at,
) or usage();

$generated_at ||= scalar gmtime() . ' UTC';

my $html = $pricing_html_path ? slurp($pricing_html_path) : fetch_pricing_html();
my $rows = extract_pricing_rows($html);
my $manifest = build_manifest($rows, $generated_at);

open my $out_fh, '>', $output_path or die "open $output_path: $!";
print {$out_fh} JSON::PP->new->ascii->pretty->canonical->encode($manifest);
close $out_fh;
