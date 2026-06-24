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

sub migration_names_section {
    my ($text) = @_;
    my ($section) = $text =~ /<!-- BEGIN 2\.0 migration names -->(.*?)<!-- END 2\.0 migration names -->/s;
    return $section;
}

sub strip_migration_names {
    my ($text) = @_;
    $text =~ s/<!-- BEGIN 2\.0 migration names -->.*?<!-- END 2\.0 migration names -->//gs;
    return $text;
}

sub decode_html_code {
    my ($value) = @_;
    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/&amp;/&/g;
    return $value;
}

sub migration_pairs {
    my ($section) = @_;
    my %pairs;

    if ($section =~ /<tr>/) {
        while ($section =~ m{<tr>(.*?)</tr>}gs) {
            my @tokens = map { decode_html_code($_) }
                ($1 =~ m{<code>(.*?)</code>}g);
            next if @tokens != 2;
            $pairs{$tokens[0] . "\0" . $tokens[1]}++;
        }
    }
    else {
        for my $line (split /\n/, $section) {
            my @tokens = $line =~ /`([^`]*)`/g;
            next if @tokens != 2;
            $pairs{$tokens[0] . "\0" . $tokens[1]}++;
        }
    }

    return \%pairs;
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
    chargingMode chargingAllowed chargingDecisionCode chargingDecision
    chargingDecisionInternalCode chargingDecisionInternal errorCode maximumCurrentLimit
    temperatureCurrentLimit minimumChargingCurrent nextTripTime
    energyTotal energySincePlugIn
    voltageL1 voltageL2 voltageL3 currentL1 currentL2 currentL3
    powerL1 powerL2 powerL3 power lastCommandRequestId
    lastCommandStatus lastCommandError
);
my @public_commands = qw(
    password chargingCurrent forceState chargingMode nextTripTime
);

my @migration_pairs = (
    [ 'state', 'state' ],
    [ 'version', 'firmwareVersion' ],
    [ 'authHashMode', 'authHashMode' ],
    [ 'CarState', 'carState' ],
    [ 'Laden_starten', 'forceState' ],
    [ 'Strom', 'chargingCurrent' ],
    [ 'Modus', 'chargingMode' ],
    [ 'Zeit_NextTrip', 'nextTripTime' ],
    [ 'EnergyTotal', 'energyTotal' ],
    [ 'Energie_seit_Anstecken', 'energySincePlugIn' ],
    [ 'Voltage_L1', 'voltageL1' ],
    [ 'Voltage_L2', 'voltageL2' ],
    [ 'Voltage_L3', 'voltageL3' ],
    [ 'Current_L1', 'currentL1' ],
    [ 'Current_L2', 'currentL2' ],
    [ 'Current_L3', 'currentL3' ],
    [ 'Power_L1', 'powerL1' ],
    [ 'Power_L2', 'powerL2' ],
    [ 'Power_L3', 'powerL3' ],
    [ 'power', 'power' ],
    [ 'lastCommandRequestId', 'lastCommandRequestId' ],
    [ 'lastCommandStatus', 'lastCommandStatus' ],
    [ 'lastCommandError', 'lastCommandError' ],
    [ 'Password <secret>', 'password <secret>' ],
    [ 'Strom <6..32>', 'chargingCurrent <6..32>' ],
    [ 'Laden_starten Start|Stop', 'forceState neutral|off|on' ],
    [ 'Modus Default|Eco|NextTrip', 'chargingMode default|eco|nextTrip' ],
    [ 'Zeit_NextTrip HH:MM', 'nextTripTime HH:MM' ],
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

    my $migration = migration_names_section($original);
    ok(defined($migration), "$label migration matrix is extractable");
    my $pairs = migration_pairs($migration // '');
    is(scalar keys %$pairs, scalar @migration_pairs,
        "$label migration matrix contains exactly the 23 historical reading mappings and five command mappings");
    for my $pair (@migration_pairs) {
        my ($old, $new) = @$pair;
        is($pairs->{$old . "\0" . $new}, 1,
            "$label maps $old to $new exactly once");
    }

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

my $readme_de = $active_docs[0][1];
my $readme_en = $active_docs[1][1];
like($commandref_en, qr/exact relationship, evaluation order, precedence, and any role of <code>cpDisabledRequest<\/code> are not confirmed/s,
    'English commandref documents the unconfirmed modelStatus/msi relationship');
like($commandref_en, qr/does not claim that <code>modelStatus<\/code> is necessarily the final\/effective decision/s,
    'English commandref avoids a final-decision claim');
like($commandref_de, qr/<code>cpDisabledRequest<\/code>.*Wattpilot Flex.*nicht best/s,
    'German commandref documents the unconfirmed modelStatus/msi relationship');
like($commandref_de, qr/<code>modelStatus<\/code>.*abschlie.*wirksame Entscheidung/s,
    'German commandref avoids a final-decision claim');
like($readme_en, qr/The exact relationship, evaluation order, precedence, and any role of `cpDisabledRequest` are not confirmed/s,
    'English README preserves the decision-field uncertainty');
like($readme_de, qr/`cpDisabledRequest`.*Wattpilot Flex.*nicht best/s,
    'German README preserves the decision-field uncertainty');

my $protocol_doc = read_utf8(File::Spec->catfile($root, 'docs', 'WATTPILOT-FLEX-JSON-API.md'));
like($protocol_doc, qr/no causal chain is inferred/s,
    'Flex protocol documentation forbids an unsupported causal-chain inference');
my $protocol_sources = read_utf8(File::Spec->catfile($root, 'docs', 'PROTOCOL-SOURCES.md'));
like($protocol_sources, qr/differing values are retained as independent device-supplied diagnostics without inferring a causal chain/s,
    'protocol provenance records the modelStatus/msi evidence limit');

done_testing;
