#!/usr/bin/env perl
use strict;
use warnings;

use File::Find qw(find);
use File::Spec;
use IO::Compress::Zip qw($ZipError ZIP_CM_DEFLATE);
use POSIX qw(tzset);

my ($source_dir, $archive_path, $epoch) = @ARGV;
die "Usage: $0 <source-dir> <archive> <epoch>\n"
    unless defined $source_dir && defined $archive_path && defined $epoch;

local $ENV{TZ} = 'UTC';
tzset();

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
die "No files found below $source_dir\n" unless @files;

my $zip;
for my $index (0 .. $#files) {
    my $path = $files[$index];
    my $relative = File::Spec->abs2rel($path, File::Spec->catdir($source_dir, '..'));
    $relative =~ s{\\}{/}g;

    my %options = (
        Name          => $relative,
        Time          => int($epoch),
        Method        => ZIP_CM_DEFLATE,
        Minimal       => 1,
        CanonicalName => 1,
        ExtAttr       => 0100644 << 16,
    );

    if ($index == 0) {
        $zip = IO::Compress::Zip->new($archive_path, %options)
            or die "Cannot create $archive_path: $ZipError\n";
    } else {
        $zip->newStream(%options)
            or die "Cannot add stream $relative: $ZipError\n";
    }

    open my $fh, '<:raw', $path or die "Cannot open $path: $!\n";
    while (1) {
        my $read = read($fh, my $buffer, 64 * 1024);
        die "Cannot read $path: $!\n" unless defined $read;
        last if $read == 0;
        $zip->write($buffer) or die "Cannot write $relative: $ZipError\n";
    }
    close $fh or die "Cannot close $path: $!\n";
}

$zip->close() or die "Cannot finish $archive_path: $ZipError\n";
