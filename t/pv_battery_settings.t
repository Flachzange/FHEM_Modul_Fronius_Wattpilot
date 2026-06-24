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
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'pvBatteryConfigWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000052',
        DeviceName => 'ws:192.0.2.52:80/ws',
        STATE => 'initializing',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-pv-battery-key';
    return $hash;
}


sub fresh_set_device {
    my $hash = fresh_device();
    $hash->{STATE} = 'connected';
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
my $help = main::Wattpilot_Set($hash, $hash->{NAME}, '?');
like($help, qr/\bpvBattery\b/,
    'Set help exposes one grouped pvBattery command');
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
