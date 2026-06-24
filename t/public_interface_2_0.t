use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'interfaceWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000200',
        DeviceName => 'ws:192.0.2.200:80/ws',
        SERIAL => '2000000000000000',
        STATE => 'disconnected',
        TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

my @public_readings = qw(
    state firmwareVersion authHashMode carState forceState chargingCurrent
    chargingMode chargingAllowed chargingDecisionCode chargingDecision
    chargingDecisionInternalCode chargingDecisionInternal errorCode maximumCurrentLimit
    temperatureCurrentLimit minimumChargingCurrent pvSurplusStartPower
    pvSurplusEnabled zeroFeedInEnabled pvControlPreference phaseSwitchMode
    threePhaseSwitchPower phaseSwitchDelay minimumPhaseSwitchInterval
    minimumChargeTime chargingPauseAllowed minimumChargingPauseDuration
    minimumChargingInterval nextTripTime
    energyTotal energySincePlugIn
    voltageL1 voltageL2 voltageL3 currentL1 currentL2 currentL3
    powerL1 powerL2 powerL3 power lastCommandRequestId
    lastCommandStatus lastCommandError
);
my @old_readings = qw(
    version CarState Laden_starten Strom Modus Zeit_NextTrip EnergyTotal
    Energie_seit_Anstecken Voltage_L1 Voltage_L2 Voltage_L3
    Current_L1 Current_L2 Current_L3 Power_L1 Power_L2 Power_L3
);

my $hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
main::readingsSingleUpdate($hash, 'state', 'connected', 1);
main::Wattpilot_DispatchMessage($hash, {
    type => 'hello',
    version => 'synthetic-2.0-firmware',
    devicetype => 'wattpilot',
    protocol => 2,
});
main::readingsSingleUpdate($hash, 'authHashMode', 'pbkdf2', 1);
main::Wattpilot_UpdateReadings($hash, {
    car => 3,
    frc => 0,
    amp => 16,
    lmo => 5,
    alw => 0,
    modelStatus => 23,
    msi => 27,
    err => 0,
    ama => 32,
    amt => 31,
    mca => 6,
    fst => 1400,
    fup => JSON::true(),
    fzf => JSON::false(),
    frm => 0,
    psm => 0,
    spl3 => 5200,
    mpwst => 120000,
    mptwt => 600000,
    fmt => 300000,
    fap => JSON::true(),
    mcpd => 120000,
    mci => 0,
    ftt => 7 * 3600 + 30 * 60,
    eto => 123456,
    wh => 789,
    nrg => [230, 231, 232, 0, 1.1, 2.2, 3.3, 100, 200, 300, 0, 600],
}, 'fullStatus');
main::Wattpilot_SetCommandReadings($hash, 17, 'success', 'none');

is_deeply([sort keys %{$hash->{READINGS}}], [sort @public_readings],
    'one complete runtime scenario exposes exactly the 44 public 2.x readings');
for my $old (@old_readings) {
    ok(!exists $hash->{READINGS}{$old}, "old reading $old is not emitted");
}
my %event_names = map { $_->[1] => 1 } @DevIo::READING_UPDATES;
for my $old (@old_readings) {
    ok(!$event_names{$old}, "no event uses old reading $old");
}

for my $case (
    [0, 'unknown'],
    [1, 'idle'],
    [2, 'charging'],
    [3, 'waitingForCar'],
    [4, 'complete'],
    [5, 'error'],
    [99, 'unknown:99'],
) {
    $hash = fresh_device();
    main::Wattpilot_UpdateReadings($hash, { car => $case->[0] });
    is($hash->{READINGS}{carState}{VAL}, $case->[1],
        "car=$case->[0] maps to $case->[1]");
}

for my $case (
    [0, 'neutral'],
    [1, 'off'],
    [2, 'on'],
    [-1, 'unknown:-1'],
) {
    $hash = fresh_device();
    main::Wattpilot_UpdateReadings($hash, { frc => $case->[0] });
    is($hash->{READINGS}{forceState}{VAL}, $case->[1],
        "frc=$case->[0] maps to $case->[1]");
}

for my $case (
    [3, 'default'],
    [4, 'eco'],
    [5, 'nextTrip'],
    [17, 'unknown:17'],
) {
    $hash = fresh_device();
    main::Wattpilot_UpdateReadings($hash, { lmo => $case->[0] });
    is($hash->{READINGS}{chargingMode}{VAL}, $case->[1],
        "lmo=$case->[0] maps to $case->[1]");
}

done_testing;
