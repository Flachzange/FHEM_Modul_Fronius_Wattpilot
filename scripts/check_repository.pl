#!/usr/bin/env perl
use strict;
use warnings;

use File::Find qw(find);
use JSON qw(decode_json);

my @required = qw(
    72_Wattpilot.pm AGENTS.md ARCHITECTURE.md CHANGELOG.md TESTING.md
    REVIEW-CHECKLIST.md .gitignore .github/pull_request_template.md
    .github/workflows/ci.yml t/72_Wattpilot.t t/lib/DevIo.pm
    t/fixtures/fullStatus-flex-43.4.json
    t/fixtures/deltaStatus-flex-43.4.json scripts/ci.sh
    scripts/check_commandref.pl scripts/check_repository.pl
);

my @missing = grep { !-f $_ } @required;
die "Missing required files: @missing\n" if @missing;

my @fixtures;
find(sub { push @fixtures, $File::Find::name if -f && /\.json\z/ }, 't/fixtures');

my @sensitive_keys = qw(
    serial mac macAddress ip ipAddress password hash ocppUrl downloadUrl signedUrl
);
my %sensitive = map { lc($_) => 1 } @sensitive_keys;

sub inspect_value {
    my ($value, $path) = @_;
    if (ref($value) eq 'HASH') {
        for my $key (keys %$value) {
            die "Sensitive fixture field '$key' in $path\n" if $sensitive{lc($key)};
            inspect_value($value->{$key}, $path);
        }
    }
    elsif (ref($value) eq 'ARRAY') {
        inspect_value($_, $path) for @$value;
    }
    elsif (defined $value && !ref($value)) {
        die "Private IPv4 address in $path\n"
            if $value =~ /\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b/;
        die "URL in fixture $path\n" if $value =~ m{https?://}i;
    }
}

for my $path (@fixtures) {
    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $data = eval { decode_json(<$fh>) };
    close $fh;
    die "Invalid JSON in $path: $@" if $@;
    inspect_value($data, $path);
}

die "Generated dist directory must not be committed\n" if -d 'dist';

print "Repository checks passed\n";

