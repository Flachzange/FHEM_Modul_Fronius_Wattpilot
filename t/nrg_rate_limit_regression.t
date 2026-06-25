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
        NAME => 'nrgRegressionWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000051',
        DeviceName => 'ws:192.0.2.51:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub nrg {
    my ($power, $current) = @_;
    $current //= 1;
    return [
        230, 231, 232, 0,
        $current, $current, $current,
        230 * $current, 231 * $current, 232 * $current,
        0, $power,
    ];
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    return main::Wattpilot_Parse($hash, encode_json({
        type => $type,
        status => $status,
    }));
}

sub reading_value {
    my ($hash, $reading) = @_;
    return $hash->{READINGS}{$reading}{VAL};
}

sub reading_time {
    my ($hash, $reading) = @_;
    return $hash->{READINGS}{$reading}{TIME};
}

sub clock_next {
    my ($hash) = @_;
    return $hash->{helper}{telemetryClock}{nextFlush};
}

subtest 'charging nrg uses one shared telemetry clock for both idle settings' => sub {
    for my $idle_setting (0, 1) {
        my $hash = fresh_device();
        $attr{$hash->{NAME}}{interval} = 30;
        $attr{$hash->{NAME}}{update_while_idle} = $idle_setting;

        $DevIo::NOW = 1_000;
        ok(parse_status($hash, 'fullStatus', {
            car => 2,
            nrg => nrg(690),
        }), "charging fullStatus is accepted with update_while_idle=$idle_setting");
        is(reading_value($hash, 'power'), '690.00',
            "charging nrg is initially published with update_while_idle=$idle_setting");
        is($hash->{helper}{car_state}, 2,
            'car helper contains the charging state from the same message');
        is(clock_next($hash), 1_030,
            'the shared telemetry clock starts at one exact boundary');

        $DevIo::NOW = 1_029;
        ok(parse_status($hash, 'deltaStatus', { nrg => nrg(750) }),
            'charging delta before the boundary is cached');
        is(reading_value($hash, 'power'), '690.00',
            'charging nrg remains unchanged before the shared boundary');
        is(clock_next($hash), 1_030,
            'input does not move the shared boundary');

        $DevIo::NOW = 1_030;
        ok(parse_status($hash, 'deltaStatus', { nrg => nrg(900) }),
            'charging delta at the exact shared boundary is accepted');
        is(reading_value($hash, 'power'), '900.00',
            'latest charging nrg publishes at the exact shared boundary');
        is(clock_next($hash), 1_060,
            'the shared clock advances by exactly one interval');
    }
};

subtest 'idle nrg follows update_while_idle without creating another clock' => sub {
    my $suppressed = fresh_device();
    $attr{$suppressed->{NAME}}{interval} = 30;
    $attr{$suppressed->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 2_000;
    ok(parse_status($suppressed, 'fullStatus', {
        car => 1,
        nrg => nrg(0),
    }), 'idle fullStatus is accepted while idle updates are disabled');
    ok(!exists $suppressed->{READINGS}{power},
        'idle nrg stays passive with update_while_idle=0');
    is(clock_next($suppressed), 2_030,
        'suppressed telemetry still belongs to the single shared clock');
    DevIo::run_due_timers(2_030);
    ok(!exists $suppressed->{READINGS}{power},
        'the common tick respects the closed idle gate');

    my $enabled = fresh_device();
    $attr{$enabled->{NAME}}{interval} = 30;
    $attr{$enabled->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 2_100;
    ok(parse_status($enabled, 'fullStatus', {
        car => 1,
        nrg => nrg(0),
    }), 'idle fullStatus is accepted while idle updates are enabled');
    is(reading_value($enabled, 'power'), '0.00',
        'real idle nrg is initially published when enabled');
    is(clock_next($enabled), 2_130,
        'idle nrg uses the same shared clock structure');
};

subtest 'interval zero disables the shared rate limit' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'deltaStatus', { car => 2, nrg => nrg(100) }),
        'first unlimited charging delta is accepted');
    is(reading_value($hash, 'power'), '100.00',
        'first unlimited nrg value is processed');

    $DevIo::NOW = 3_001;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'second unlimited charging delta is accepted');
    is(reading_value($hash, 'power'), '200.00',
        'interval=0 admits consecutive nrg values');
    ok(!exists $hash->{helper}{telemetryClock},
        'interval=0 does not leave a shared timer clock behind');
};

subtest 'battery-first ordering cannot starve nrg on the common tick' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 4_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 51,
        fbuf_pAkku => -400,
        nrg => nrg(690),
    }), 'combined charging baseline is accepted');

    $DevIo::NOW = 4_029;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
    }), 'battery-first delta is cached');
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(900) }),
        'fresh nrg immediately after battery is cached');
    is(reading_value($hash, 'power'), '690.00',
        'neither owner publishes before the common tick');

    DevIo::run_due_timers(4_030);
    is(reading_value($hash, 'power'), '900.00',
        'fresh nrg is not starved by battery input');
    is(reading_value($hash, 'pvBatteryPower'), '-500.00',
        'fresh battery input publishes on the same tick');
    is(reading_time($hash, 'power'), reading_time($hash, 'pvBatteryPower'),
        'nrg and battery receive the same FHEM timestamp');
};

subtest 'invalid or incomplete nrg cannot dirty or move the common clock' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 5_000;
    ok(parse_status($hash, 'deltaStatus', { car => 2, nrg => nrg(300) }),
        'baseline charging nrg is accepted');
    is(reading_value($hash, 'power'), '300.00',
        'baseline nrg is visible');

    $DevIo::NOW = 5_029;
    ok(parse_status($hash, 'deltaStatus', {
        amp => 16,
        nrg => [230, 231, 232],
    }), 'delta with incomplete nrg and another valid field is accepted');
    is(reading_value($hash, 'configChargingCurrent'), 16,
        'another valid field in the same delta still updates');
    ok(!keys %{$hash->{helper}{telemetryPublication}{nrg}{dirty}},
        'incomplete nrg does not dirty the electrical owner');
    is(clock_next($hash), 5_030,
        'incomplete nrg does not move the common boundary');

    DevIo::run_due_timers(5_030);
    is(reading_value($hash, 'power'), '300.00',
        'empty electrical owner publishes nothing at the tick');

    $DevIo::NOW = 5_031;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(400) }),
        'valid nrg after the empty tick is cached');
    is(reading_value($hash, 'power'), '300.00',
        'valid nrg waits for the next shared tick');
    DevIo::run_due_timers(5_060);
    is(reading_value($hash, 'power'), '400.00',
        'the valid nrg publishes at the next shared tick');
};

subtest 'observed fullStatus and matched responses use the common clock' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;

    my $fixture_path = File::Spec->catfile(
        $root, 't', 'fixtures', 'fullStatus-flex-observed.json');
    open my $fixture_fh, '<:raw', $fixture_path
        or die "Cannot read $fixture_path: $!";
    local $/;
    my $fixture = decode_json(<$fixture_fh>);
    close $fixture_fh;

    $DevIo::NOW = 5_500;
    ok(main::Wattpilot_DispatchMessage($hash, $fixture),
        'sanitized observed Flex fullStatus is accepted');
    is(reading_value($hash, 'voltageL1'), '230.00',
        'observed Flex voltage is initially published');
    is(reading_value($hash, 'pvBatteryPower'), '-1525.00',
        'observed Flex battery power is initially published');
    is(clock_next($hash), 5_530,
        'observed fullStatus starts one common telemetry clock');

    $hash->{helper}{pendingRequests}{51} = {
        key => 'syntheticNrgReadback',
        sentAt => 5_529,
    };
    $DevIo::NOW = 5_529;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => 51,
        success => JSON::true(),
        status => {
            nrg => nrg(30),
            fbuf_pAkku => -1400,
        },
    })), 'matched response carrying telemetry is accepted');
    is(reading_value($hash, 'power'), '0.00',
        'matched response remains cached before the tick');

    DevIo::run_due_timers(5_530);
    is(reading_value($hash, 'power'), '30.00',
        'matched response nrg publishes on the common tick');
    is(reading_value($hash, 'pvBatteryPower'), '-1400.00',
        'matched response battery power publishes on the common tick');
    is(reading_time($hash, 'power'), reading_time($hash, 'pvBatteryPower'),
        'response owners share one transaction timestamp');
};

done_testing;
