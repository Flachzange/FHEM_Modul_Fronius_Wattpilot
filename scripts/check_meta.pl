#!/usr/bin/env perl
use strict;
use warnings;

use CPAN::Meta;
use JSON qw(decode_json);

my $module = shift // '72_Wattpilot.pm';
open my $fh, '<', $module or die "Cannot read $module: $!\n";
local $/;
my $source = <$fh>;
close $fh;

my ($version) = $source =~ /my\s+\$WATTPILOT_VERSION\s*=\s*['"]([^'"]+)['"]\s*;/;
die "Missing central WATTPILOT_VERSION in $module\n" unless defined $version;

my ($json) = $source =~ m{
    =for\s+:application/json;q=META\.json\s+72_Wattpilot\.pm\s*\n
    (\{.*?\})\s*\n
    =end\s+:application/json;q=META\.json
}sx;
die "Missing embedded META.json in $module\n" unless defined $json;

my $meta = eval { decode_json($json) };
die "Invalid embedded META JSON: $@" if $@;

for my $field (qw(name abstract description version release_status author license prereqs resources)) {
    die "META field '$field' is missing\n" unless exists $meta->{$field};
}

die "Unexpected META module name\n"
    unless $meta->{name} eq 'FHEM-Wattpilot'
        && ($meta->{x_fhem_module_name} // '') eq 'Wattpilot';
die "META version '$meta->{version}' differs from source version 'v$version'\n"
    unless $meta->{version} eq "v$version";
die "META release status must be testing\n"
    unless $meta->{release_status} eq 'testing';
die "META license must be gpl_2 with SPDX extension GPL-2.0-or-later\n"
    unless ref($meta->{license}) eq 'ARRAY'
        && @{$meta->{license}} == 1
        && $meta->{license}[0] eq 'gpl_2'
        && ($meta->{x_spdx_license} // '') eq 'GPL-2.0-or-later';
die "Original author must be exactly Dennis Gramespacher <>\n"
    unless ref($meta->{author}) eq 'ARRAY'
        && @{$meta->{author}} == 1
        && $meta->{author}[0] eq 'Dennis Gramespacher <>';
die "Maintainer Flachzange is missing\n"
    unless ref($meta->{x_fhem_maintainer}) eq 'ARRAY'
        && grep { $_ eq 'Flachzange' } @{$meta->{x_fhem_maintainer}};
die "GitHub maintainer Flachzange is missing\n"
    unless ref($meta->{x_fhem_maintainer_github}) eq 'ARRAY'
        && grep { $_ eq 'Flachzange' } @{$meta->{x_fhem_maintainer_github}};
die "FHEM support status must be experimental\n"
    unless ($meta->{x_support_status} // '') eq 'experimental';

my $requires = $meta->{prereqs}{runtime}{requires};
die "META runtime prerequisites are missing\n" unless ref($requires) eq 'HASH';
for my $module_name (qw(FHEM FHEM::Meta DevIo JSON Digest::SHA Crypt::PBKDF2 Data::Dumper)) {
    die "META prerequisite '$module_name' is missing\n" unless exists $requires->{$module_name};
}
die "Optional Crypt::Bcrypt prerequisite is missing\n"
    unless exists $meta->{prereqs}{runtime}{recommends}{'Crypt::Bcrypt'};

my $repository = $meta->{resources}{repository};
die "META repository resource is invalid\n"
    unless ref($repository) eq 'HASH'
        && ($repository->{url} // '') eq 'https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot.git';

my $cpan_meta = eval { CPAN::Meta->new($meta, { lazy_validation => 0 }) };
die "Strict CPAN::Meta validation failed: $@" if $@ || !$cpan_meta;

print "META checks passed with strict CPAN::Meta validation (source $version, META v$version)\n";
