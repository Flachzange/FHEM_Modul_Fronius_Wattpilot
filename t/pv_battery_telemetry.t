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
    $attr{$hash->{NAME}}{update_while_idle} = 1;
    return $hash;
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

sub battery_update_count {
    my %battery = map { $_ => 1 } qw(
        pvBatteryStateOfCharge pvBatteryPower pvBatteryModeCode
    );
    return scalar grep {
        ref($_) eq 'ARRAY' && defined($_->[1]) && $battery{$_->[1]}
    } @DevIo::READING_UPDATES;
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
is(reading_value($hash, 'pvBatteryPower'), '-1525.00',
    'signed PV-battery power is rounded to two decimal places without sign reinterpretation');
is(reading_value($hash, 'pvBatteryModeCode'), 1,
    'PV-battery mode remains an unmodified raw code');

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 42.5,
        fbuf_pAkku => 987.256,
        fbuf_akkuMode => 77,
    },
})), 'deltaStatus updates all PV-battery telemetry readings');
is(reading_value($hash, 'pvBatteryStateOfCharge'), 42.5,
    'decimal PV-battery SOC is preserved');
is(reading_value($hash, 'pvBatteryPower'), '987.26',
    'positive PV-battery power is rounded to two decimal places');
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
is(reading_value($hash, 'pvBatteryPower'), '-1200.00',
    'successful response updates and formats PV-battery power');
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

my $limited = fresh_device();
$attr{$limited->{NAME}}{interval} = 30;
$DevIo::NOW = 1_000;
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'fullStatus',
    status => {
        partial => JSON::false(),
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 1,
    },
})), 'initial fullStatus bypasses the battery interval gate');
is($limited->{LAST_BATTERY_UPDATE}, 1_000,
    'initial fullStatus records independent battery rate-limit history');
my $updates_after_initial = battery_update_count();

$DevIo::NOW = 1_005;
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 49.5,
        fbuf_pAkku => -650,
        fbuf_akkuMode => 2,
    },
})), 'battery delta inside interval is accepted but rate-limited');
is(battery_update_count(), $updates_after_initial,
    'battery delta inside interval produces no reading updates');
is(reading_value($limited, 'pvBatteryStateOfCharge'), 50,
    'rate-limited battery delta preserves the previous SOC');
is(reading_value($limited, 'pvBatteryPower'), '-500.00',
    'rate-limited battery delta preserves the previous formatted power');
is(reading_value($limited, 'pvBatteryModeCode'), 1,
    'rate-limited battery delta preserves the previous mode code');
is($limited->{LAST_BATTERY_UPDATE}, 1_000,
    'suppressed battery delta does not advance rate-limit history');

$DevIo::NOW = 1_030;
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 49,
        fbuf_pAkku => -700,
        fbuf_akkuMode => 2,
    },
})), 'battery delta at interval boundary is processed');
is(reading_value($limited, 'pvBatteryStateOfCharge'), 49,
    'SOC updates at the interval boundary');
is(reading_value($limited, 'pvBatteryPower'), '-700.00',
    'battery power updates at the interval boundary with two decimals');
is(reading_value($limited, 'pvBatteryModeCode'), 2,
    'battery mode code updates at the interval boundary');
is($limited->{LAST_BATTERY_UPDATE}, 1_030,
    'processed battery delta advances its own rate-limit history');

$DevIo::NOW = 1_031;
my $last_before_invalid = $limited->{LAST_BATTERY_UPDATE};
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 'NaN',
        fbuf_pAkku => 'Inf',
        fbuf_akkuMode => -1,
    },
})), 'invalid battery-only delta is ignored safely');
is($limited->{LAST_BATTERY_UPDATE}, $last_before_invalid,
    'invalid battery-only delta does not consume the interval');

$limited->{helper}{pendingRequests}{50} = {
    key => 'syntheticBatteryReadback', sentAt => time(),
};
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'response',
    requestId => 50,
    success => JSON::true,
    status => {
        fbuf_akkuSOC => 48,
        fbuf_pAkku => -800,
        fbuf_akkuMode => 3,
    },
})), 'matched response bypasses the battery interval gate');
is(reading_value($limited, 'pvBatteryStateOfCharge'), 48,
    'response-confirmed SOC is applied immediately');
is(reading_value($limited, 'pvBatteryPower'), '-800.00',
    'response-confirmed battery power is applied immediately with two decimals');
is(reading_value($limited, 'pvBatteryModeCode'), 3,
    'response-confirmed battery mode is applied immediately');

$DevIo::NOW = 1_032;
ok(main::Wattpilot_Parse($limited, encode_json({
    type => 'fullStatus',
    status => {
        partial => JSON::false(),
        fbuf_akkuSOC => 47,
        fbuf_pAkku => -900,
        fbuf_akkuMode => 4,
    },
})), 'new complete fullStatus bypasses the battery interval gate');
is(reading_value($limited, 'pvBatteryStateOfCharge'), 47,
    'complete fullStatus refreshes battery telemetry immediately');

my $independent = fresh_device();
$attr{$independent->{NAME}}{interval} = 30;
$attr{$independent->{NAME}}{update_while_idle} = 0;
$independent->{helper}{car_state} = 1;
$DevIo::NOW = 2_000;
$independent->{LAST_BATTERY_UPDATE} = 1_970;
$independent->{LAST_UPDATE} = 1_970;
ok(main::Wattpilot_Parse($independent, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 40,
        fbuf_pAkku => 250.126,
        fbuf_akkuMode => 1,
        nrg => [230, 231, 232, 0, 1, 1, 1, 230, 231, 232, 0, 693],
    },
})), 'idle telemetry delta is accepted while update_while_idle is disabled');
ok(!exists $independent->{READINGS}{pvBatteryPower},
    'update_while_idle=0 suppresses stationary-battery telemetry while idle');
ok(!exists $independent->{READINGS}{power},
    'update_while_idle=0 suppresses nrg telemetry while idle');
is($independent->{LAST_BATTERY_UPDATE}, 1_970,
    'idle-suppressed battery telemetry does not advance its interval history');
is($independent->{LAST_UPDATE}, 1_970,
    'idle-suppressed nrg telemetry does not advance its interval history');

ok(main::Wattpilot_Parse($independent, encode_json({
    type => 'fullStatus',
    status => {
        partial => JSON::false(),
        fbuf_akkuSOC => 39,
        fbuf_pAkku => 300.129,
        fbuf_akkuMode => 2,
    },
})), 'complete fullStatus does not bypass the shared idle gate');
ok(!exists $independent->{READINGS}{pvBatteryPower},
    'idle-suppressed complete fullStatus leaves battery telemetry absent');

$independent->{helper}{pendingRequests}{51} = {
    key => 'syntheticBatteryReadback', sentAt => time(),
};
ok(main::Wattpilot_Parse($independent, encode_json({
    type => 'response',
    requestId => 51,
    success => JSON::true,
    status => {
        fbuf_akkuSOC => 38,
        fbuf_pAkku => 350.129,
        fbuf_akkuMode => 3,
    },
})), 'matched response does not bypass the shared idle gate');
ok(!exists $independent->{READINGS}{pvBatteryPower},
    'idle-suppressed response leaves battery telemetry absent');
is($independent->{LAST_BATTERY_UPDATE}, 1_970,
    'idle-suppressed fullStatus and response do not advance battery history');

$attr{$independent->{NAME}}{update_while_idle} = 1;
$DevIo::NOW = 2_001;
ok(main::Wattpilot_Parse($independent, encode_json({
    type => 'deltaStatus',
    status => {
        fbuf_akkuSOC => 40,
        fbuf_pAkku => 250.126,
        fbuf_akkuMode => 1,
        nrg => [230, 231, 232, 0, 1, 1, 1, 230, 231, 232, 0, 693],
    },
})), 'update_while_idle enables both volatile telemetry groups uniformly');
is(reading_value($independent, 'pvBatteryPower'), '250.13',
    'enabled idle battery telemetry is rounded to two decimal places');
is(reading_value($independent, 'power'), '693.00',
    'enabled idle nrg telemetry is updated through the same idle policy');

my $unlimited = fresh_device();
$attr{$unlimited->{NAME}}{interval} = 0;
$DevIo::NOW = 3_000;
ok(main::Wattpilot_Parse($unlimited, encode_json({
    type => 'deltaStatus',
    status => { fbuf_pAkku => 10 },
})), 'interval zero accepts first battery delta');
$DevIo::NOW = 3_001;
ok(main::Wattpilot_Parse($unlimited, encode_json({
    type => 'deltaStatus',
    status => { fbuf_pAkku => 20 },
})), 'interval zero accepts consecutive battery delta');
is(reading_value($unlimited, 'pvBatteryPower'), '20.00',
    'interval zero disables battery telemetry rate limiting while formatting remains stable');

done_testing;
