use strict;
use warnings;

use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
open my $module_fh, '<:encoding(UTF-8)', $module or die "Cannot read $module: $!";
local $/;
my $source = <$module_fh>;
close $module_fh;
my ($runtime) = split /\n1;\n/, $source, 2;

my @old_exact_strings = (
    'version', 'CarState', 'Laden_starten', 'Strom', 'Modus',
    'Zeit_NextTrip', 'EnergyTotal', 'Energie_seit_Anstecken',
    'Voltage_L1', 'Voltage_L2', 'Voltage_L3',
    'Current_L1', 'Current_L2', 'Current_L3',
    'Power_L1', 'Power_L2', 'Power_L3',
    'Password', 'Start', 'Stop', 'Default', 'Eco', 'NextTrip',
    'Unknown', 'password stored', 'password missing', 'credential error',
    'connection failed', 'auth_failed', 'auth_timeout',
    'initialization_timeout', 'auth_sequence_invalid',
    'auth_config_missing', 'auth_challenge_invalid',
    'auth_hash_unsupported', 'auth_hash_failed',
    'auth_hash_store_failed', 'auth_nonce_failed',
);
my $old_pattern = join '|', map { quotemeta($_) } @old_exact_strings;
my $quoted_old = qr/(['"])(?:$old_pattern)\1/;

unlike($runtime, $quoted_old,
    'runtime contains no exact old public interface string');

my @test_files;
find(sub {
    return if !-f $_;
    push @test_files, $File::Find::name if /\.t\z/;
}, File::Spec->catdir($root, 't'));

for my $path (sort @test_files) {
    next if $path =~ /public_interface_guard\.t\z/;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    $text =~ s/# BEGIN 2\.0 negative controls for removed public names.*?# END 2\.0 negative controls for removed public names//s;
    unlike($text, $quoted_old,
        "$path contains no exact old public interface string outside marked negative controls");
}

done_testing;
