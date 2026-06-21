#!/usr/bin/env perl
use strict;
use warnings;

my $module = '72_Wattpilot.pm';
open my $fh, '<', $module or die "Cannot read $module: $!\n";
local $/;
my $source = <$fh>;
close $fh;

for my $language (qw(html html_DE)) {
    my ($section) = $source =~ /=begin\s+\Q$language\E\s+(.*?)=end\s+\Q$language\E/s;
    die "Missing $language command reference\n" unless defined $section && length $section;

    my @anchors = $section =~ /<a\s+name=["']([^"']+)["']/gi;
    die "No anchors in $language command reference\n" unless @anchors;

    my %seen;
    my @duplicates = grep { $seen{$_}++ } @anchors;
    die "Duplicate anchors in $language: @duplicates\n" if @duplicates;
}

print "Command reference checks passed\n";

