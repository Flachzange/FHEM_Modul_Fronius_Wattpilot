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

sub reading_time {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{TIME};
}

sub updates_since {
    my ($start) = @_;
    return () if $start > $#DevIo::READING_UPDATES;
    return @DevIo::READING_UPDATES[$start .. $#DevIo::READING_UPDATES];
}

subtest 'combined status exposes independently published PV-battery telemetry' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 100;

    for my $reading (qw(pvBatterySoC pvBatteryPower pvBatteryModeCode)) {
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
    is(reading_value($hash, 'pvBatterySoC'), '60.0',
        'stationary PV-battery state of charge is formatted with one decimal place');
    is(reading_value($hash, 'pvBatteryPower'), '-1525.00',
        'signed PV-battery power is formatted with two decimal places');
    is(reading_value($hash, 'pvBatteryModeCode'), 1,
        'PV-battery mode remains an unmodified raw code');
    is(reading_value($hash, 'power'), '690.00',
        'nrg power is emitted from the same status message');
    is(reading_time($hash, 'power'), reading_time($hash, 'pvBatteryPower'),
        'electrical and battery telemetry share one transaction timestamp');

    $DevIo::NOW = 101;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 42.5,
        fbuf_pAkku => 987.256,
        fbuf_akkuMode => 77,
        nrg => nrg(900),
    }), 'combined deltaStatus updates both independent telemetry groups');
    is(reading_value($hash, 'pvBatterySoC'), '42.5',
        'decimal PV-battery SOC is formatted with one decimal place');
    is(reading_value($hash, 'pvBatteryPower'), '987.26',
        'positive PV-battery power is rounded to two decimal places');
    is(reading_value($hash, 'pvBatteryModeCode'), 77,
        'unknown non-negative PV-battery mode code remains visible');
    is(reading_value($hash, 'power'), '900.00',
        'nrg data advances independently in the same input message');
};

subtest 'invalid battery values neither overwrite readings nor cadence state' => sub {
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
        pvBatterySoC => reading_value($hash, 'pvBatterySoC'),
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
            "$label is followed by unrelated valid nrg");
        for my $reading (sort keys %stable) {
            is(reading_value($hash, $reading), $stable{$reading},
                "$label leaves $reading unchanged");
        }
    }
};

subtest 'battery-only and nrg input share one cadence without cross-publication' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $DevIo::NOW = 1_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 1,
        nrg => nrg(500),
    }), 'combined baseline starts the common telemetry clock');

    my $cycle_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 1_029;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 49,
        fbuf_pAkku => -700,
        fbuf_akkuMode => 2,
    }), 'battery-only input is cached before the common tick');
    is(reading_value($hash, 'pvBatteryModeCode'), 2,
        'battery mode remains immediate-on-change');
    is(reading_value($hash, 'pvBatteryPower'), '-500.00',
        'battery telemetry waits for the common tick');

    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(700) }),
        'fresh nrg in the same cycle is cached');
    is(reading_value($hash, 'power'), '500.00',
        'nrg also waits for the common tick');

    DevIo::run_due_timers(1_030);
    is(reading_value($hash, 'pvBatterySoC'), '49.0',
        'fresh SOC publishes with one decimal place');
    is(reading_value($hash, 'pvBatteryPower'), '-700.00',
        'fresh battery power publishes on the common tick');
    is(reading_value($hash, 'power'), '700.00',
        'fresh nrg publishes on the same common tick');
    is(reading_time($hash, 'power'), reading_time($hash, 'pvBatteryPower'),
        'nrg and battery receive the same timestamp');
    my @cycle = map { $_->[1] } updates_since($cycle_start);
    ok(grep($_ eq 'power', @cycle) && grep($_ eq 'pvBatteryPower', @cycle),
        'the tick publishes fresh values from both dirty owners');
};

subtest 'matched responses cache battery telemetry for the common tick' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
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
        'response telemetry remains cached before the tick');
    is(reading_value($hash, 'pvBatteryModeCode'), 2,
        'response mode change is immediate-on-change');

    $DevIo::NOW = 2_029;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(650) }),
        'nrg in the same cycle is cached independently');
    is(reading_value($hash, 'pvBatteryPower'), '-600.00',
        'nrg input does not publish response-cached battery data early');

    DevIo::run_due_timers(2_030);
    is(reading_value($hash, 'pvBatterySoC'), '61.0',
        'latest response-cached SOC becomes visible at the tick');
    is(reading_value($hash, 'pvBatteryPower'), '-1200.00',
        'latest response-cached battery power becomes visible at the tick');
    is(reading_value($hash, 'power'), '650.00',
        'fresh nrg becomes visible at the same tick');
    is(reading_time($hash, 'power'), reading_time($hash, 'pvBatteryPower'),
        'matched response and nrg values share one timestamp');
};

subtest 'idle policy gates nrg and battery together on the common clock' => sub {
    my $suppressed = fresh_device();
    $attr{$suppressed->{NAME}}{interval} = 30;
    $attr{$suppressed->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 3_000;
    ok(parse_status($suppressed, 'fullStatus', {
        car => 1,
        fbuf_akkuSOC => 40,
        fbuf_pAkku => 250.126,
        fbuf_akkuMode => 1,
        nrg => nrg(0),
    }), 'idle telemetry is accepted while publication is disabled');
    ok(!exists $suppressed->{READINGS}{pvBatteryPower},
        'idle battery telemetry stays passive');
    ok(!exists $suppressed->{READINGS}{power},
        'idle nrg telemetry stays passive');
    is(reading_value($suppressed, 'pvBatteryModeCode'), 1,
        'discrete battery mode still publishes immediately');
    DevIo::run_due_timers(3_030);
    ok(!exists $suppressed->{READINGS}{pvBatteryPower}
        && !exists $suppressed->{READINGS}{power},
        'the common tick keeps both idle-gated owners passive');

    my $enabled = fresh_device();
    $attr{$enabled->{NAME}}{interval} = 30;
    $attr{$enabled->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 3_100;
    ok(parse_status($enabled, 'fullStatus', {
        car => 1,
        fbuf_pAkku => 200,
        nrg => nrg(0),
    }), 'idle telemetry is initially published when enabled');
    $DevIo::NOW = 3_129;
    ok(parse_status($enabled, 'deltaStatus', {
        fbuf_pAkku => 250.126,
        nrg => nrg(10),
    }), 'fresh idle nrg and battery values are cached');
    DevIo::run_due_timers(3_130);
    is(reading_value($enabled, 'power'), '10.00',
        'idle nrg publishes on the common tick');
    is(reading_value($enabled, 'pvBatteryPower'), '250.13',
        'idle battery telemetry publishes on the same tick');
    is(reading_time($enabled, 'power'), reading_time($enabled, 'pvBatteryPower'),
        'idle nrg and battery share one timestamp');
};

subtest 'interval zero publishes each valid telemetry group independently' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 4_000;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        fbuf_pAkku => 10,
    }), 'battery-only delta is independently publishable');
    is(reading_value($hash, 'pvBatteryPower'), '10.00',
        'battery-only input publishes without nrg initialization');
    ok(!exists $hash->{READINGS}{power},
        'battery-only input creates no electrical reading');

    $DevIo::NOW = 4_001;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(100) }),
        'first nrg delta publishes independently');
    is(reading_value($hash, 'power'), '100.00',
        'fresh nrg is published');

    my $battery_cycle_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 4_002;
    ok(parse_status($hash, 'deltaStatus', { fbuf_pAkku => 20 }),
        'second battery-only delta is unlimited');
    is(reading_value($hash, 'pvBatteryPower'), '20.00',
        'fresh battery value is published immediately');
    is(reading_value($hash, 'power'), '100.00',
        'cached nrg is not republished');
    my @battery_cycle = map { $_->[1] } updates_since($battery_cycle_start);
    ok(!grep($_ eq 'power', @battery_cycle)
        && grep($_ eq 'pvBatteryPower', @battery_cycle),
        'battery input updates only the battery group');

    $DevIo::NOW = 4_003;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'second nrg delta also publishes without rate limiting');
    is(reading_value($hash, 'power'), '200.00',
        'fresh nrg is published immediately');
    is(reading_value($hash, 'pvBatteryPower'), '20.00',
        'nrg input leaves battery reading unchanged');
};

my $interface = main::Wattpilot_InterfaceSnapshot();
is($interface->{readings}{pv_battery_soc},
    'pvBatterySoC',
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
