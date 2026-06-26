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

my @diag_readings = qw(
    diag_fbuf_akkuMode
    diag_fbuf_akkuSOC
    diag_fbuf_pAkku
    diag_fbuf_pGrid
    diag_fbuf_pPv
    diag_pvopt_averagePGrid
    diag_pvopt_averagePPv
    diag_pvopt_averagePAkku
    diag_pvopt_averagePOhmpilot
    diag_pvopt_deltaP
    diag_pvopt_deltaA
    diag_pvopt_specialCase
    diag_fbuf_pAcTotal
    diag_fbuf_ohmpilotState
    diag_fbuf_ohmpilotTemperature
);

sub fresh_device {
    my ($name) = @_;
    $name //= 'issue87Wallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => $name,
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000087',
        DeviceName => 'ws:192.0.2.87:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$name} = $hash;
    return $hash;
}

sub parse_message {
    my ($hash, $message) = @_;
    return main::Wattpilot_Parse($hash, encode_json($message));
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    my $message = { type => $type, status => $status };
    $message->{partial} = JSON::false() if $type eq 'fullStatus';
    return parse_message($hash, $message);
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

sub diagnostic_status {
    return {
        fbuf_akkuMode => 1,
        fbuf_akkuSOC => 60.1256789,
        fbuf_pAkku => -1525.9876543,
        fbuf_pGrid => 125.1256789,
        fbuf_pPv => -1650.25,
        pvopt_averagePGrid => 1.23456789,
        pvopt_averagePPv => 2,
        pvopt_averagePAkku => -3.5,
        pvopt_averagePOhmpilot => 4.75,
        pvopt_deltaP => -5.125,
        pvopt_deltaA => 6.625,
        pvopt_specialCase => 7,
        fbuf_pAcTotal => 'raw-ac-value',
        fbuf_ohmpilotState => JSON::true(),
        fbuf_ohmpilotTemperature => JSON::false(),
    };
}

subtest 'identity readings keep their exact sources separate' => sub {
    my $hash = fresh_device();

    $DevIo::NOW = 1_000;
    ok(parse_message($hash, {
        type => 'hello',
        devicetype => 'wattpilot',
        protocol => 2,
        version => '43.4',
        serial => '10000001',
    }), 'valid hello is accepted');
    is(reading_value($hash, 'firmwareVersion'), '43.4',
        'firmwareVersion comes from hello.version');
    is(reading_value($hash, 'helloProtocol'), 2,
        'helloProtocol comes from hello.protocol');
    ok(!exists $hash->{READINGS}{deviceType},
        'hello.devicetype remains an internal compatibility value');
    is($hash->{helper}{deviceType}, 'wattpilot',
        'hello.devicetype remains available internally');

    my $firmware_time = reading_time($hash, 'firmwareVersion');
    my $protocol_time = reading_time($hash, 'helloProtocol');
    my $update_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 1_001;
    ok(parse_message($hash, {
        type => 'hello',
        devicetype => 'wattpilot',
        protocol => 2,
        version => '43.4',
    }), 'identical hello is accepted');
    is(reading_time($hash, 'firmwareVersion'), $firmware_time,
        'identical firmware does not renew its timestamp');
    is(reading_time($hash, 'helloProtocol'), $protocol_time,
        'identical hello protocol does not renew its timestamp');
    is(updates_for('firmwareVersion', $update_start), 0,
        'identical firmware produces no reading update');
    is(updates_for('helloProtocol', $update_start), 0,
        'identical hello protocol produces no reading update');

    $DevIo::NOW = 1_010;
    ok(parse_status($hash, 'fullStatus', {
        typ => 'wattpilot_flex',
        grp => 'Wattpilot Flex Home 22 C6',
        styp => 'wattpilot_flex_c6',
        var => 22,
        proto => 4,
    }), 'identity status is accepted');
    is(reading_value($hash, 'deviceType'), 'wattpilot_flex',
        'deviceType comes from status.typ');
    is(reading_value($hash, 'deviceModel'), 'Wattpilot Flex Home 22 C6',
        'deviceModel preserves status.grp');
    is(reading_value($hash, 'deviceSubType'), 'wattpilot_flex_c6',
        'deviceSubType preserves status.styp');
    is(reading_value($hash, 'deviceVariant'), 22,
        'deviceVariant preserves status.var');
    is(reading_value($hash, 'statusProtocol'), 4,
        'statusProtocol remains distinct from helloProtocol');
    is(reading_value($hash, 'helloProtocol'), 2,
        'status protocol does not overwrite helloProtocol');

    my %before = map { $_ => reading_value($hash, $_) } qw(
        deviceType deviceModel deviceSubType deviceVariant statusProtocol
    );
    ok(parse_status($hash, 'deltaStatus', {
        typ => '',
        grp => 22,
        styp => JSON::true(),
        var => '22',
        proto => -1,
    }), 'invalid identity delta is ignored field by field');
    for my $reading (sort keys %before) {
        is(reading_value($hash, $reading), $before{$reading},
            "$reading preserves its previous valid value");
    }
};

subtest 'device health readings share interval timing with separate idle gates' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        rbc => 104,
        rbt => 62_068_619,
    }), 'idle health status is accepted');
    is(reading_value($hash, 'deviceRebootCount'), 104,
        'reboot count publishes during idle');
    ok(!exists $hash->{READINGS}{uptime},
        'uptime remains gated while idle');

    $DevIo::NOW = 2_029;
    ok(parse_status($hash, 'deltaStatus', {
        rbc => 105,
        rbt => 62_069_999,
    }), 'changed health values are cached');
    DevIo::run_due_timers(2_030);
    is(reading_value($hash, 'deviceRebootCount'), 105,
        'reboot count publishes at the normal interval while idle');
    ok(!exists $hash->{READINGS}{uptime},
        'uptime remains gated at the interval boundary');

    is(DevIo::command_attr($hash->{NAME}, 'update_while_idle', 1), undef,
        'idle updates can be enabled');
    $DevIo::NOW = 2_059;
    ok(parse_status($hash, 'deltaStatus', { rbt => 62_070_123 }),
        'latest uptime in milliseconds is cached');
    DevIo::run_due_timers(2_060);
    is(reading_value($hash, 'uptime'), '17:14',
        'uptime converts milliseconds to cumulative hours and minutes when idle updates are enabled');

    my $charging = fresh_device('chargingHealthWallbox');
    $attr{$charging->{NAME}}{interval} = 30;
    $attr{$charging->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 2_100;
    ok(parse_status($charging, 'fullStatus', {
        car => 2,
        rbt => 77_777,
    }), 'charging health status is accepted');
    is(reading_value($charging, 'uptime'), '0:01',
        'charging opens the uptime idle gate after converting milliseconds');
};

subtest 'optional raw diagnostics are boolean-enabled, interval-controlled, and removable' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        %{diagnostic_status()},
    }), 'diagnostic fields are accepted while the feature is disabled');
    for my $reading (@diag_readings) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading is absent by default");
    }
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'disabled diagnostics create no cache owner');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 1), undef,
        'diagnosticReadings accepts one');
    $DevIo::NOW = 3_010;
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        %{diagnostic_status()},
    }), 'enabled diagnostic status is accepted');
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'battery mode is exposed only as a rounded raw diagnostic');
    ok(!exists $hash->{READINGS}{pvBatteryModeCode},
        'the former normal battery mode reading is not recreated');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '60.13',
        'former battery SOC telemetry is rounded to two decimals');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-1525.99',
        'former battery power telemetry is rounded to two decimals');
    # BEGIN 2.0 negative controls for removed public names
    ok(!exists $hash->{READINGS}{pvBatterySoC},
        'the former public battery SOC reading is not recreated');
    ok(!exists $hash->{READINGS}{pvBatteryPower},
        'the former public battery power reading is not recreated');
    # END 2.0 negative controls for removed public names
    is(reading_value($hash, 'diag_fbuf_pGrid'), '125.13',
        'numeric diagnostics are rounded to two decimals');
    ok(!ref($hash->{helper}{telemetryPublication}{diagnostic}{cache}{fbuf_pGrid}),
        'numeric diagnostic cache keeps the original plain JSON scalar type');
    is(reading_value($hash, 'diag_fbuf_pPv'), '-1650.25',
        'signed diagnostics are not reinterpreted');
    is(reading_value($hash, 'diag_pvopt_averagePGrid'), '1.23',
        'numeric diagnostic detail is rounded consistently');
    is(reading_value($hash, 'diag_fbuf_pAcTotal'), 'raw-ac-value',
        'string diagnostics are copied unchanged');
    is(reading_value($hash, 'diag_fbuf_ohmpilotState'), 1,
        'true diagnostic boolean is normalized to one');
    is(reading_value($hash, 'diag_fbuf_ohmpilotTemperature'), 0,
        'false diagnostic boolean is normalized to zero');

    $DevIo::NOW = 3_039;
    ok(parse_status($hash, 'deltaStatus', {
        diag_unused => 1,
        fbuf_pGrid => 222.2222222,
        fbuf_pAcTotal => { nested => 1 },
        fbuf_ohmpilotState => [1, 2],
        fbuf_ohmpilotTemperature => undef,
    }), 'mixed diagnostic delta is accepted');
    is(reading_value($hash, 'diag_fbuf_pGrid'), '125.13',
        'changed numeric diagnostic waits for the interval');
    DevIo::run_due_timers(3_040);
    is(reading_value($hash, 'diag_fbuf_pGrid'), '222.22',
        'changed numeric diagnostic publishes rounded at the interval');
    is(reading_value($hash, 'diag_fbuf_pAcTotal'), 'raw-ac-value',
        'object diagnostic input preserves the previous scalar');
    is(reading_value($hash, 'diag_fbuf_ohmpilotState'), 1,
        'array diagnostic input preserves the previous scalar');
    is(reading_value($hash, 'diag_fbuf_ohmpilotTemperature'), 0,
        'null diagnostic input preserves the previous scalar');

    $hash->{helper}{idleRefreshAttempted} = 1;
    $DevIo::NOW = 3_069;
    ok(parse_status($hash, 'deltaStatus', {
        car => 1,
        fbuf_pGrid => 333.3333333,
    }), 'idle diagnostic value is cached');
    DevIo::run_due_timers(3_070);
    is(reading_value($hash, 'diag_fbuf_pGrid'), '222.22',
        'all diagnostics stay gated while idle');

    is(DevIo::command_attr($hash->{NAME}, 'update_while_idle', 1), undef,
        'idle publication is enabled');
    DevIo::run_due_timers(3_100);
    is(reading_value($hash, 'diag_fbuf_pGrid'), '333.33',
        'the latest cached diagnostic publishes rounded after the gate opens');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 0), undef,
        'diagnosticReadings accepts zero');
    for my $reading (@diag_readings) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading is deleted immediately");
    }
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'diagnostic cache and dirty state are deleted');
    DevIo::run_due_timers(3_130);
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'a pending shared timer does not recreate disabled diagnostic state');
    for my $reading (@diag_readings) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading stays absent after a pending shared timer");
    }

    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        fbuf_pGrid => 444,
    }), 'diagnostic input remains harmless while disabled');
    ok(!exists $hash->{READINGS}{diag_fbuf_pGrid},
        'disabled diagnostics are not recreated');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 1), undef,
        'diagnostics can be enabled again');
    $DevIo::NOW = 3_131;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        fbuf_pGrid => 555,
    }), 'diagnostic input is cached after re-enabling');
    DevIo::run_due_timers(3_160);
    is(reading_value($hash, 'diag_fbuf_pGrid'), '555.00',
        're-enabled numeric diagnostics publish with two decimals');
    is(DevIo::command_delete_attr($hash->{NAME}, 'diagnosticReadings'), undef,
        'deleting the attribute is accepted');
    ok(!exists $hash->{READINGS}{diag_fbuf_pGrid},
        'deleting the attribute removes diagnostic readings');
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'deleting the attribute clears diagnostic runtime state');

    like(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 2),
        qr/diagnosticReadings must be 0 or 1/,
        'other diagnosticReadings values are rejected');
};


subtest 'reload clears transient diagnostic cache while preserving enabled readings' => sub {
    my $hash = fresh_device('reloadEnabledDiagnostics');
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
    $hash->{READINGS}{diag_fbuf_pGrid} = { VAL => '12.34', TIME => 'old' };
    $hash->{helper}{telemetryPublication}{diagnostic} = {
        cache => { fbuf_pGrid => 12 },
        dirty => { fbuf_pGrid => 1 },
    };

    my $module_hash = {};
    main::Wattpilot_Initialize($module_hash);
    is(reading_value($hash, 'diag_fbuf_pGrid'), '12.34',
        'reload preserves an enabled diagnostic reading');
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'reload discards transient diagnostic cache state');

    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 1;
    ok(parse_status($hash, 'deltaStatus', {
        car => 2,
        fbuf_pGrid => 15,
    }), 'fresh diagnostic input repopulates the cache after reload');
    is(reading_value($hash, 'diag_fbuf_pGrid'), '15.00',
        'fresh post-reload numeric diagnostics use two-decimal formatting');
};

subtest 'reload removes stale diagnostics when the effective attribute is off' => sub {
    my $hash = fresh_device();
    $hash->{READINGS}{diag_fbuf_pGrid} = { VAL => 1, TIME => 'old' };
    $hash->{READINGS}{carState} = { VAL => 'idle', TIME => 'old' };
    $hash->{helper}{telemetryPublication}{diagnostic} = {
        cache => { fbuf_pGrid => 2 },
        dirty => { fbuf_pGrid => 1 },
    };
    $attr{$hash->{NAME}}{diagnosticReadings} = 0;

    my $module_hash = {};
    main::Wattpilot_Initialize($module_hash);
    ok(!exists $hash->{READINGS}{diag_fbuf_pGrid},
        'reload removes stale optional diagnostics when disabled');
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'reload removes stale diagnostic cache state');
    is(reading_value($hash, 'carState'), 'idle',
        'reload preserves unrelated readings');
    like($module_hash->{AttrList}, qr/\bdiagnosticReadings:0,1\b/,
        'the module advertises the boolean diagnostic attribute');
    like($module_hash->{AttrList}, qr/(?:^|\s)interval(?:\s|$)/,
        'interval is advertised as a free-value attribute');
    unlike($module_hash->{AttrList}, qr/interval:slider/,
        'interval no longer advertises a FHEMWEB slider');
};

done_testing;
