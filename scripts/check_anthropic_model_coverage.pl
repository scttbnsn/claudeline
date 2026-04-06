#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use HTTP::Tiny;
use JSON::PP qw(decode_json);

sub usage {
    die "usage: $0 --manifest PATH [--models-json PATH]\n";
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

sub load_manifest {
    my ($path) = @_;
    my $doc = decode_json(slurp($path));
    die "manifest at $path is missing pricing rules\n"
        unless ref($doc->{rules}) eq 'ARRAY';

    my @rules = map {
        my $match_kind = $_->{match_kind} // '';
        my $match_value = $_->{match_value} // '';
        die "invalid manifest rule in $path\n"
            unless ($match_kind eq 'exact' || $match_kind eq 'regex') && length $match_value;

        {
            match_kind => $match_kind,
            match_value => $match_value,
            compiled_regex => $match_kind eq 'regex'
                ? compile_manifest_regex($match_value, $path)
                : undef,
        };
    } @{$doc->{rules}};

    return \@rules;
}

sub model_is_covered {
    my ($rules, $model_id) = @_;
    for my $rule (@$rules) {
        if ($rule->{match_kind} eq 'exact' && $model_id eq $rule->{match_value}) {
            return 1;
        }
        if ($rule->{match_kind} eq 'regex' && $model_id =~ $rule->{compiled_regex}) {
            return 1;
        }
    }
    return 0;
}

sub load_models_json {
    my ($path) = @_;
    return decode_json(slurp($path)) if $path;

    my $api_key = $ENV{ANTHROPIC_API_KEY}
        or die "ANTHROPIC_API_KEY is required when --models-json is not provided\n";

    my $http = HTTP::Tiny->new(
        agent => "claudeline-pricing-checker/1.0",
        default_headers => {
            'x-api-key' => $api_key,
            'anthropic-version' => '2023-06-01',
        },
        timeout => 20,
    );
    my $response = $http->get('https://api.anthropic.com/v1/models');
    die "failed to fetch https://api.anthropic.com/v1/models: $response->{status} $response->{reason}\n"
        unless $response->{success};
    return decode_json($response->{content});
}

my $manifest_path = '';
my $models_json_path = '';

GetOptions(
    'manifest=s' => \$manifest_path,
    'models-json=s' => \$models_json_path,
) or usage();

usage() unless $manifest_path;

my $rules = load_manifest($manifest_path);
my $models_doc = load_models_json($models_json_path);
my $models = $models_doc->{data};

die "models payload is missing a data array\n" unless ref($models) eq 'ARRAY';

my @uncovered;
for my $entry (@$models) {
    next unless ref($entry) eq 'HASH';
    my $model_id = $entry->{id};
    next unless defined $model_id && length $model_id;

    push @uncovered, $model_id unless model_is_covered($rules, $model_id);
}

if (@uncovered) {
    print "Uncovered Anthropic model ids:\n";
    print "$_\n" for @uncovered;
    exit 1;
}

print "ok\n";
