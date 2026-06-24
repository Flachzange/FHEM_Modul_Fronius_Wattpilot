use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json);
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
        NAME => 'operationalWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000201',
        DeviceName => 'ws:192.0.2.201:80/ws',
        SERIAL => '2000000000000201',
        STATE => 'connected',
        TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

my %expected_from_observed = (
    chargingAllowed => 0,
    chargingDecisionCode => 23,
    chargingDecision => 'notChargingBecausePhaseSwitch',
    chargingDecisionInternalCode => 27,
    chargingDecisionInternal => 'notChargingBecauseLoadManagementDoesntWant',
    errorCode => 0,
    configMaximumCurrentLimit => 32,
    temperatureCurrentLimit => 32,
    configMinimumChargingCurrent => 6,
    configPvSurplusStartPower => 1400,
);

my $fixture_path = File::Spec->catfile(
    $root, 't', 'fixtures', 'fullStatus-flex-observed.json');
open my $fixture_fh, '<:raw', $fixture_path
    or die "Cannot read $fixture_path: $!";
local $/;
my $fixture = decode_json(<$fixture_fh>);
close $fixture_fh;

my $hash = fresh_device();
ok(main::Wattpilot_DispatchMessage($hash, $fixture),
    'sanitized observed Flex fullStatus is dispatched');
for my $reading (sort keys %expected_from_observed) {
    is(reading_value($hash, $reading), $expected_from_observed{$reading},
        "observed Flex field updates $reading");
}

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        alw => JSON::true,
        modelStatus => 24,
    },
});
is(reading_value($hash, 'chargingAllowed'), 1,
    'device-supplied true updates chargingAllowed to 1');
is(reading_value($hash, 'chargingDecisionCode'), 24,
    'a later raw decision code replaces the prior code');
is(reading_value($hash, 'chargingDecision'),
    'notChargingBecauseMinPauseDuration',
    'a later decision code updates its text reading');
is(reading_value($hash, 'chargingDecisionInternalCode'), 27,
    'an omitted delta field preserves its existing raw reading');
is(reading_value($hash, 'chargingDecisionInternal'),
    'notChargingBecauseLoadManagementDoesntWant',
    'an omitted delta field preserves its existing text reading');
is(reading_value($hash, 'configMaximumCurrentLimit'), 32,
    'another omitted operational field remains unchanged');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        alw => undef,
        modelStatus => undef,
        msi => undef,
        err => undef,
        ama => undef,
        amt => undef,
        mca => undef,
        fst => undef,
    },
});
is(reading_value($hash, 'chargingAllowed'), 1,
    'JSON null does not clear chargingAllowed');
is(reading_value($hash, 'chargingDecisionCode'), 24,
    'JSON null does not clear a decision code');
is(reading_value($hash, 'chargingDecision'),
    'notChargingBecauseMinPauseDuration',
    'JSON null does not clear a decision text');
is(reading_value($hash, 'configMinimumChargingCurrent'), 6,
    'JSON null does not clear a current-limit reading');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        alw => 2,
        modelStatus => 'paused',
        msi => [],
        err => {},
        ama => 31.5,
        amt => '32A',
        mca => JSON::true,
        fst => -1,
    },
});
is(reading_value($hash, 'chargingAllowed'), 1,
    'invalid boolean input cannot replace chargingAllowed');
is(reading_value($hash, 'chargingDecisionCode'), 24,
    'invalid decision input cannot replace the raw code');
is(reading_value($hash, 'chargingDecision'),
    'notChargingBecauseMinPauseDuration',
    'invalid decision input cannot replace the text reading');
is(reading_value($hash, 'chargingDecisionInternalCode'), 27,
    'invalid internal decision input cannot replace the raw code');
is(reading_value($hash, 'chargingDecisionInternal'),
    'notChargingBecauseLoadManagementDoesntWant',
    'invalid internal decision input cannot replace the text reading');
is(reading_value($hash, 'errorCode'), 0,
    'invalid error input cannot replace the raw code');
is(reading_value($hash, 'configMaximumCurrentLimit'), 32,
    'non-integer maximum-current input is ignored');
is(reading_value($hash, 'temperatureCurrentLimit'), 32,
    'unit-suffixed temperature-current input is ignored');
is(reading_value($hash, 'configMinimumChargingCurrent'), 6,
    'boolean minimum-current input is ignored');
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'negative start-power input is ignored');

$hash = fresh_device();
$attr{$hash->{NAME}}{interval} = 300;
$attr{$hash->{NAME}}{update_while_idle} = 0;
$hash->{LAST_UPDATE} = DevIo::gettimeofday();
main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        car => 1,
        alw => JSON::false,
        modelStatus => 0,
        msi => 0,
        err => 0,
        ama => 0,
        amt => 0,
        mca => 0,
        fst => 0,
        nrg => [230, 230, 230, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    },
});
for my $reading (qw(
    chargingAllowed chargingDecisionCode chargingDecisionInternalCode
    errorCode configMaximumCurrentLimit temperatureCurrentLimit
    configMinimumChargingCurrent configPvSurplusStartPower
)) {
    is(reading_value($hash, $reading), 0,
        "$reading preserves an authoritative device-supplied zero");
}
is(reading_value($hash, 'chargingDecision'),
    'notChargingBecauseNoChargeCtrlData',
    'modelStatus zero maps to its text decision');
is(reading_value($hash, 'chargingDecisionInternal'),
    'notChargingBecauseNoChargeCtrlData',
    'msi zero maps to its text decision');
ok(!exists $hash->{READINGS}{power},
    'operational readings update while idle electrical readings remain suppressed');

my %decision_text = (
    0 => 'notChargingBecauseNoChargeCtrlData',
    1 => 'notChargingBecauseOvertemperature',
    2 => 'notChargingBecauseAccessControlWait',
    3 => 'chargingBecauseForceStateOn',
    4 => 'notChargingBecauseForceStateOff',
    5 => 'notChargingBecauseScheduler',
    6 => 'notChargingBecauseEnergyLimit',
    7 => 'chargingBecauseAwattarPriceLow',
    8 => 'chargingBecauseAutomaticStopTestLadung',
    9 => 'chargingBecauseAutomaticStopNotEnoughTime',
    10 => 'chargingBecauseAutomaticStop',
    11 => 'chargingBecauseAutomaticStopNoClock',
    12 => 'chargingBecausePvSurplus',
    13 => 'chargingBecauseFallbackGoEDefault',
    14 => 'chargingBecauseFallbackGoEScheduler',
    15 => 'chargingBecauseFallbackDefault',
    16 => 'notChargingBecauseFallbackGoEAwattar',
    17 => 'notChargingBecauseFallbackAwattar',
    18 => 'notChargingBecauseFallbackAutomaticStop',
    19 => 'chargingBecauseCarCompatibilityKeepAlive',
    20 => 'chargingBecauseChargePauseNotAllowed',
    22 => 'notChargingBecauseSimulateUnplugging',
    23 => 'notChargingBecausePhaseSwitch',
    24 => 'notChargingBecauseMinPauseDuration',
    26 => 'notChargingBecauseError',
    27 => 'notChargingBecauseLoadManagementDoesntWant',
    28 => 'notChargingBecauseOcppDoesntWant',
    29 => 'notChargingBecauseReconnectDelay',
    30 => 'notChargingBecauseAdapterBlocking',
    31 => 'notChargingBecauseUnderfrequencyControl',
    32 => 'notChargingBecauseUnbalancedLoad',
    33 => 'chargingBecauseDischargingPvBattery',
    34 => 'notChargingBecauseGridMonitoring',
    35 => 'notChargingBecauseOcppFallback',
);
for my $code (sort { $a <=> $b } keys %decision_text) {
    $hash = fresh_device();
    main::Wattpilot_UpdateReadings($hash, { modelStatus => $code });
    is(reading_value($hash, 'chargingDecision'), $decision_text{$code},
        "modelStatus $code maps to $decision_text{$code}");
}
for my $code (21, 25, 99) {
    $hash = fresh_device();
    main::Wattpilot_UpdateReadings($hash, { modelStatus => $code, msi => $code });
    is(reading_value($hash, 'chargingDecision'), "unknown:$code",
        "unknown modelStatus $code remains explicit");
    is(reading_value($hash, 'chargingDecisionInternal'), "unknown:$code",
        "unknown msi $code remains explicit");
}

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { modelStatus => 12, msi => 23 });
is(reading_value($hash, 'chargingDecision'), 'chargingBecausePvSurplus',
    'modelStatus and msi are mapped independently');
is(reading_value($hash, 'chargingDecisionInternal'),
    'notChargingBecausePhaseSwitch',
    'internal decision uses the same compatibility enum independently');

done_testing;
