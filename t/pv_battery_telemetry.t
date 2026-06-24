use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(encode_json);
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
        NAME => 'batteryWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000049',
        DeviceName => 'ws:192.0.2.49:80/ws',
        STATE => 'connected',
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

my $hash = fresh_device();
for my $reading (qw(pvBatteryStateOfCharge pvBatteryPower pvBatteryModeCode)) {
    ok(!exists $hash->{READINGS}{$reading},
        "$reading remains absent before a valid device value arrives");
}
ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus',
    status => {
        fbuf_akkuSOC => 60.0,
        fbuf_pAkku => -1525.0,
        fbuf_akkuMode => 1,
    },
})), 'fullStatus with observed PV-battery telemetry is accepted');
is(reading_value($hash, 'pvBatteryStateOfCharge'), 60,
    'stationary PV-battery state of charge is exposed as percent');
is(reading_value($hash, 'pvBatteryPower'), -1525,
    'signed PV-battery power is preserved without sign reinterpretation');
is(reading_value($hash, 'pvBatteryModeCode'), 1,
    'PV-battery mode remains an unmodified raw code');

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 42.5,
        fbuf_pAkku => 987.25,
        fbuf_akkuMode => 77,
    },
})), 'deltaStatus updates all PV-battery telemetry readings');
is(reading_value($hash, 'pvBatteryStateOfCharge'), 42.5,
    'decimal PV-battery SOC is preserved');
is(reading_value($hash, 'pvBatteryPower'), 987.25,
    'positive PV-battery power is preserved unchanged');
is(reading_value($hash, 'pvBatteryModeCode'), 77,
    'unknown non-negative PV-battery mode code remains visible');

my %stable = (
    pvBatteryStateOfCharge => reading_value($hash, 'pvBatteryStateOfCharge'),
    pvBatteryPower => reading_value($hash, 'pvBatteryPower'),
    pvBatteryModeCode => reading_value($hash, 'pvBatteryModeCode'),
);

for my $case (
    [ 'missing', {} ],
    [ 'null', {
        fbuf_akkuSOC => undef,
        fbuf_pAkku => undef,
        fbuf_akkuMode => undef,
    } ],
    [ 'SOC below zero', { fbuf_akkuSOC => -0.1 } ],
    [ 'SOC above 100', { fbuf_akkuSOC => 100.1 } ],
    [ 'SOC text', { fbuf_akkuSOC => 'full' } ],
    [ 'SOC NaN', { fbuf_akkuSOC => 'NaN' } ],
    [ 'SOC infinity', { fbuf_akkuSOC => 'Inf' } ],
    [ 'SOC overflow', { fbuf_akkuSOC => '1e9999' } ],
    [ 'SOC array', { fbuf_akkuSOC => [60] } ],
    [ 'power text', { fbuf_pAkku => 'charging' } ],
    [ 'power NaN', { fbuf_pAkku => 'NaN' } ],
    [ 'power infinity', { fbuf_pAkku => '-Inf' } ],
    [ 'power overflow', { fbuf_pAkku => '1e9999' } ],
    [ 'power object', { fbuf_pAkku => { watts => -1200 } } ],
    [ 'mode text', { fbuf_akkuMode => 'automatic' } ],
    [ 'mode decimal', { fbuf_akkuMode => 1.5 } ],
    [ 'mode negative', { fbuf_akkuMode => -1 } ],
    [ 'mode array', { fbuf_akkuMode => [1] } ],
    [ 'boolean values', {
        fbuf_akkuSOC => JSON::true(),
        fbuf_pAkku => JSON::false(),
        fbuf_akkuMode => JSON::true(),
    } ],
) {
    my ($label, $status) = @$case;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'deltaStatus', status => $status,
    })), "$label delta is processed safely");
    for my $reading (sort keys %stable) {
        is(reading_value($hash, $reading), $stable{$reading},
            "$label delta leaves $reading unchanged");
    }
}

$hash->{helper}{pendingRequests}{49} = {
    key => 'syntheticBatteryReadback', sentAt => time(),
};
ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'response',
    requestId => 49,
    success => JSON::true,
    status => {
        fbuf_akkuSOC => 61,
        fbuf_pAkku => -1200,
        fbuf_akkuMode => 2,
    },
})), 'successful response status uses the same PV-battery parsing path');
is(reading_value($hash, 'pvBatteryStateOfCharge'), 61,
    'successful response updates PV-battery SOC');
is(reading_value($hash, 'pvBatteryPower'), -1200,
    'successful response updates PV-battery power');
is(reading_value($hash, 'pvBatteryModeCode'), 2,
    'successful response updates PV-battery mode code');

my $interface = main::Wattpilot_InterfaceSnapshot();
is($interface->{readings}{pv_battery_state_of_charge},
    'pvBatteryStateOfCharge',
    'public interface snapshot exposes the stationary-battery SOC reading');
is($interface->{readings}{pv_battery_power}, 'pvBatteryPower',
    'public interface snapshot exposes the stationary-battery power reading');
is($interface->{readings}{pv_battery_mode_code}, 'pvBatteryModeCode',
    'public interface snapshot exposes the raw stationary-battery mode code');

my $help = main::Wattpilot_Set($hash, 'batteryWallbox', '?');
unlike($help, qr/pvBattery(?:StateOfCharge|Power|ModeCode)/,
    'read-only PV-battery telemetry does not invent a setter');

done_testing;
