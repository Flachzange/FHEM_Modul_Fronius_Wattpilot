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
    return $hash;
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
is(reading_value($hash, 'configPvBatteryChargeAboveStateOfCharge'), 60,
    'fam maps to the Charge above state-of-charge setting');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 0,
    'pdte maps to the disabled Discharge until switch');
is(reading_value($hash, 'configPvBatteryDischargeUntilStateOfCharge'), 57,
    'pdt maps to the Discharge until state-of-charge setting');
is(reading_value($hash, 'configPvBatteryDischargeTimeLimitEnabled'), 1,
    'pdle maps to the enabled discharge-time limitation');
is(reading_value($hash, 'configPvBatteryDischargeStartTime'), '07:00',
    'pdls maps seconds since midnight to the app start time');
is(reading_value($hash, 'configPvBatteryDischargeEndTime'), '20:00',
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
is(reading_value($hash, 'configPvBatteryChargeAboveStateOfCharge'), 61,
    'Charge above state of charge updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeEnabled'), 1,
    'Discharge until switch updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeUntilStateOfCharge'), 56,
    'Discharge until state of charge updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeTimeLimitEnabled'), 0,
    'discharge-time limitation switch updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeStartTime'), '07:15',
    'discharge start time updates immediately');
is(reading_value($hash, 'configPvBatteryDischargeEndTime'), '20:15',
    'discharge end time updates immediately');

my %stable = map {
    $_ => reading_value($hash, $_)
} qw(
    configPvBatteryChargeAboveStateOfCharge
    configPvBatteryDischargeEnabled
    configPvBatteryDischargeUntilStateOfCharge
    configPvBatteryDischargeTimeLimitEnabled
    configPvBatteryDischargeStartTime
    configPvBatteryDischargeEndTime
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
is(reading_value($hash, 'configPvBatteryDischargeEndTime'), '24:00',
    '86400 seconds is preserved as the end-of-day boundary');

my $interface = main::Wattpilot_InterfaceSnapshot();
for my $key (qw(
    pv_battery_charge_above_state_of_charge
    pv_battery_discharge_enabled
    pv_battery_discharge_until_state_of_charge
    pv_battery_discharge_time_limit_enabled
    pv_battery_discharge_start_time
    pv_battery_discharge_end_time
)) {
    is($interface->{readingCategories}{$key}, 'configuration',
        "$key is explicitly classified as configuration");
    like($interface->{readings}{$key}, qr/^configPvBattery/,
        "$key uses the final configPvBattery prefix");
}

my @set_commands = values %{$interface->{commands}};
unlike(join(' ', @set_commands), qr/PvBattery/,
    'read-only discovery stage adds no battery Set command');

done_testing;
