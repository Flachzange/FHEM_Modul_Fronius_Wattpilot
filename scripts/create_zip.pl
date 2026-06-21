#!/usr/bin/env perl
use strict;
use warnings;

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use File::Find qw(find);
use File::Spec;

my ($source_dir, $archive_path, $epoch) = @ARGV;
die "Usage: $0 <source-dir> <archive> <epoch>\n"
    unless defined $source_dir && defined $archive_path && defined $epoch;

my @files;
find(
    {
      no_chdir => 1,
      wanted   => sub {
        return unless -f $File::Find::name;
        push @files, $File::Find::name;
      },
    },
    $source_dir
);
@files = sort @files;

my $zip = Archive::Zip->new;
for my $path (@files) {
    my $relative = File::Spec->abs2rel($path, File::Spec->catdir($source_dir, '..'));
    $relative =~ s{\\}{/}g;
    my $member = $zip->addFile($path, $relative)
        or die "Cannot add $path to archive\n";
    $member->setLastModFileDateTimeFromUnix($epoch);
    $member->desiredCompressionMethod(COMPRESSION_DEFLATED);
}

$zip->writeToFileNamed($archive_path) == AZ_OK
    or die "Cannot write $archive_path\n";
