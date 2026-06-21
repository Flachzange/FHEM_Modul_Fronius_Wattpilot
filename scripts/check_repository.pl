#!/usr/bin/env perl
use strict;
use warnings;

use lib 'scripts/lib';

use Encode qw(decode FB_CROAK);
use File::Find qw(find);
use JSON qw(decode_json);
use Wattpilot::RepositoryCheck qw(contains_mojibake);

my @required = qw(
    72_Wattpilot.pm AGENTS.md ARCHITECTURE.md CHANGELOG.md TESTING.md
    REVIEW-CHECKLIST.md .gitignore .github/pull_request_template.md
    .github/workflows/ci.yml t/72_Wattpilot.t t/lib/DevIo.pm
    t/lib/FHEM/Meta.pm t/repository_text_check.t
    t/fixtures/fullStatus-flex-43.4.json
    t/fixtures/deltaStatus-flex-43.4.json scripts/ci.sh
    scripts/check_commandref.pl scripts/check_repository.pl
    scripts/check_meta.pl scripts/build-release.sh scripts/verify-release.sh
    scripts/create_zip.pl scripts/check_reproducible_release.sh
    scripts/lib/Wattpilot/RepositoryCheck.pm
    docs/PROTOCOL-SOURCES.md
);

my @missing = grep { !-f $_ } @required;
die "Missing required files: @missing\n" if @missing;

open my $git_fh, '-|', 'git', 'ls-files', '-z', '--'
    or die "Cannot list tracked files: $!\n";
binmode $git_fh;
local $/;
my $tracked_raw = <$git_fh>;
close $git_fh or die "git ls-files failed\n";

my @tracked = split /\0/, $tracked_raw;
my @maintained_text;
for my $path (@tracked) {
    push @maintained_text, $path
        if $path =~ /(?:\.md|\.pm|\.pl|\.sh|\.yml|\.yaml|\.json)\z/
            || $path =~ /(?:^|\/)(?:LICENSE|\.gitignore)\z/;
}

for my $path (@maintained_text) {
    open my $text_fh, '<:raw', $path or die "Cannot read $path: $!\n";
    local $/;
    my $bytes = <$text_fh>;
    close $text_fh;

    my $text = eval { decode('UTF-8', $bytes, FB_CROAK) };
    die "Invalid UTF-8 in $path: $@" if $@;
    die "Mojibake or Unicode replacement character in $path\n"
        if contains_mojibake($text);
}

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

my @tracked_dist = grep { m{^dist/} } @tracked;
die "Generated dist files must not be committed: @tracked_dist\n" if @tracked_dist;

open my $ignore_fh, '<', '.gitignore' or die "Cannot read .gitignore: $!\n";
local $/;
my $ignore = <$ignore_fh>;
close $ignore_fh;
die "dist/ must remain ignored\n" unless $ignore =~ m{^/dist/\s*$}m;

print "Repository and UTF-8 checks passed (" . scalar(@maintained_text) . " maintained text files)\n";
