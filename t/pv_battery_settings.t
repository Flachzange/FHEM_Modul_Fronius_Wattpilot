use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'pvBatteryConfigWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000052',
        DeviceName => 'ws:192.0.2.52:80/ws',
        STATE => 'initializing',
        TEST_OPEN => 1,
        helper => { authenticated => 1, lifecycleState => 'initializing' },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-pv-battery-key';
    return $hash;
}


sub fresh_set_device {
    my $hash = fresh_device();
    $hash->{STATE} = 'connected';
    $hash->{helper}{lifecycleState} = 'connected';
    $hash->{READINGS}{state}{VAL} = 'connected';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer, decode_json($outer->{data}));
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

my $fixture_path = File::Spec->catfile(
    $root, 't', 'fixtures', 'pv-battery-settings-flex-43.4.json');
open my $fixture_fh, '<:raw', $fixture_path
    or die "Cannot read $fixture_path: $!";
local $/;
my $fixture = decode_json(<$fixture_fh>);
close $fixture_fh;

my $hash = fresh_device();
ok(main::Wattpilot_Parse($hash, encode_json($fixture)),
    'sanitized Flex 43.4 battery-setting fullStatus is accepted');
is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 60,
    'fam maps to the Charge above state-of-charge setting');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'pdte maps to the disabled Discharge until switch');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 57,
    'pdt maps to the Discharge until state-of-charge setting');
is(reading_value($hash, 'configPvBatteryDischargeTimeLimitEnabled'), 1,
    'pdle maps to the enabled discharge-time limitation');
is(reading_value($hash, 'configPvBatteryDischargeStartTime'), '07:00',
    'pdls maps seconds since midnight to the app start time');
is(reading_value($hash, 'configPvBatteryDischargeStopTime'), '20:00',
    'pdlo maps seconds since midnight to the app end time');
is(reading_value($hash, 'state'), 'connected',
    'the complete authenticated fullStatus initializes the device');

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus',
    status => {
        fam => 61,
        pdte => JSON::true(),
        pdt => 56,
        pdle => JSON::false(),
        pdls => 26100,
        pdlo => 72900,
    },
})), 'one deltaStatus can update all six identified settings');
is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 61,
    'Charge above state of charge updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 1,
    'Discharge until switch updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 56,
    'Discharge until state of charge updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeTimeLimitEnabled'), 0,
    'discharge-time limitation switch updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeStartTime'), '07:15',
    'discharge start time updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeStopTime'), '20:15',
    'discharge end time updates immediately');

my %stable = map {
    $_ => reading_value($hash, $_)
} qw(
    configPvBatteryChargeAboveSoC
    configPvBatteryDischargeEnabled
    configPvBatteryDischargeUntilSoC
    configPvBatteryDischargeTimeLimitEnabled
    configPvBatteryDischargeStartTime
    configPvBatteryDischargeStopTime
);

for my $case (
    [ 'missing', {} ],
    [ 'null', {
        fam => undef, pdte => undef, pdt => undef,
        pdle => undef, pdls => undef, pdlo => undef,
    } ],
    [ 'wrong types', {
        fam => 'bad', pdte => 'bad', pdt => [],
        pdle => {}, pdls => '07:15', pdlo => 20.25,
    } ],
    [ 'out of range', {
        fam => 101, pdte => 2, pdt => -1,
        pdle => -1, pdls => -60, pdlo => 86460,
    } ],
    [ 'non-minute clock values', { pdls => 26101, pdlo => 72959 } ],
) {
    my ($label, $status) = @$case;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'deltaStatus', status => $status,
    })), "$label delta is handled safely");
    for my $reading (sort keys %stable) {
        is(reading_value($hash, $reading), $stable{$reading},
            "$label leaves $reading unchanged");
    }
}

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus',
    status => { pdls => 0, pdlo => 86400 },
})), 'clock boundary values are accepted');
is(reading_value($hash, 'configPvBatteryDischargeStartTime'), '00:00',
    'zero seconds maps to midnight');
is(reading_value($hash, 'configPvBatteryDischargeStopTime'), '24:00',
    '86400 seconds is preserved as the end-of-day boundary');

my $interface = main::Wattpilot_InterfaceSnapshot();
for my $key (qw(
    pv_battery_charge_above_soc
    pv_battery_discharge_enabled
    pv_battery_discharge_until_soc
    pv_battery_discharge_time_limit_enabled
    pv_battery_discharge_start_time
    pv_battery_discharge_stop_time
)) {
    is($interface->{readingCategories}{$key}, 'configuration',
        "$key is explicitly classified as configuration");
    like($interface->{readings}{$key}, qr/^configPvBattery/,
        "$key uses the final configPvBattery prefix");
}

is($interface->{commands}{pv_battery}, 'pvBattery',
    'one grouped pvBattery Set command is public');
my @set_commands = values %{$interface->{commands}};
my $pv_battery_command_count = grep { $_ eq 'pvBattery' } @set_commands;
is($pv_battery_command_count, 1,
    'pvBattery appears exactly once in the top-level Set command list');
unlike(join(' ', @set_commands),
    qr/(?:chargeAboveSoC|dischargeEnabled|dischargeUntilSoC|dischargeStartTime|dischargeStopTime)/,
    'battery subcommands are not separate top-level Set commands');

for my $case (
    [ 'chargeAboveSoC', 60, 'fam', 60, 'number' ],
    [ 'dischargeEnabled', 1, 'pdte', 1, 'boolean' ],
    [ 'dischargeEnabled', 0, 'pdte', 0, 'boolean' ],
    [ 'dischargeUntilSoC', 57, 'pdt', 57, 'number' ],
    [ 'dischargeTimeLimitEnabled', 1, 'pdle', 1, 'boolean' ],
    [ 'dischargeTimeLimitEnabled', 0, 'pdle', 0, 'boolean' ],
    [ 'dischargeStartTime', '07:00', 'pdls', 25200, 'number' ],
    [ 'dischargeStopTime', '20:00', 'pdlo', 72000, 'number' ],
    [ 'dischargeStopTime', '24:00', 'pdlo', 86400, 'number' ],
) {
    my ($subcommand, $input, $key, $expected, $kind) = @$case;
    $hash = fresh_set_device();
    is(main::Wattpilot_Set(
            $hash, $hash->{NAME}, 'pvBattery', $subcommand, $input),
        undef, "pvBattery $subcommand accepts $input");
    my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{key}, $key, "pvBattery $subcommand writes $key");
    if ($kind eq 'boolean') {
        ok(JSON::is_bool($inner->{value}),
            "pvBattery $subcommand sends a JSON boolean");
        is($inner->{value} ? 1 : 0, $expected,
            "pvBattery $subcommand sends the expected boolean");
    } else {
        is($inner->{value}, $expected,
            "pvBattery $subcommand sends the expected numeric value");
    }
    is($outer->{requestId}, '1sm',
        "pvBattery $subcommand uses secured request correlation");
}

for my $case (
    [ [] ],
    [ ['chargeAboveSoC'] ],
    [ ['chargeAboveSoC', -1] ],
    [ ['chargeAboveSoC', 101] ],
    [ ['chargeAboveSoC', '60.0'] ],
    [ ['chargeAboveSoC', '060'] ],
    [ ['dischargeEnabled', 2] ],
    [ ['dischargeEnabled', 'true'] ],
    [ ['dischargeUntilSoC', -1] ],
    [ ['dischargeUntilSoC', 101] ],
    [ ['dischargeTimeLimitEnabled', -1] ],
    [ ['dischargeStartTime', '24:00'] ],
    [ ['dischargeStartTime', '7:00'] ],
    [ ['dischargeStartTime', '07:60'] ],
    [ ['dischargeStopTime', '24:01'] ],
    [ ['dischargeStopTime', 'invalid'] ],
    [ ['unknownSetting', 1] ],
    [ ['chargeAboveSoC', 60, 'extra'] ],
) {
    my @args = @{$case->[0]};
    $hash = fresh_set_device();
    like(main::Wattpilot_Set($hash, $hash->{NAME}, 'pvBattery', @args),
        qr/^Usage:/, 'invalid grouped pvBattery syntax is rejected');
    is(scalar @DevIo::WRITES, 0,
        'invalid grouped pvBattery syntax sends no frame');
}

$hash = fresh_set_device();
main::Wattpilot_UpdateReadings($hash, { fam => 60 });
is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 60,
    'confirmed Charge above SoC starts at 60');
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBattery', 'chargeAboveSoC', 61),
    undef, 'Charge above SoC setter is accepted');
is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 60,
    'pending battery setter does not update the reading optimistically');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { fam => 61 },
}));
is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 61,
    'successful response updates Charge above SoC through returned status');
is(reading_value($hash, 'lastCommandStatus'), 'success',
    'successful grouped battery command completes normally');

$hash = fresh_set_device();
main::Wattpilot_UpdateReadings($hash, { pdte => JSON::false });
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBattery', 'dischargeEnabled', 1);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::false,
}));
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'failed response leaves confirmed battery setting unchanged');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'failed grouped battery command is terminal');

$hash = fresh_set_device();
main::Wattpilot_UpdateReadings($hash, {
    pdte => JSON::false,
    pdt => 57,
});
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20),
    undef, 'combined PV-battery setter accepts whitespace-separated values');
is(scalar @DevIo::WRITES, 1,
    'enabling initially sends exactly one secured command');
my ($enable_first_outer, $enable_first_inner) = inner_payload($DevIo::WRITES[0]);
is($enable_first_inner->{key}, 'pdt',
    'enabling writes the discharge-until threshold first');
is($enable_first_inner->{value}, 20,
    'enabling writes the requested threshold');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 57,
    'combined command does not update the threshold optimistically');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'combined command does not enable discharge optimistically');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $enable_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
is(scalar @DevIo::WRITES, 2,
    'confirmed threshold write triggers the enable write');
my ($enable_second_outer, $enable_second_inner) = inner_payload($DevIo::WRITES[1]);
is($enable_second_inner->{key}, 'pdte',
    'enabling writes dischargeEnabled second');
ok(JSON::is_bool($enable_second_inner->{value})
        && $enable_second_inner->{value},
    'enabling sends a true JSON boolean');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 20,
    'first confirmed response updates the threshold reading');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'discharge remains disabled until the second response');
is(reading_value($hash, 'lastCommandStatus'), 'pending',
    'combined command remains pending during the second write');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $enable_second_outer->{requestId},
    success => JSON::true, status => { pdte => JSON::true },
}));
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 1,
    'second confirmed response enables discharge');
is(reading_value($hash, 'lastCommandStatus'), 'success',
    'combined enabling sequence completes successfully');
is(reading_value($hash, 'lastCommandError'), 'none',
    'successful combined sequence clears the command error');

$hash = fresh_set_device();
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 'on,35'),
    undef, 'combined PV-battery setter accepts the FHEMWEB on value');
my (undef, $comma_inner) = inner_payload($DevIo::WRITES[0]);
is($comma_inner->{key}, 'pdt',
    'FHEMWEB on syntax follows the same safe enabling order');
is($comma_inner->{value}, 35,
    'FHEMWEB on syntax preserves the free-text threshold');

$hash = fresh_set_device();
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', '1,36'),
    undef, 'previous numeric comma syntax remains accepted');
my (undef, $numeric_comma_inner) = inner_payload($DevIo::WRITES[0]);
is($numeric_comma_inner->{key}, 'pdt',
    'numeric comma syntax retains the safe enabling order');
is($numeric_comma_inner->{value}, 36,
    'numeric comma syntax retains the requested threshold');

$hash = fresh_set_device();
main::Wattpilot_UpdateReadings($hash, {
    pdte => JSON::true,
    pdt => 20,
});
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 0, 40),
    undef, 'combined PV-battery setter accepts disabling');
my ($disable_first_outer, $disable_first_inner) = inner_payload($DevIo::WRITES[0]);
is($disable_first_inner->{key}, 'pdte',
    'disabling writes dischargeEnabled first');
ok(JSON::is_bool($disable_first_inner->{value})
        && !$disable_first_inner->{value},
    'disabling sends a false JSON boolean');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $disable_first_outer->{requestId},
    success => JSON::true, status => { pdte => JSON::false },
}));
my ($disable_second_outer, $disable_second_inner) = inner_payload($DevIo::WRITES[1]);
is($disable_second_inner->{key}, 'pdt',
    'disabling writes the threshold second');
is($disable_second_inner->{value}, 40,
    'disabling still stores the explicitly supplied threshold');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $disable_second_outer->{requestId},
    success => JSON::true, status => { pdt => 40 },
}));
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'disabling sequence leaves discharge disabled');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 40,
    'disabling sequence confirms the new threshold');

$hash = fresh_set_device();
is(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 'off,45'),
    undef, 'combined PV-battery setter accepts the FHEMWEB off value');
my (undef, $off_inner) = inner_payload($DevIo::WRITES[0]);
is($off_inner->{key}, 'pdte',
    'FHEMWEB off syntax follows the safe disabling order');
ok(JSON::is_bool($off_inner->{value}) && !$off_inner->{value},
    'FHEMWEB off syntax maps to a false JSON boolean');

for my $case (
    [],
    [1],
    [1, 20, 'extra'],
    ['1,20,30'],
    [''],
    ['true', 20],
    ['enabled', 20],
    [2, 20],
    [-1, 20],
    [1, -1],
    [1, 101],
    [1, '20.0'],
    [1, '020'],
    ['1,101'],
    ['on,'],
    ['on,20.0'],
    ['off,101'],
) {
    $hash = fresh_set_device();
    like(main::Wattpilot_Set(
            $hash, $hash->{NAME}, 'pvBatteryDischarge', @$case),
        qr/^Usage:/,
        'invalid combined PV-battery syntax is rejected');
    is(scalar @DevIo::WRITES, 0,
        'invalid combined PV-battery syntax sends no frame');
}

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
like(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBattery', 'dischargeEnabled', 0),
    qr/already pending/,
    'grouped dischargeEnabled write cannot overlap a combined sequence');
like(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 0, 30),
    qr/already pending/,
    'a second combined sequence cannot overlap the first');
is(scalar @DevIo::WRITES, 1,
    'overlap rejection sends no additional frame');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBattery', 'dischargeUntilSoC', 20);
like(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20),
    qr/already pending/,
    'combined sequence cannot overlap a grouped threshold write');
like(main::Wattpilot_Set(
        $hash, $hash->{NAME}, 'pvBattery', 'dischargeEnabled', 1),
    qr/already pending/,
    'related grouped writes cannot overlap each other');
is(scalar @DevIo::WRITES, 1,
    'grouped overlap rejection sends no additional frame');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($reject_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $reject_first_outer->{requestId},
    success => JSON::false,
}));
is(scalar @DevIo::WRITES, 1,
    'a rejected first step does not send the second step');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'a rejected first step is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge dischargeUntilSoC failed: device rejected pdt',
    'first-step rejection identifies the failed setting');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($partial_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $partial_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
my ($partial_second_outer) = inner_payload($DevIo::WRITES[1]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $partial_second_outer->{requestId},
    success => JSON::false,
}));
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'a rejected second step is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeUntilSoC; dischargeEnabled failed: device rejected pdte',
    'second-step rejection reports the applied and failed settings');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 0, 40);
my ($disable_reject_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $disable_reject_first_outer->{requestId},
    success => JSON::false,
}));
is(scalar @DevIo::WRITES, 1,
    'a rejected disable step does not send the threshold update');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'a rejected disable step is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge dischargeEnabled failed: device rejected pdte',
    'disable-first rejection identifies dischargeEnabled');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 0, 40);
my ($disable_partial_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $disable_partial_first_outer->{requestId},
    success => JSON::true, status => { pdte => JSON::false },
}));
my ($disable_partial_second_outer) = inner_payload($DevIo::WRITES[1]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $disable_partial_second_outer->{requestId},
    success => JSON::false,
}));
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'confirmed disable remains visible when the threshold update fails');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'a rejected threshold after disable is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeEnabled; dischargeUntilSoC failed: device rejected pdt',
    'disable-second rejection reports the applied and failed settings');

$hash = fresh_set_device();
$DevIo::NOW = 100;
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
DevIo::run_due_timers(131);
is(reading_value($hash, 'lastCommandStatus'), 'timeout',
    'first-step response timeout is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge dischargeUntilSoC failed: response timeout',
    'first-step timeout identifies the failed setting');
is(scalar @DevIo::WRITES, 1,
    'first-step timeout never sends the second step');

$hash = fresh_set_device();
$DevIo::NOW = 100;
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($timeout_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $timeout_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
DevIo::run_due_timers(131);
is(reading_value($hash, 'lastCommandStatus'), 'timeout',
    'second-step response timeout is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeUntilSoC; dischargeEnabled failed: response timeout',
    'second-step timeout reports the partial application');

$hash = fresh_set_device();
my $reentrant_abort = 0;
$DevIo::READING_EVENT_HOOK = sub {
    my ($event_hash, $events) = @_;
    return if $reentrant_abort;
    return if !grep { $_ eq 'lastCommandStatus: pending' } @$events;
    my $pending = $event_hash->{helper}{pendingRequests} // {};
    my ($request) = values %$pending;
    return if ref($request) ne 'HASH'
        || ref($request->{context}) ne 'HASH'
        || ($request->{context}{step} // '') ne 'dischargeEnabled';
    $reentrant_abort = 1;
    main::Wattpilot_AbortPendingRequests(
        $event_hash, 'connection lost', 1);
};
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($reentrant_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $reentrant_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
ok($reentrant_abort,
    'second-step sequence context is attached before pending events fire');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'reentrant connection loss during pending publication remains terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeUntilSoC; dischargeEnabled failed: connection lost',
    'reentrant abort sees complete partial-failure context');
$DevIo::READING_EVENT_HOOK = undef;

$hash = fresh_set_device();
my ($reentrant_undef, $events_at_undef) = (0, 0);
$DevIo::READING_EVENT_HOOK = sub {
    my ($event_hash, $events) = @_;
    return if $reentrant_undef;
    return if !grep { $_ eq 'lastCommandStatus: pending' } @$events;
    my $pending = $event_hash->{helper}{pendingRequests} // {};
    my ($request) = values %$pending;
    return if ref($request) ne 'HASH'
        || ref($request->{context}) ne 'HASH'
        || ($request->{context}{step} // '') ne 'dischargeEnabled';
    $reentrant_undef = 1;
    $events_at_undef = scalar @DevIo::READING_EVENTS;
    main::Wattpilot_Undefine($event_hash, $event_hash->{NAME});
};
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($undef_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $undef_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
ok($reentrant_undef,
    'reentrant undefine is exercised during second-step pending publication');
ok($hash->{helper}{undefined},
    'reentrant undefine keeps the device runtime invalidated');
ok(!exists $hash->{READINGS}{configPvBatteryDischargeUntilSoC},
    'obsolete first-step status is not published after reentrant undefine');
is(scalar @DevIo::READING_EVENTS, $events_at_undef,
    'reentrant undefine is followed by no additional reading events');
$DevIo::READING_EVENT_HOOK = undef;

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($send_failure_outer) = inner_payload($DevIo::WRITES[0]);
$hash->{TEST_OPEN} = 0;
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $send_failure_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
is(scalar @DevIo::WRITES, 1,
    'local second-step send failure adds no frame');
is(reading_value($hash, 'configPvBatteryDischargeUntilSoC'), 20,
    'confirmed first response is still applied when second send fails');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'local second-step send failure is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeUntilSoC; dischargeEnabled failed: not sent: Wattpilot is disconnected',
    'local second-step send failure reports the partial application');

$hash = fresh_set_device();
main::Wattpilot_Set(
    $hash, $hash->{NAME}, 'pvBatteryDischarge', 1, 20);
my ($abort_first_outer) = inner_payload($DevIo::WRITES[0]);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => $abort_first_outer->{requestId},
    success => JSON::true, status => { pdt => 20 },
}));
main::Wattpilot_AbortPendingRequests($hash, 'connection lost', 1);
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'connection loss during the second step is terminal');
is(reading_value($hash, 'lastCommandError'),
    'pvBatteryDischarge partial failure after dischargeUntilSoC; dischargeEnabled failed: connection lost',
    'connection loss reports the partial application');

$hash = fresh_set_device();
my $help = main::Wattpilot_Set($hash, $hash->{NAME}, '?');
like($help, qr/\bpvBattery\b/,
    'Set help exposes one grouped pvBattery command');
like($help, qr/\bpvBatteryDischarge:widgetList,3,select,off,on,3,textField,SoC%,4\b/,
    'Set help exposes the off/on dropdown and SoC free-text field');
for my $subcommand (qw(
    chargeAboveSoC dischargeEnabled dischargeUntilSoC
    dischargeTimeLimitEnabled dischargeStartTime dischargeStopTime
)) {
    unlike($help, qr/\b\Q$subcommand\E\b/,
        "$subcommand is not a top-level Set command");
}
like(main::Wattpilot_Set($hash, $hash->{NAME}, 'pvBattery'),
    qr/chargeAboveSoC.*dischargeStopTime/,
    'pvBattery usage lists all subcommands');

done_testing;
