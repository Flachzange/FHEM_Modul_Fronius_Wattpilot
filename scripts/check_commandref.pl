#!/usr/bin/env perl
use strict;
use warnings;

use lib 't/lib';

our ($readingFnAttributes, %modules, %defs, %attr);

my $module = '72_Wattpilot.pm';
open my $fh, '<:encoding(UTF-8)', $module or die "Cannot read $module: $!\n";
local $/;
my $source = <$fh>;
close $fh;

require "./$module";
my $interface = Wattpilot_InterfaceSnapshot();
my %registration;
Wattpilot_Initialize(\%registration);

my @readings = sort values %{ $interface->{readings} };
my @commands = sort values %{ $interface->{commands} };
my @attributes;
for my $entry (split /\s+/, $registration{AttrList} // '') {
    next if !length $entry;
    $entry =~ s/:.*\z//;
    next if $entry eq ($readingFnAttributes // '');
    push @attributes, $entry;
}
@attributes = sort @attributes;

sub commandref_section {
    my ($language) = @_;
    my ($section) = $source =~ /=begin\s+\Q$language\E\s+(.*?)=end\s+\Q$language\E/s;
    die "Missing $language command reference\n" unless defined $section && length $section;
    return $section;
}

sub anchor_chunk {
    my ($section, $start, $end) = @_;
    my $start_re = qr/<a\s+name=["']\Q$start\E["'][^>]*><\/a>/i;
    my $end_re = defined $end
        ? qr/<a\s+name=["']\Q$end\E["'][^>]*><\/a>/i
        : undef;
    my ($tail) = $section =~ /$start_re(.*)/s;
    die "Missing commandref anchor $start\n" unless defined $tail;
    if ($end_re) {
        $tail =~ s/$end_re.*\z//s
            or die "Missing commandref anchor $end after $start\n";
    }
    return $tail;
}

my %anchors_by_language;
for my $language (qw(html html_DE)) {
    my $section = commandref_section($language);
    my @anchors = $section =~ /<a\s+name=["']([^"']+)["']/gi;
    die "No anchors in $language command reference\n" unless @anchors;

    my %seen;
    my @duplicates = grep { $seen{$_}++ } @anchors;
    die "Duplicate anchors in $language: @duplicates\n" if @duplicates;
    $anchors_by_language{$language} = \@anchors;

    my $set_chunk = anchor_chunk($section, 'Wattpilot-set', 'Wattpilot-get');
    my $attr_chunk = anchor_chunk($section, 'Wattpilot-attr', 'Wattpilot-readings');
    my $reading_chunk = anchor_chunk($section, 'Wattpilot-readings', undef);

    for my $command (@commands) {
        die "Missing public Set command '$command' in $language command reference\n"
            unless $set_chunk =~ /<code>[^<]*\b\Q$command\E(?:\s|&lt;|<\/code>)/;
    }
    for my $attribute (@attributes) {
        die "Missing public attribute '$attribute' in $language command reference\n"
            unless $attr_chunk =~ /<code>\Q$attribute\E(?:\s|&lt;|<\/code>)/;
    }
    for my $reading (@readings) {
        die "Missing public reading '$reading' in $language command reference\n"
            unless $reading_chunk =~ /<code>\Q$reading\E(?:\s|,|<\/code>)/;
    }

    for my $removed (qw(debug defaultAmp)) {
        die "Removed attribute '$removed' remains in $language command reference\n"
            if $attr_chunk =~ /<code>\Q$removed\E(?:\s|&lt;|<\/code>)/;
    }
}

die "English and German command reference anchor inventories differ\n"
    unless join("\0", @{ $anchors_by_language{html} })
        eq join("\0", @{ $anchors_by_language{html_DE} });

print "Command reference checks passed ("
    . scalar(@commands) . " commands, "
    . scalar(@attributes) . " attributes, "
    . scalar(@readings) . " readings)\n";
