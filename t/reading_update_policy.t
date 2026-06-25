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
        NAME => 'readingPolicyWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000069',
        DeviceName => 'ws:192.0.2.69:80/ws',
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
    my ($hash, $type, $status, $partial) = @_;
    my $message = { type => $type, status => $status };
    $message->{partial} = $partial ? JSON::true() : JSON::false()
        if $type eq 'fullStatus';
    return main::Wattpilot_Parse($hash, encode_json($message));
}

sub parse_response {
    my ($hash, $request_id, $status) = @_;
    $hash->{helper}{pendingRequests}{$request_id} = {
        key => 'syntheticReadback',
        sentAt => $DevIo::NOW,
    };
    return main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => $request_id,
        success => JSON::true(),
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

sub updates_for {
    my ($reading, $start) = @_;
    $start //= 0;
    return scalar grep {
        ($_->[1] // '') eq $reading
    } @DevIo::READING_UPDATES[$start .. $#DevIo::READING_UPDATES];
}

sub events_for {
    my ($reading, $start) = @_;
    $start //= 0;
    return scalar grep {
        ($_->[1] // '') eq $reading
    } @DevIo::READING_EVENTS[$start .. $#DevIo::READING_EVENTS];
}

subtest 'energy telemetry is interval-controlled including timestamps and events' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 1_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        eto => 780_600,
        wh => 6_730,
    }), 'baseline fullStatus is accepted');
    is(reading_value($hash, 'energyTotal'), '780.60',
        'baseline energyTotal is published');
    is(reading_value($hash, 'energySincePlugIn'), '6730.00',
        'baseline energySincePlugIn is published');
    my $total_time = reading_time($hash, 'energyTotal');
    my $plug_time = reading_time($hash, 'energySincePlugIn');

    my $update_start = scalar @DevIo::READING_UPDATES;
    my $event_start = scalar @DevIo::READING_EVENTS;
    $DevIo::NOW = 1_001;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 780_600,
        wh => 6_730,
    }), 'identical energy delta inside the interval is accepted');
    is(reading_time($hash, 'energyTotal'), $total_time,
        'identical energyTotal does not refresh its timestamp');
    is(reading_time($hash, 'energySincePlugIn'), $plug_time,
        'identical energySincePlugIn does not refresh its timestamp');
    is(updates_for('energyTotal', $update_start), 0,
        'identical energyTotal causes no reading update');
    is(events_for('energyTotal', $event_start), 0,
        'identical energyTotal causes no event');

    $DevIo::NOW = 1_029;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 781_000,
        wh => 6_800,
    }), 'changed energy delta before the boundary is accepted');
    is(reading_value($hash, 'energyTotal'), '780.60',
        'changed energy remains rate-limited before the boundary');
    is(reading_time($hash, 'energyTotal'), $total_time,
        'rate-limited energy does not refresh its timestamp');

    $DevIo::NOW = 1_030;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 781_500,
        wh => 6_900,
    }), 'energy delta at the exact boundary is accepted');
    is(reading_value($hash, 'energyTotal'), '781.50',
        'energyTotal updates at the exact boundary');
    is(reading_value($hash, 'energySincePlugIn'), '6900.00',
        'energySincePlugIn updates at the exact boundary');
    isnt(reading_time($hash, 'energyTotal'), $total_time,
        'eligible energy update refreshes its timestamp');

    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::NOW = 1_031;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 782_000,
        wh => 7_000,
    }), 'energy delta with interval zero is accepted');
    is(reading_value($hash, 'energyTotal'), '782.00',
        'interval zero publishes every valid energy change');
};

subtest 'independent telemetry cadences prevent battery-first nrg starvation' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 1,
        nrg => nrg(500),
    }), 'combined charging baseline is accepted');

    for my $cycle (1 .. 3) {
        my $boundary = 2_000 + 30 * $cycle;
        my $battery_power = -500 - 100 * $cycle;
        my $nrg_power = 500 + 100 * $cycle;

        my $nrg_time_before = reading_time($hash, 'power');
        my $battery_start = scalar @DevIo::READING_UPDATES;
        $DevIo::NOW = $boundary;
        ok(parse_status($hash, 'deltaStatus', {
            fbuf_akkuSOC => 50 - $cycle,
            fbuf_pAkku => $battery_power,
        }), "battery-first delta $cycle is accepted");
        is(reading_value($hash, 'pvBatteryPower'), sprintf('%.2f', $battery_power),
            "fresh battery power $cycle is published");
        is(reading_time($hash, 'power'), $nrg_time_before,
            "battery delta $cycle does not refresh stale nrg timestamp");
        is(updates_for('power', $battery_start), 0,
            "battery delta $cycle does not republish cached nrg");

        my $nrg_start = scalar @DevIo::READING_UPDATES;
        ok(parse_status($hash, 'deltaStatus', {
            nrg => nrg($nrg_power, $cycle + 1),
        }), "fresh nrg delta $cycle immediately after battery is accepted");
        is(reading_value($hash, 'power'), sprintf('%.2f', $nrg_power),
            "fresh nrg power $cycle is not starved");
        is(updates_for('pvBatteryPower', $nrg_start), 0,
            "nrg delta $cycle does not republish cached battery telemetry");
    }
};

subtest 'energy and discrete status cannot consume electrical cadence' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        eto => 100_000,
        nrg => nrg(100),
        modelStatus => 12,
    }), 'combined baseline is accepted');

    $DevIo::NOW = 3_030;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        modelStatus => 17,
    }), 'energy and decision delta at the boundary is accepted');
    is(reading_value($hash, 'energyTotal'), '101.00',
        'energy updates on its own cadence');
    is(reading_value($hash, 'chargingDecisionCode'), 17,
        'discrete decision changes immediately');

    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'fresh nrg immediately after energy and status is accepted');
    is(reading_value($hash, 'power'), '200.00',
        'energy and discrete status did not consume nrg cadence');
};

subtest 'unrelated messages cannot release cached telemetry' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_500;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        eto => 100_000,
        nrg => nrg(100),
    }), 'baseline is accepted');

    $DevIo::NOW = 3_529;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'new nrg is cached inside its interval');
    is(reading_value($hash, 'power'), '100.00',
        'cached nrg remains unpublished');

    my $energy_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 3_530;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        modelStatus => 12,
    }), 'unrelated energy and discrete fields are accepted at the boundary');
    is(reading_value($hash, 'power'), '100.00',
        'unrelated fields cannot release cached nrg');
    is(updates_for('power', $energy_start), 0,
        'unrelated fields do not refresh the nrg timestamp');

    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(300) }),
        'fresh nrg at the boundary is accepted');
    is(reading_value($hash, 'power'), '300.00',
        'same-group input publishes the latest nrg snapshot');

    my $idle = fresh_device();
    $attr{$idle->{NAME}}{interval} = 0;
    $attr{$idle->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 3_600;
    ok(parse_status($idle, 'fullStatus', {
        car => 1,
        fbuf_pAkku => -100,
        nrg => nrg(0),
    }), 'idle telemetry is cached while publication is disabled');
    ok(!exists $idle->{READINGS}{power},
        'idle electrical telemetry remains passive');
    ok(!exists $idle->{READINGS}{pvBatteryPower},
        'idle battery telemetry remains passive');

    ok(parse_status($idle, 'deltaStatus', { car => 2 }),
        'charging state change without telemetry is accepted');
    ok(!exists $idle->{READINGS}{power},
        'car change alone does not publish cached nrg');
    ok(!exists $idle->{READINGS}{pvBatteryPower},
        'car change alone does not publish cached battery data');
};

subtest 'discrete status is immediate-on-change and paired readings are atomic' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 300;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 4_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        alw => JSON::false(),
        modelStatus => 0,
        msi => 27,
        err => 0,
        amt => 16,
        fbuf_akkuMode => 1,
    }), 'baseline discrete status is accepted');
    my %time = map { $_ => reading_time($hash, $_) } qw(
        carState chargingAllowed chargingDecisionCode chargingDecision
        chargingDecisionInternalCode chargingDecisionInternal errorCode
        temperatureCurrentLimit pvBatteryModeCode
    );

    my $update_start = scalar @DevIo::READING_UPDATES;
    my $event_start = scalar @DevIo::READING_EVENTS;
    $DevIo::NOW = 4_001;
    ok(parse_status($hash, 'deltaStatus', {
        car => 1,
        alw => JSON::false(),
        modelStatus => 0,
        msi => 27,
        err => 0,
        amt => 16,
        fbuf_akkuMode => 1,
    }), 'identical discrete delta is accepted');
    for my $reading (sort keys %time) {
        is(reading_time($hash, $reading), $time{$reading},
            "identical $reading does not refresh its timestamp");
        is(updates_for($reading, $update_start), 0,
            "identical $reading causes no reading update");
        is(events_for($reading, $event_start), 0,
            "identical $reading causes no event");
    }

    $DevIo::NOW = 4_002;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        alw => JSON::true(),
        modelStatus => 12,
        msi => 28,
        err => 7,
        amt => 15,
        fbuf_akkuMode => 2,
    }), 'changed discrete delta is accepted inside the telemetry interval');
    is(reading_value($hash, 'carState'), 'charging',
        'carState changes immediately');
    is(reading_value($hash, 'chargingAllowed'), 1,
        'chargingAllowed changes immediately');
    is(reading_value($hash, 'chargingDecisionCode'), 12,
        'decision code changes immediately');
    is(reading_value($hash, 'chargingDecision'), 'chargingBecausePvSurplus',
        'decision text changes immediately');
    is(reading_time($hash, 'chargingDecisionCode'),
        reading_time($hash, 'chargingDecision'),
        'paired public decision readings share one transaction timestamp');
    is(reading_value($hash, 'pvBatteryModeCode'), 2,
        'battery mode code is immediate-on-change, not telemetry-gated');
    is($hash->{helper}{car_state}, 2,
        'internal car state is immediately current');
};

subtest 'configuration stays immediate and status paths share one policy' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;

    $DevIo::NOW = 5_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        amp => 6,
        nrg => nrg(10),
    }, 1), 'partial fullStatus is accepted');
    is(reading_value($hash, 'configChargingCurrent'), 6,
        'configuration from partial fullStatus publishes immediately');
    is(reading_value($hash, 'power'), '10.00',
        'partial fullStatus uses the telemetry policy');

    $DevIo::NOW = 5_001;
    ok(parse_status($hash, 'deltaStatus', { amp => 7, nrg => nrg(20) }),
        'deltaStatus inside interval is accepted');
    is(reading_value($hash, 'configChargingCurrent'), 7,
        'configuration from deltaStatus is immediate');
    is(reading_value($hash, 'power'), '10.00',
        'deltaStatus telemetry remains rate-limited');

    $DevIo::NOW = 5_030;
    ok(parse_response($hash, 69, { amp => 8, nrg => nrg(30) }),
        'matched response at the boundary is accepted');
    is(reading_value($hash, 'configChargingCurrent'), 8,
        'configuration from matched response is immediate');
    is(reading_value($hash, 'power'), '30.00',
        'matched response uses the same nrg cadence');
};

subtest 'invalid or incomplete telemetry never advances cadence' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 6_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        eto => 1_000,
        fbuf_pAkku => -100,
        nrg => nrg(100),
    }), 'valid telemetry baseline is accepted');
    my $nrg_last = $hash->{helper}{telemetryPublication}{nrg}{lastUpdate};
    my $battery_last = $hash->{helper}{telemetryPublication}{battery}{lastUpdate};
    my $energy_last = $hash->{helper}{telemetryPublication}{energy}{lastUpdate};

    $DevIo::NOW = 6_030;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 'invalid',
        fbuf_pAkku => 'invalid',
        nrg => [230, 231, 232],
    }), 'invalid telemetry delta is safely accepted after normalization');
    is($hash->{helper}{telemetryPublication}{nrg}{lastUpdate}, $nrg_last,
        'incomplete nrg does not advance nrg history');
    is($hash->{helper}{telemetryPublication}{battery}{lastUpdate}, $battery_last,
        'invalid battery value does not advance battery history');
    is($hash->{helper}{telemetryPublication}{energy}{lastUpdate}, $energy_last,
        'invalid energy value does not advance energy history');
};

subtest '2.1.0 hot-reload state activates the new policy without lifecycle side effects' => sub {
    my $hash = fresh_device();
    my $timer = { kind => 'connect', generation => 7 };
    $hash->{VERSION} = '2.1.0';
    $hash->{FD} = 69;
    $hash->{helper}{timers}{connect} = $timer;
    $hash->{helper}{lifecycleGeneration} = 7;
    $hash->{LAST_UPDATE} = 6_900;
    $hash->{LAST_BATTERY_UPDATE} = 6_900;
    $hash->{helper}{volatileTelemetryCache} = {
        nrg => nrg(1),
        fbuf_pAkku => -1,
    };

    my $module_hash = {};
    main::Wattpilot_Initialize($module_hash);
    is($hash->{VERSION}, '2.1.1',
        'reload-style Initialize refreshes the module version');
    is($hash->{FD}, 69,
        'reload-style Initialize preserves the open transport');
    is($hash->{helper}{timers}{connect}, $timer,
        'reload-style Initialize preserves existing timer ownership');
    is($hash->{helper}{lifecycleGeneration}, 7,
        'reload-style Initialize preserves lifecycle generation');

    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 7_000;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        eto => 2_000,
        fbuf_pAkku => -200,
        nrg => nrg(200),
    }), 'first post-reload status activates the new policy');
    is(reading_value($hash, 'energyTotal'), '2.00',
        'post-reload energy uses the new energy owner');
    is(reading_value($hash, 'pvBatteryPower'), '-200.00',
        'post-reload battery uses the new battery owner');
    is(reading_value($hash, 'power'), '200.00',
        'post-reload electrical telemetry uses the new nrg owner');
    ok(!exists $hash->{LAST_UPDATE}
        && !exists $hash->{LAST_BATTERY_UPDATE}
        && !exists $hash->{helper}{volatileTelemetryCache},
        'obsolete shared-cadence state is discarded safely');
};

subtest 'authoritative reading policy inventory is complete' => sub {
    my $interface = main::Wattpilot_InterfaceSnapshot();
    my $policy = $interface->{readingPolicy};
    is_deeply([sort keys %$policy], [sort keys %{$interface->{readings}}],
        'every public reading has exactly one policy entry');
    for my $key (sort keys %$policy) {
        for my $field (qw(category source publication idleGate owner formatter invalid)) {
            ok(defined($policy->{$key}{$field}) && $policy->{$key}{$field} ne '',
                "$key policy defines $field");
        }
    }
    is($policy->{car_state}{publication}, 'immediate-on-change',
        'carState policy is immediate-on-change');
    is($policy->{energy_total}{publication}, 'interval',
        'energyTotal policy is interval-controlled');
    isnt($policy->{power}{owner}, $policy->{pv_battery_power}{owner},
        'nrg and battery telemetry have different cadence owners');
    isnt($policy->{energy_total}{owner}, $policy->{power}{owner},
        'energy and nrg telemetry have different cadence owners');

    my @configuration = grep {
        $policy->{$_}{category} eq 'configuration'
    } keys %$policy;
    is(scalar @configuration, 24,
        'all 24 configuration readings are inventoried');
    for my $key (sort @configuration) {
        is($policy->{$key}{publication}, 'immediate',
            "$key remains immediate after device confirmation");
        like($policy->{$key}{source}, qr/^status:/,
            "$key is sourced from device status");
    }

    my @discrete = sort grep {
        $policy->{$_}{publication} eq 'immediate-on-change'
    } keys %$policy;
    is_deeply(\@discrete, [sort qw(
        car_state charging_allowed temperature_current_limit
        pv_battery_mode_code charging_decision_code charging_decision
        charging_decision_internal_code charging_decision_internal error_code
    )], 'exactly the nine discrete status/diagnostic readings are immediate-on-change');

    for my $key (qw(
        state firmware_version auth_hash_mode last_command_request_id
        last_command_status last_command_error
    )) {
        is($policy->{$key}{publication}, 'immediate',
            "$key remains event-driven and immediate");
        like($policy->{$key}{source}, qr/^event:/,
            "$key remains outside status payload policy");
    }
};

done_testing;
