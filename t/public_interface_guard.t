use strict;
use warnings;

use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));

sub read_utf8 {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

sub strip_migration_names {
    my ($text) = @_;
    $text =~ s/<!-- BEGIN 2\.0 migration names -->.*?<!-- END 2\.0 migration names -->//gs;
    return $text;
}

my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
my $source = read_utf8($module);
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
    my $text = read_utf8($path);
    $text =~ s/# BEGIN 2\.0 negative controls for removed public names.*?# END 2\.0 negative controls for removed public names//s;
    unlike($text, $quoted_old,
        "$path contains no exact old public interface string outside marked negative controls");
}

my @public_readings = qw(
    state firmwareVersion authHashMode carState forceState chargingCurrent
    chargingMode nextTripTime energyTotal energySincePlugIn
    voltageL1 voltageL2 voltageL3 currentL1 currentL2 currentL3
    powerL1 powerL2 powerL3 power lastCommandRequestId
    lastCommandStatus lastCommandError
);
my @public_commands = qw(
    password chargingCurrent forceState chargingMode nextTripTime
);

my @active_docs = (
    [ 'README.md', read_utf8(File::Spec->catfile($root, 'README.md')) ],
    [ 'README_en.md', read_utf8(File::Spec->catfile($root, 'README_en.md')) ],
);
my ($commandref_en) = $source =~ /=begin\s+html\s+(.*?)=end\s+html/s;
my ($commandref_de) = $source =~ /=begin\s+html_DE\s+(.*?)=end\s+html_DE/s;
ok(defined($commandref_en), 'English commandref is extractable for interface guard');
ok(defined($commandref_de), 'German commandref is extractable for interface guard');
push @active_docs,
    [ 'English commandref', $commandref_en // '' ],
    [ 'German commandref', $commandref_de // '' ];

my $markdown_old = qr/`(?:$old_pattern)`/;
my $html_old = qr/<code>(?:$old_pattern)<\/code>/;
for my $entry (@active_docs) {
    my ($label, $original) = @$entry;
    my $begin_count = () = $original =~ /<!-- BEGIN 2\.0 migration names -->/g;
    my $end_count = () = $original =~ /<!-- END 2\.0 migration names -->/g;
    is($begin_count, $end_count, "$label has balanced migration-name markers");
    ok($begin_count >= 1, "$label marks its historical 1.x names explicitly");

    my $active = strip_migration_names($original);
    unlike($active, $markdown_old,
        "$label contains no exact old Markdown code token outside migration section");
    unlike($active, $html_old,
        "$label contains no exact old HTML code token outside migration section");

    for my $reading (@public_readings) {
        like($active, qr/\b\Q$reading\E\b/,
            "$label documents public reading $reading");
    }
    for my $command (@public_commands) {
        like($active, qr/\b\Q$command\E\b/,
            "$label documents public command $command");
    }
}

done_testing;
