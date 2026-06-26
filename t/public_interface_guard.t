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
    'pvBatterySoC', 'pvBatteryPower', 'deviceUptime',
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
    state firmwareVersion deviceType deviceModel deviceSubType deviceVariant helloProtocol statusProtocol
    authHashMode carState configForceState configChargingCurrent
    configChargingMode chargingAllowed chargingDecisionCode chargingDecision
    chargingDecisionInternalCode chargingDecisionInternal errorCode configMaximumCurrentLimit
    temperatureCurrentLimit configMinimumChargingCurrent configPvSurplusStartPower
    configPvSurplusEnabled configZeroFeedInEnabled configPvControlPreference configPhaseSwitchMode
    configThreePhaseSwitchPower configPhaseSwitchDelay configMinimumPhaseSwitchInterval
    configMinimumChargeTime configChargingPauseAllowed configMinimumChargingPauseDuration
    configMinimumChargingInterval pvBatteryModeCode deviceRebootCount uptime
    diag_fbuf_akkuSOC diag_fbuf_pAkku diag_fbuf_pGrid diag_fbuf_pPv diag_pvopt_averagePGrid diag_pvopt_averagePPv
    diag_pvopt_averagePAkku diag_pvopt_averagePOhmpilot diag_pvopt_deltaP
    diag_pvopt_deltaA diag_pvopt_specialCase diag_fbuf_pAcTotal
    diag_fbuf_ohmpilotState diag_fbuf_ohmpilotTemperature configPvBatteryChargeAboveSoC
    configPvBatteryDischargeEnabled configPvBatteryDischargeUntilSoC
    configPvBatteryDischargeTimeLimitEnabled configPvBatteryDischargeStartTime
    configPvBatteryDischargeStopTime configNextTripTime
    energyTotal energySincePlugIn
    voltageL1 voltageL2 voltageL3 currentL1 currentL2 currentL3
    powerL1 powerL2 powerL3 power lastCommandRequestId
    lastCommandStatus lastCommandError
);
my @public_commands = qw(
    password chargingCurrent forceState chargingMode pvSurplusStartPower
    pvSurplusEnabled zeroFeedInEnabled pvControlPreference phaseSwitch
    minimumCharging chargingPauseAllowed reconnect
    nextTripTime
);

my @migration_pairs = (
    [ 'state', 'state' ],
    [ 'version', 'firmwareVersion' ],
    [ 'authHashMode', 'authHashMode' ],
    [ 'CarState', 'carState' ],
    [ 'Laden_starten', 'configForceState' ],
    [ 'Strom', 'configChargingCurrent' ],
    [ 'Modus', 'configChargingMode' ],
    [ 'Zeit_NextTrip', 'configNextTripTime' ],
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

my @readme_docs = (
    [ 'README.md', read_utf8(File::Spec->catfile($root, 'README.md')) ],
    [ 'README_en.md', read_utf8(File::Spec->catfile($root, 'README_en.md')) ],
);
my ($commandref_en) = $source =~ /=begin\s+html\s+(.*?)=end\s+html/s;
my ($commandref_de) = $source =~ /=begin\s+html_DE\s+(.*?)=end\s+html_DE/s;
ok(defined($commandref_en), 'English commandref is extractable for interface guard');
ok(defined($commandref_de), 'German commandref is extractable for interface guard');
my @commandref_docs = (
    [ 'English commandref', $commandref_en // '' ],
    [ 'German commandref', $commandref_de // '' ],
);
my @active_docs = (@readme_docs, @commandref_docs);

my $markdown_old = qr/`(?:$old_pattern)`/;
my $html_old = qr/<code>(?:$old_pattern)<\/code>/;

for my $entry (@readme_docs) {
    my ($label, $original) = @$entry;
    unlike($original, qr/<!-- (?:BEGIN|END) 2\.0 migration names -->/,
        "$label contains no embedded migration matrix");
    unlike($original, $markdown_old,
        "$label contains no exact old Markdown public-interface token");
    my @bad_table_code_spans;
    for my $line (split /\n/, $original) {
        next if $line !~ /^\|/;
        while ($line =~ /`([^`]*)`/g) {
            push @bad_table_code_spans, $line if $1 =~ /(?<!\\)\|/;
        }
    }
    is_deeply(\@bad_table_code_spans, [],
        "$label contains no unescaped pipe inside a code span in a Markdown table row");
}

for my $entry (@commandref_docs) {
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
}

for my $entry (@active_docs) {
    my ($label, $original) = @$entry;
    my $active = strip_migration_names($original);
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
unlike($readme_de, qr/Version 2\.\d+\.\d+|Reading bis 2\.0\.6/,
    'German README contains no embedded version-by-version changelog or migration table');
unlike($readme_en, qr/Version 2\.\d+\.\d+|Reading through 2\.0\.6/i,
    'English README contains no embedded version-by-version changelog or migration table');
like($readme_de, qr/Seriennummer.*kryptografischer Eingabewert.*PBKDF2.*bcrypt/s,
    'German README explains the serial-number role in both authentication modes');
like($readme_en, qr/serial.*cryptographic input.*PBKDF2.*bcrypt/s,
    'English README explains the serial-number role in both authentication modes');
like($readme_de, qr/\| Authentifizierung \| PBKDF2;.*\| Ausschlie\x{00DF}lich bcrypt;/s,
    'German README distinguishes legacy PBKDF2 from Flex bcrypt-only authentication');
like($readme_en, qr/\| Authentication \| PBKDF2;.*\| bcrypt only;/s,
    'English README distinguishes legacy PBKDF2 from Flex bcrypt-only authentication');
unlike($readme_de, qr/Wattpilot Flex.*(?:PBKDF2 oder bcrypt|bcrypt oder PBKDF2)/s,
    'German README does not present PBKDF2 as a supported Flex authentication mode');
unlike($readme_en, qr/Wattpilot Flex.*(?:PBKDF2 or bcrypt|bcrypt or PBKDF2)/s,
    'English README does not present PBKDF2 as a supported Flex authentication mode');
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
like($commandref_en,
    qr/chargingCurrent.*min\(32, configMaximumCurrentLimit\).*dynamic slider maximum/s,
    'English commandref documents the dynamic charging-current upper bound');
like($commandref_de,
    qr/chargingCurrent.*min\(32, configMaximumCurrentLimit\).*dynamische Slider-Obergrenze/s,
    'German commandref documents the dynamic charging-current upper bound');
like($readme_en,
    qr/configMaximumCurrentLimit.*dynamic upper bound.*capped at 32 A/s,
    'English README documents the device-confirmed charging-current bound');
like($readme_de,
    qr/configMaximumCurrentLimit.*dynamische Obergrenze.*maximal 32 A/s,
    'German README documents the device-confirmed charging-current bound');
like($protocol_doc,
    qr/local FHEM upper bound.*does not add an `ama` setter/s,
    'Flex protocol documentation keeps the ama evidence boundary explicit');
like($protocol_sources,
    qr/local FHEM safety\/UX constraint.*adds no `ama` setter/s,
    'protocol provenance records the local-only ama use');
like($readme_en,
    qr/first valid authenticated `fullStatus` or `deltaStatus` input completes initialization.*`partial=true` describes snapshot completeness only/s,
    'English README documents partial fullStatus initialization');
like($readme_de,
    qr/authentifizierte `fullStatus`- oder `deltaStatus`-Input.*Initialisierung.*`partial=true`/s,
    'German README documents partial fullStatus initialization');
like($commandref_en,
    qr/first valid authenticated <code>fullStatus<\/code> or <code>deltaStatus<\/code>.*<code>partial=true<\/code>.*completes initialization/s,
    'English commandref documents partial fullStatus initialization');
like($commandref_de,
    qr/authentifizierte <code>fullStatus<\/code> oder <code>deltaStatus<\/code>.*<code>partial=true<\/code>.*Initialisierung/s,
    'German commandref documents partial fullStatus initialization');
like($readme_en,
    qr/Changing a positive value to `0`, or deleting the attribute, immediately publishes already queued dirty owners.*currently eligible/s,
    'English README documents interval-to-zero flush semantics');
like($readme_de,
    qr/positiver Wert auf `0`.*Attribut gel.*gepufferte.*Dirty-Gruppen.*sofort gemeinsam/s,
    'German README documents interval-to-zero flush semantics');
like($readme_en,
    qr/With either attribute value.*one real `nrg`.*may bypass the clock once/s,
    'English README documents the bounded idle refresh for both attribute values');
like($readme_de,
    qr/Bei beiden Attributwerten.*ein echtes `nrg`.*den Takt einmalig umgehen/s,
    'German README documents the bounded idle refresh for both attribute values');
like($protocol_sources,
    qr/ordinary EOF.*DevIo_Disconnected.*ReadyFn.*WebSocket Close frame.*DevIo_CloseDev.*one module reconnect/s,
    'protocol provenance records distinct DevIo reconnect ownership paths');
my $architecture_doc = read_utf8(File::Spec->catfile($root, 'ARCHITECTURE.md'));
like($architecture_doc,
    qr/0ae38bf79d19d8d598c065bf84b3990b33063c4b.*Ordinary EOF.*DevIoJustClosed.*WebSocket Close.*exactly one guarded module reconnect/s,
    'architecture pins and documents DevIo close-frame ownership');
like($commandref_en,
    qr/connection lost.*device disabled.*credentials changed.*authentication aborted.*lifecycle timeout.*reconnect requested.*definition changed.*session replaced/s,
    'English commandref documents every stable session-finalization reason');
like($commandref_de,
    qr/connection lost.*device disabled.*credentials changed.*authentication aborted.*lifecycle timeout.*reconnect requested.*definition changed.*session replaced/s,
    'German commandref documents every stable session-finalization reason');

for my $entry (@active_docs) {
    my ($label, $text) = @$entry;
    like($text, qr/reconnect/s,
        "$label documents the manual reconnect command");
    like($text, qr/(?:not|kein).*fullStatus.*request|fullStatus.*(?:not|kein).*request/is,
        "$label states that reconnect is not a fullStatus request");
    like($text, qr/minimumCharging.*interval/s,
        "$label documents the grouped public mci command path");
    like($text, qr/phaseSwitch.*(?:mode|delay|minInterval|threePhasePower)/s,
        "$label documents the grouped phaseSwitch command path");
}
like($readme_en, qr/minimumCharging interval.*Forced charging interval/s,
    'English README distinguishes grouped mci command from Fronius UI terminology');
like($readme_de, qr/minimumCharging interval.*Forced charging interval|configMinimumChargingInterval.*Zwangsladeintervall/s,
    'German README distinguishes grouped mci command from Fronius UI terminology');
like($commandref_en, qr/reconnect.*not a <code>fullStatus<\/code> request/s,
    'English commandref does not misrepresent reconnect as polling');
like($commandref_de, qr/reconnect.*kein <code>fullStatus<\/code>-Request/s,
    'German commandref does not misrepresent reconnect as polling');
like($protocol_sources, qr/No pinned Wattpilot-specific source documents a <code>|No pinned Wattpilot-specific source documents a `fullStatus`/s,
    'protocol provenance records the missing fullStatus request evidence');

my $testing_doc = read_utf8(File::Spec->catfile($root, 'TESTING.md'));
like($testing_doc, qr/0ae38bf79d19d8d598c065bf84b3990b33063c4b/s,
    'testing documentation records the current FHEM source audit revision');
like($testing_doc, qr/successful asynchronous .*opened.*before invoking the module callback/is,
    'testing documentation records the audited DevIo opened-before-callback side effect');

done_testing;
