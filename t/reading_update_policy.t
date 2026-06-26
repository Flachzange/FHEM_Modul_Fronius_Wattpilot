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
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
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

subtest 'energy telemetry is change-only on the shared telemetry clock' => sub {
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
    DevIo::run_due_timers(1_030);
    is(reading_time($hash, 'energyTotal'), $total_time,
        'identical energyTotal does not refresh its timestamp at the tick');
    is(reading_time($hash, 'energySincePlugIn'), $plug_time,
        'identical energySincePlugIn does not refresh its timestamp at the tick');
    is(updates_for('energyTotal', $update_start), 0,
        'identical energyTotal causes no reading update');
    is(events_for('energyTotal', $event_start), 0,
        'identical energyTotal causes no event');

    $DevIo::NOW = 1_031;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 781_500,
        wh => 6_900,
    }), 'changed idle energy delta is accepted after the first tick');
    is(reading_value($hash, 'energyTotal'), '780.60',
        'changed energy waits for the shared telemetry tick');
    DevIo::run_due_timers(1_060);
    is(reading_value($hash, 'energyTotal'), '781.50',
        'changed energyTotal publishes on the shared tick');
    is(reading_value($hash, 'energySincePlugIn'), '6900.00',
        'changed energySincePlugIn publishes on the shared tick');
    is(reading_time($hash, 'energyTotal'), reading_time($hash, 'energySincePlugIn'),
        'both changed energy readings share one transaction timestamp');

    is(DevIo::command_attr($hash->{NAME}, 'interval', 0), undef,
        'interval zero is accepted through the real attribute path');
    $DevIo::NOW = 1_061;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 782_000,
        wh => 7_000,
    }), 'energy delta with interval zero is accepted');
    is(reading_value($hash, 'energyTotal'), '782.00',
        'interval zero publishes a changed energy value immediately');
};

subtest 'all telemetry owners flush together without cross-owner starvation' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        eto => 100_000,
        wh => 1_000,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        nrg => nrg(500),
    }), 'combined charging baseline is accepted');
    is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
        'initial nrg and diagnostics values share one transaction timestamp');
    is(reading_time($hash, 'power'), reading_time($hash, 'energyTotal'),
        'initial energy and nrg values share one transaction timestamp');

    $DevIo::NOW = 2_029;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 49,
        fbuf_pAkku => -600,
    }), 'diagnostic-first input is cached');
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        wh => 1_100,
    }), 'energy input in the same cycle is cached');
    ok(parse_status($hash, 'deltaStatus', {
        nrg => nrg(600, 2),
    }), 'nrg input in the same cycle is cached');
    is(reading_value($hash, 'power'), '500.00',
        'nrg remains unchanged before the shared tick');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-500.00',
        'diagnostic remains unchanged before the shared tick');
    is(reading_value($hash, 'energyTotal'), '100.00',
        'energy remains unchanged before the shared tick');

    DevIo::run_due_timers(2_030);
    is(reading_value($hash, 'power'), '600.00',
        'fresh nrg publishes on the shared tick');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-600.00',
        'fresh battery diagnostics publish on the shared tick');
    is(reading_value($hash, 'energyTotal'), '101.00',
        'changed energy publishes on the shared tick');
    is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
        'nrg and diagnostics use the same tick timestamp');
    is(reading_time($hash, 'power'), reading_time($hash, 'energyTotal'),
        'energy and nrg use the same tick timestamp');

    for my $cycle (1 .. 2) {
        my $input_time = 2_030 + 30 * $cycle - 1;
        my $tick = 2_030 + 30 * $cycle;
        my $power = 600 + 100 * $cycle;
        $DevIo::NOW = $input_time;
        ok(parse_status($hash, 'deltaStatus', {
            fbuf_pAkku => -600 - 100 * $cycle,
        }), "diagnostic-first input for cycle $cycle is accepted");
        ok(parse_status($hash, 'deltaStatus', {
            nrg => nrg($power, 2 + $cycle),
        }), "nrg input for cycle $cycle is accepted");
        DevIo::run_due_timers($tick);
        is(reading_value($hash, 'power'), sprintf('%.2f', $power),
            "fresh nrg cycle $cycle is never starved");
        is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
            "cycle $cycle shares one telemetry timestamp");
    }
};

subtest 'idle gating applies only to nrg and diagnostics while energy stays change-only' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        eto => 100_000,
        wh => 1_000,
        fbuf_pAkku => -100,
        nrg => nrg(0),
    }), 'idle baseline is accepted');
    is(reading_value($hash, 'energyTotal'), '100.00',
        'initial energy value is published even from an idle fullStatus');
    ok(!exists $hash->{READINGS}{power},
        'idle nrg remains passive with update_while_idle zero');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'idle diagnostic remains passive with update_while_idle zero');

    $DevIo::NOW = 3_029;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        wh => 1_100,
        fbuf_pAkku => -200,
        nrg => nrg(10),
    }), 'changed idle telemetry is cached');
    DevIo::run_due_timers(3_030);
    is(reading_value($hash, 'energyTotal'), '101.00',
        'changed energy publishes on the shared tick while idle');
    ok(!exists $hash->{READINGS}{power},
        'idle nrg stays gated at the tick');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'idle diagnostics stays gated at the tick');

    my $enabled = fresh_device();
    $attr{$enabled->{NAME}}{interval} = 30;
    $attr{$enabled->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 3_100;
    ok(parse_status($enabled, 'fullStatus', {
        car => 1,
        fbuf_pAkku => -200,
        nrg => nrg(10),
    }), 'idle baseline is published when update_while_idle is enabled');
    $DevIo::NOW = 3_129;
    ok(parse_status($enabled, 'deltaStatus', {
        fbuf_pAkku => -300,
        nrg => nrg(20),
    }), 'fresh idle nrg and diagnostics values are cached while enabled');
    DevIo::run_due_timers(3_130);
    is(reading_value($enabled, 'power'), '20.00',
        'idle nrg publishes on the common tick when enabled');
    is(reading_value($enabled, 'diag_fbuf_pAkku'), '-300.00',
        'idle diagnostics publishes on the common tick when enabled');
    is(reading_time($enabled, 'power'), reading_time($enabled, 'diag_fbuf_pAkku'),
        'idle nrg and diagnostics share the common tick timestamp');
};

subtest 'unrelated immediate status cannot flush cached telemetry early' => sub {
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
        'new nrg is cached inside the interval');
    ok(parse_status($hash, 'deltaStatus', { modelStatus => 12 }),
        'unrelated discrete status is accepted');
    is(reading_value($hash, 'power'), '100.00',
        'discrete status cannot release cached nrg');
    is(reading_value($hash, 'chargingDecisionCode'), 12,
        'discrete status still publishes immediately');

    DevIo::run_due_timers(3_530);
    is(reading_value($hash, 'power'), '200.00',
        'cached nrg publishes only on the common tick');
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
    }), 'baseline discrete status is accepted');
    my %time = map { $_ => reading_time($hash, $_) } qw(
        carState chargingAllowed chargingDecisionCode chargingDecision
        chargingDecisionInternalCode chargingDecisionInternal errorCode
        temperatureCurrentLimit
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

subtest 'interval transition to zero flushes all currently eligible dirty owners' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 5_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        eto => 100_000,
        wh => 1_000,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        nrg => nrg(500),
    }), 'charging baseline starts a positive shared interval');
    my $old_ctx = $hash->{helper}{timers}{telemetry_flush};

    $DevIo::NOW = 5_001;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        wh => 1_100,
        fbuf_akkuSOC => 49,
        fbuf_pAkku => -600,
        nrg => nrg(600, 2),
    }), 'all owners become dirty before the boundary');
    is(reading_value($hash, 'power'), '500.00', 'nrg remains queued before interval zero');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-500.00', 'diagnostic remains queued before interval zero');
    is(reading_value($hash, 'energyTotal'), '100.00', 'energy remains queued before interval zero');

    $DevIo::NOW = 5_002;
    my $events_before = scalar @DevIo::READING_EVENTS;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 0), undef,
        'positive-to-zero transition is accepted');
    is(reading_value($hash, 'power'), '600.00', 'eligible dirty nrg flushes immediately');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-600.00', 'eligible dirty battery flushes immediately');
    is(reading_value($hash, 'energyTotal'), '101.00', 'eligible changed energy flushes immediately');
    is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
        'nrg and diagnostics share the attribute-change transaction timestamp');
    is(reading_time($hash, 'power'), reading_time($hash, 'energyTotal'),
        'all flushed owners share one transaction timestamp');
    ok(!exists $hash->{helper}{telemetryClock}, 'interval zero removes the shared clock');
    ok(!exists $hash->{helper}{timers}{telemetry_flush}, 'interval zero removes timer ownership');
    for my $owner (qw(nrg diagnostic energy)) {
        ok(!keys %{$hash->{helper}{telemetryPublication}{$owner}{dirty}},
            "interval zero clears eligible $owner dirty state");
    }
    main::Wattpilot_TelemetryFlush($old_ctx);
    is(reading_value($hash, 'power'), '600.00', 'stale old timer cannot republish after interval zero');

    my $events_after_flush = scalar @DevIo::READING_EVENTS;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 0), undef,
        'repeating interval zero is accepted');
    is(scalar @DevIo::READING_EVENTS, $events_after_flush,
        'repeating interval zero without dirty data emits no reading events');

    $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 5_100;
    ok(parse_status($hash, 'fullStatus', {
        car => 2, eto => 200_000, fbuf_pAkku => -700, nrg => nrg(700),
    }), 'second charging baseline is accepted');
    $DevIo::NOW = 5_101;
    ok(parse_status($hash, 'deltaStatus', { car => 1 }),
        'car transitions to idle');
    # Consume the bounded idle bypass, then queue later ordinary idle input.
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(0) }),
        'authoritative one-shot idle nrg is accepted');
    $DevIo::NOW = 5_102;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 201_000, fbuf_pAkku => -800, nrg => nrg(800),
    }), 'later idle telemetry is cached');
    is(DevIo::command_attr($hash->{NAME}, 'interval', 0), undef,
        'idle positive-to-zero transition is accepted');
    is(reading_value($hash, 'energyTotal'), '201.00',
        'changed energy remains eligible while idle');
    isnt(reading_value($hash, 'power'), '800.00',
        'ineligible ordinary idle nrg is not flushed by the attribute change');
    isnt(reading_value($hash, 'diag_fbuf_pAkku'), '-800.00',
        'ineligible idle diagnostics is not flushed by the attribute change');
    ok(keys %{$hash->{helper}{telemetryPublication}{nrg}{dirty}},
        'ineligible idle nrg remains dirty and passive');
    ok(keys %{$hash->{helper}{telemetryPublication}{diagnostic}{dirty}},
        'ineligible idle diagnostic remains dirty and passive');
    ok(!keys %{$hash->{helper}{telemetryPublication}{energy}{dirty}},
        'eligible energy dirty state is consumed');

    $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 5_200;
    ok(parse_status($hash, 'fullStatus', { car => 2, nrg => nrg(900) }),
        'delete-attribute baseline is accepted');
    $DevIo::NOW = 5_201;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(901) }),
        'delete-attribute nrg becomes dirty');
    is(DevIo::command_delete_attr($hash->{NAME}, 'interval'), undef,
        'deleting interval is accepted');
    is(reading_value($hash, 'power'), '901.00',
        'deleting interval applies the effective default zero immediately');
    ok(!exists $hash->{helper}{telemetryClock},
        'deleting interval removes the old shared clock');
};

subtest 'positive interval changes replace one timer and preserve queued telemetry' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 5_500;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        nrg => nrg(100),
    }), 'first telemetry input starts the shared clock');
    my $first_ctx = $hash->{helper}{timers}{telemetry_flush};
    ok(ref($first_ctx) eq 'HASH',
        'shared clock owns a telemetry_flush timer context');
    is($hash->{helper}{telemetryClock}{nextFlush}, 5_530,
        'first telemetry input establishes the common boundary');
    is((scalar grep {
        $_->[1] eq 'Wattpilot_TelemetryFlush' && $_->[2] == $first_ctx
    } @DevIo::ACTIVE_TIMERS), 1,
        'exactly one active timer represents the shared clock');

    $DevIo::NOW = 5_501;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 1_000,
        fbuf_pAkku => -100,
        nrg => nrg(110),
    }), 'all telemetry owners become dirty inside the first interval');
    is(reading_value($hash, 'power'), '100.00',
        'queued nrg is not published before the boundary');
    ok(!defined $hash->{READINGS}{energyTotal}{VAL},
        'new energy remains queued before the boundary');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'new battery diagnostics remains queued before the boundary');

    $DevIo::NOW = 5_502;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 60), undef,
        'first positive-to-positive interval change is accepted');
    my $second_ctx = $hash->{helper}{timers}{telemetry_flush};
    ok(ref($second_ctx) eq 'HASH',
        'dirty telemetry immediately receives a replacement timer');
    isnt($second_ctx, $first_ctx,
        'replacement timer uses a fresh lifecycle-safe context');
    is($hash->{helper}{telemetryClock}{nextFlush}, 5_562,
        'replacement boundary is based on the new interval and change time');
    is(reading_value($hash, 'power'), '100.00',
        'positive interval change does not flush queued telemetry early');
    is((scalar grep {
        $_->[1] eq 'Wattpilot_TelemetryFlush' && $_->[2] == $second_ctx
    } @DevIo::ACTIVE_TIMERS), 1,
        'the first interval change leaves exactly one owned timer');

    $DevIo::NOW = 5_503;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 45), undef,
        'repeated positive interval change is accepted');
    my $third_ctx = $hash->{helper}{timers}{telemetry_flush};
    ok(ref($third_ctx) eq 'HASH',
        'repeated change still owns a telemetry timer');
    isnt($third_ctx, $second_ctx,
        'repeated change replaces the previous timer context');
    is($hash->{helper}{telemetryClock}{nextFlush}, 5_548,
        'latest positive interval defines the only active boundary');
    is((scalar grep {
        $_->[1] eq 'Wattpilot_TelemetryFlush'
    } @DevIo::ACTIVE_TIMERS), 1,
        'repeated positive changes cannot create duplicate timers');

    my $power_time = reading_time($hash, 'power');
    main::Wattpilot_TelemetryFlush($first_ctx);
    main::Wattpilot_TelemetryFlush($second_ctx);
    is($hash->{helper}{timers}{telemetry_flush}, $third_ctx,
        'obsolete callbacks cannot steal replacement timer ownership');
    is(reading_time($hash, 'power'), $power_time,
        'obsolete callbacks cannot publish queued telemetry');

    DevIo::run_due_timers(5_548);
    is(reading_value($hash, 'power'), '110.00',
        'queued nrg publishes at the replacement boundary without new input');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-100.00',
        'queued battery diagnostics publish at the replacement boundary');
    is(reading_value($hash, 'energyTotal'), '1.00',
        'queued energy publishes at the replacement boundary');
    is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
        'replacement-boundary nrg and diagnostics share one transaction timestamp');
    is(reading_time($hash, 'power'), reading_time($hash, 'energyTotal'),
        'all replacement-boundary owners share one transaction timestamp');
    is((scalar grep {
        $_->[1] eq 'Wattpilot_TelemetryFlush'
    } @DevIo::ACTIVE_TIMERS), 1,
        'the shared cadence advances with exactly one timer after publication');

    is(DevIo::command_attr($hash->{NAME}, 'disable', 1), undef,
        'disabling the device is accepted through the real attribute path');
    ok(!exists $hash->{helper}{telemetryClock},
        'session invalidation clears the shared telemetry clock');
    ok(!exists $hash->{helper}{timers}{telemetry_flush},
        'session invalidation cancels the telemetry timer');

    $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 5_600;
    ok(parse_status($hash, 'fullStatus', { car => 2, nrg => nrg(200) }),
        'clean baseline starts a clock and publishes its only telemetry');
    ok(!main::Wattpilot_HasDirtyTelemetry($hash),
        'baseline publication leaves no dirty telemetry');
    $DevIo::NOW = 5_601;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 60), undef,
        'positive interval change without dirty telemetry is accepted');
    ok(!exists $hash->{helper}{telemetryClock},
        'no dirty telemetry keeps the replacement clock lazy');
    ok(!exists $hash->{helper}{timers}{telemetry_flush},
        'no dirty telemetry creates no unnecessary timer');

    $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 5_700;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        eto => 100_000,
        fbuf_pAkku => -100,
        nrg => nrg(0),
    }), 'idle baseline retains gated telemetry and publishes energy');
    $DevIo::NOW = 5_701;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 101_000,
        fbuf_pAkku => -200,
        nrg => nrg(10),
    }), 'idle energy, nrg, and diagnostics become dirty');
    $DevIo::NOW = 5_702;
    is(DevIo::command_attr($hash->{NAME}, 'interval', 60), undef,
        'idle positive-to-positive change is accepted');
    is($hash->{helper}{telemetryClock}{nextFlush}, 5_762,
        'dirty idle telemetry receives the new positive boundary');
    DevIo::run_due_timers(5_762);
    is(reading_value($hash, 'energyTotal'), '101.00',
        'eligible changed energy publishes at the new boundary while idle');
    ok(!exists $hash->{READINGS}{power},
        'ineligible idle nrg remains passive at the new boundary');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'ineligible idle diagnostic remains passive at the new boundary');
    ok(keys %{$hash->{helper}{telemetryPublication}{nrg}{dirty}},
        'ineligible idle nrg remains dirty after the boundary');
    ok(keys %{$hash->{helper}{telemetryPublication}{diagnostic}{dirty}},
        'ineligible idle diagnostic remains dirty after the boundary');
    ok(!keys %{$hash->{helper}{telemetryPublication}{energy}{dirty}},
        'eligible energy dirty state is consumed at the boundary');
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
    my $next_flush = $hash->{helper}{telemetryClock}{nextFlush};
    for my $owner (qw(nrg diagnostic energy)) {
        $hash->{helper}{telemetryPublication}{$owner}{dirty} = {};
    }

    $DevIo::NOW = 6_029;
    ok(parse_status($hash, 'deltaStatus', {
        eto => 'invalid',
        fbuf_pAkku => { invalid => 1 },
        nrg => [230, 231, 232],
    }), 'invalid telemetry delta is safely accepted after normalization');
    is($hash->{helper}{telemetryClock}{nextFlush}, $next_flush,
        'invalid input does not move the shared telemetry boundary');
    for my $owner (qw(nrg diagnostic energy)) {
        ok(!keys %{$hash->{helper}{telemetryPublication}{$owner}{dirty}},
            "invalid input does not dirty the $owner owner");
    }
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
    is($hash->{VERSION}, '2.1.7',
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
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-200.00',
        'post-reload diagnostics uses the new diagnostic owner');
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
    is($interface->{telemetryCadence}{mode}, 'shared',
        'all interval-controlled telemetry uses one shared cadence');
    is_deeply($interface->{telemetryCadence}{owners}, [qw(
        device_health device_uptime diagnostic energy nrg
    )], 'the shared cadence derives all five telemetry owners from policy');
    isnt($policy->{power}{owner}, $policy->{diag_fbuf_p_akku}{owner},
        'nrg and diagnostics have different cadence owners');
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
        firmware_version device_type device_model device_sub_type device_variant
        hello_protocol status_protocol car_state charging_allowed
        temperature_current_limit charging_decision_code
        charging_decision charging_decision_internal_code
        charging_decision_internal error_code
    )], 'identity and discrete status readings are exactly immediate-on-change');

    for my $key (qw(
        state auth_hash_mode last_command_request_id
        last_command_status last_command_error
    )) {
        is($policy->{$key}{publication}, 'immediate',
            "$key remains event-driven and immediate");
        like($policy->{$key}{source}, qr/^event:/,
            "$key remains outside status payload policy");
    }

    for my $key (qw(firmware_version hello_protocol)) {
        is($policy->{$key}{publication}, 'immediate-on-change',
            "$key remains event-sourced but suppresses identical reconnect values");
        like($policy->{$key}{source}, qr/^event:/,
            "$key remains outside status payload policy");
    }

    is($policy->{device_reboot_count}{idleGate}, 'none',
        'deviceRebootCount is interval-controlled without an idle gate');
    is($policy->{device_uptime}{idleGate}, 'device',
        'uptime uses the charging/update_while_idle gate');
    my @optional_diagnostic = grep {
        $policy->{$_}{category} eq 'optional_diagnostic'
    } keys %$policy;
    is(scalar @optional_diagnostic, 15,
        'all fifteen optional raw diagnostics are inventoried');
    for my $key (@optional_diagnostic) {
        is($policy->{$key}{publication}, 'interval',
            "$key follows the shared interval");
        is($policy->{$key}{idleGate}, 'diagnostic',
            "$key uses the common diagnostic idle gate");
        is($policy->{$key}{owner}, 'diagnostic',
            "$key uses the diagnostic owner");
        is($policy->{$key}{formatter}, 'diagnostic2',
            "$key rounds JSON numbers while preserving strings and booleans");
    }
};

done_testing;
