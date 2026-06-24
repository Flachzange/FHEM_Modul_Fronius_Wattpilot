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

sub nrg {
    my ($power) = @_;
    return [230, 231, 232, 0, 1, 1, 1, 230, 231, 232, 0, $power];
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    return main::Wattpilot_Parse($hash, encode_json({
        type => $type,
        status => $status,
    }));
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

subtest 'combined nrg cycle exposes stationary PV-battery telemetry' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 100;

    for my $reading (qw(pvBatteryStateOfCharge pvBatteryPower pvBatteryModeCode)) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading remains absent before a valid device value arrives");
    }

    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(),
        car => 2,
        fbuf_akkuSOC => 60.0,
        fbuf_pAkku => -1525.0,
        fbuf_akkuMode => 1,
        nrg => nrg(690),
    }), 'combined fullStatus is accepted');
    is(reading_value($hash, 'pvBatteryStateOfCharge'), 60,
        'stationary PV-battery state of charge is exposed as percent');
    is(reading_value($hash, 'pvBatteryPower'), '-1525.00',
        'signed PV-battery power is formatted with two decimal places');
    is(reading_value($hash, 'pvBatteryModeCode'), 1,
        'PV-battery mode remains an unmodified raw code');
    is(reading_value($hash, 'power'), '690.00',
        'nrg power is emitted by the same shared cycle');
    is($hash->{LAST_UPDATE}, 100,
        'one shared interval timestamp is recorded');
    ok(!exists $hash->{LAST_BATTERY_UPDATE},
        'no independent battery interval timestamp exists');

    $DevIo::NOW = 101;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 42.5,
        fbuf_pAkku => 987.256,
        fbuf_akkuMode => 77,
        nrg => nrg(900),
    }), 'combined deltaStatus updates the shared telemetry cycle');
    is(reading_value($hash, 'pvBatteryStateOfCharge'), 42.5,
        'decimal PV-battery SOC is preserved');
    is(reading_value($hash, 'pvBatteryPower'), '987.26',
        'positive PV-battery power is rounded to two decimal places');
    is(reading_value($hash, 'pvBatteryModeCode'), 77,
        'unknown non-negative PV-battery mode code remains visible');
    is(reading_value($hash, 'power'), '900.00',
        'nrg and battery data advance together');
};

subtest 'invalid battery values neither overwrite readings nor cached values' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 200;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(), car => 2,
        fbuf_akkuSOC => 55,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 2,
        nrg => nrg(500),
    }), 'valid baseline is accepted');

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
        $DevIo::NOW++;
        ok(parse_status($hash, 'deltaStatus', $status),
            "$label delta is processed safely");
        ok(parse_status($hash, 'deltaStatus', { nrg => nrg(501) }),
            "$label cache is flushed by a valid nrg cycle");
        for my $reading (sort keys %stable) {
            is(reading_value($hash, $reading), $stable{$reading},
                "$label leaves $reading unchanged");
        }
    }
};

subtest 'battery-only messages are cached until the next nrg-led cycle' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $DevIo::NOW = 1_000;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(), car => 2,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 1,
        nrg => nrg(500),
    }), 'combined baseline establishes the shared cadence');

    my $updates_before = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 1_030;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 49,
        fbuf_pAkku => -700,
        fbuf_akkuMode => 2,
    }), 'battery-only boundary delta is accepted');
    is(reading_value($hash, 'pvBatteryPower'), '-500.00',
        'battery-only data is not published independently');
    is(scalar @DevIo::READING_UPDATES, $updates_before,
        'battery-only data produces no reading transaction');
    is($hash->{LAST_UPDATE}, 1_000,
        'battery-only data does not consume the shared interval');

    my $cycle_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 1_031;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(700) }),
        'following nrg delta starts the shared cycle');
    is(reading_value($hash, 'pvBatteryStateOfCharge'), 49,
        'latest cached SOC is published with nrg');
    is(reading_value($hash, 'pvBatteryPower'), '-700.00',
        'latest cached battery power is published with nrg');
    is(reading_value($hash, 'pvBatteryModeCode'), 2,
        'latest cached mode is published with nrg');
    is(reading_value($hash, 'power'), '700.00',
        'fresh nrg is published in the same cycle');
    is($hash->{LAST_UPDATE}, 1_031,
        'nrg-led cycle advances the shared timestamp');
    my @cycle = map { $_->[1] }
        @DevIo::READING_UPDATES[$cycle_start .. $#DevIo::READING_UPDATES];
    ok(grep($_ eq 'power', @cycle) && grep($_ eq 'pvBatteryPower', @cycle),
        'nrg and battery readings belong to one update call');
};

subtest 'matched responses cache battery data without bypassing the shared cadence' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(), car => 2,
        fbuf_akkuSOC => 60,
        fbuf_pAkku => -600,
        fbuf_akkuMode => 1,
        nrg => nrg(600),
    }), 'baseline is accepted');

    $hash->{helper}{pendingRequests}{49} = {
        key => 'syntheticBatteryReadback', sentAt => 2_005,
    };
    $DevIo::NOW = 2_005;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => 49,
        success => JSON::true(),
        status => {
            fbuf_akkuSOC => 61,
            fbuf_pAkku => -1200,
            fbuf_akkuMode => 2,
        },
    })), 'successful response is accepted');
    is(reading_value($hash, 'pvBatteryPower'), '-600.00',
        'response does not create a separate battery update');
    is($hash->{LAST_UPDATE}, 2_000,
        'response does not bypass the shared interval');

    $DevIo::NOW = 2_030;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(650) }),
        'next nrg boundary flushes response-cached battery data');
    is(reading_value($hash, 'pvBatteryStateOfCharge'), 61,
        'response-cached SOC becomes visible at the shared boundary');
    is(reading_value($hash, 'pvBatteryPower'), '-1200.00',
        'response-cached power becomes visible at the shared boundary');
    is(reading_value($hash, 'pvBatteryModeCode'), 2,
        'response-cached mode becomes visible at the shared boundary');
};

subtest 'idle policy applies once to the shared telemetry cycle' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(), car => 1,
        fbuf_akkuSOC => 40,
        fbuf_pAkku => 250.126,
        fbuf_akkuMode => 1,
        nrg => nrg(0),
    }), 'idle telemetry is accepted while publication is disabled');
    ok(!exists $hash->{READINGS}{pvBatteryPower},
        'idle battery telemetry stays passive');
    ok(!exists $hash->{READINGS}{power},
        'idle nrg telemetry stays passive');
    ok(!exists $hash->{LAST_UPDATE},
        'suppressed idle telemetry does not advance the shared cadence');

    $attr{$hash->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 3_001;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(0) }),
        'one valid idle nrg enables the shared publication');
    is(reading_value($hash, 'pvBatteryPower'), '250.13',
        'cached idle battery telemetry is published with nrg');
    is(reading_value($hash, 'power'), '0.00',
        'idle nrg is published in the same cycle');
};

subtest 'interval zero still requires an nrg-led publication' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 4_000;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        fbuf_pAkku => 10,
    }), 'first battery-only delta is cached');
    ok(!exists $hash->{READINGS}{pvBatteryPower},
        'battery-only delta is not published even with interval zero');

    $DevIo::NOW = 4_001;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(100) }),
        'first nrg delta publishes the cache');
    is(reading_value($hash, 'pvBatteryPower'), '10.00',
        'first cached battery value is published');

    $DevIo::NOW = 4_002;
    ok(parse_status($hash, 'deltaStatus', { fbuf_pAkku => 20 }),
        'second battery-only delta is cached');
    is(reading_value($hash, 'pvBatteryPower'), '10.00',
        'second battery-only delta remains unpublished');

    $DevIo::NOW = 4_003;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'second nrg delta publishes without rate limiting');
    is(reading_value($hash, 'pvBatteryPower'), '20.00',
        'interval zero publishes latest cached battery data on every nrg cycle');
};

my $interface = main::Wattpilot_InterfaceSnapshot();
is($interface->{readings}{pv_battery_state_of_charge},
    'pvBatteryStateOfCharge',
    'public interface snapshot exposes the stationary-battery SOC reading');
is($interface->{readings}{pv_battery_power}, 'pvBatteryPower',
    'public interface snapshot exposes the stationary-battery power reading');
is($interface->{readings}{pv_battery_mode_code}, 'pvBatteryModeCode',
    'public interface snapshot exposes the raw stationary-battery mode code');

my $hash = fresh_device();
my $help = main::Wattpilot_Set($hash, 'batteryWallbox', '?');
unlike($help, qr/pvBattery(?:StateOfCharge|Power|ModeCode)/,
    'read-only PV-battery telemetry does not invent a setter');

done_testing;
