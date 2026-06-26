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
    my ($name) = @_;
    $name //= 'batteryDiagnosticWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => $name,
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000049',
        DeviceName => 'ws:192.0.2.49:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$name} = $hash;
    return $hash;
}

sub nrg {
    my ($power) = @_;
    return [230, 231, 232, 0, 1, 1, 1, 230, 231, 232, 0, $power];
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    my $message = { type => $type, status => $status };
    $message->{partial} = JSON::false() if $type eq 'fullStatus';
    return main::Wattpilot_Parse($hash, encode_json($message));
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

sub reading_time {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{TIME};
}

subtest 'stationary battery mode, SOC, and power are optional raw diagnostics' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 100;

    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 60.1234567,
        fbuf_pAkku => -1525.9876543,
        fbuf_akkuMode => 1,
    }), 'battery fields are accepted while diagnostics are disabled');
    ok(!exists $hash->{READINGS}{diag_fbuf_akkuMode},
        'battery mode diagnostic is absent by default');
    ok(!exists $hash->{READINGS}{diag_fbuf_akkuSOC},
        'battery SOC diagnostic is absent by default');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'battery power diagnostic is absent by default');
    ok(!exists $hash->{READINGS}{pvBatteryModeCode},
        'the former normal battery mode reading is not emitted');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 1), undef,
        'raw diagnostics can be enabled');
    $DevIo::NOW = 101;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuMode => 1,
        fbuf_akkuSOC => 60.1234567,
        fbuf_pAkku => -1525.9876543,
    }), 'battery diagnostics are accepted after enabling');
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'mode is exposed as an uninterpreted rounded diagnostic number');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '60.12',
        'SOC is rounded to two decimals without percentage validation');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-1525.99',
        'power is rounded without unit or sign interpretation');

    # BEGIN 2.0 negative controls for removed public names
    ok(!exists $hash->{READINGS}{pvBatterySoC},
        'removed pvBatterySoC reading is not emitted');
    ok(!exists $hash->{READINGS}{pvBatteryPower},
        'removed pvBatteryPower reading is not emitted');
    # END 2.0 negative controls for removed public names
};

subtest 'diagnostic scalar rules round numbers and preserve other scalar kinds' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 1;
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
    $DevIo::NOW = 200;

    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 55.25,
        fbuf_pAkku => -500.125,
    }), 'numeric baseline is accepted');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '55.25',
        'two-decimal numeric SOC remains unchanged');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-500.12',
        'numeric power is rounded to two decimals');

    $DevIo::NOW = 201;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 'field-research-text',
        fbuf_pAkku => JSON::true(),
    }), 'string and boolean diagnostics are accepted');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), 'field-research-text',
        'diagnostic strings are copied unchanged');
    is(reading_value($hash, 'diag_fbuf_pAkku'), 1,
        'diagnostic booleans are normalized to zero or one');

    $DevIo::NOW = 202;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => [60],
        fbuf_pAkku => { watts => -1200 },
    }), 'array and object diagnostics are ignored safely');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), 'field-research-text',
        'array input preserves the previous scalar');
    is(reading_value($hash, 'diag_fbuf_pAkku'), 1,
        'object input preserves the previous scalar');

    $DevIo::NOW = 203;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => undef,
        fbuf_pAkku => undef,
    }), 'null diagnostics are ignored safely');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), 'field-research-text',
        'null SOC preserves the previous scalar');
    is(reading_value($hash, 'diag_fbuf_pAkku'), 1,
        'null power preserves the previous scalar');
};

subtest 'battery diagnostics share the common interval without cross-publication' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
    $DevIo::NOW = 1_000;

    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 1,
        nrg => nrg(500),
    }), 'combined baseline starts the shared telemetry clock');
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'initial battery mode diagnostic is published with two decimals');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-500.00',
        'initial numeric battery diagnostic is published with two decimals');
    is(reading_value($hash, 'power'), '500.00',
        'initial electrical telemetry is published normally');
    is(reading_time($hash, 'power'), reading_time($hash, 'diag_fbuf_pAkku'),
        'electrical and diagnostic owners share one transaction timestamp');

    $DevIo::NOW = 1_029;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 49.1234,
        fbuf_pAkku => -700.5678,
        fbuf_akkuMode => 2,
    }), 'battery-only input is cached before the common tick');
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'changed battery mode waits for the common diagnostic tick');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-500.00',
        'diagnostic power waits for the common tick');

    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(700) }),
        'fresh nrg in the same cycle is cached independently');
    DevIo::run_due_timers(1_030);
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '2.00',
        'latest raw mode publishes on the common tick');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '49.12',
        'latest raw SOC publishes on the common tick');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-700.57',
        'latest raw battery power publishes on the common tick');
    is(reading_value($hash, 'power'), '700.00',
        'fresh nrg publishes on the same common tick');
};

subtest 'idle gate and diagnostic removal apply to battery diagnostics' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
    $DevIo::NOW = 2_000;

    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        fbuf_akkuSOC => 40,
        fbuf_pAkku => 250.126,
        fbuf_akkuMode => 1,
    }), 'idle battery diagnostics are cached');
    ok(!exists $hash->{READINGS}{diag_fbuf_akkuMode},
        'battery mode diagnostic remains passive while idle');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'battery diagnostics remain passive while idle');

    is(DevIo::command_attr($hash->{NAME}, 'update_while_idle', 1), undef,
        'idle publication can be enabled');
    DevIo::run_due_timers(2_030);
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'cached mode publishes after opening the idle gate');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '40.00',
        'cached SOC publishes after opening the idle gate');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '250.13',
        'cached power publishes rounded to two decimals');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 0), undef,
        'diagnostics can be disabled');
    ok(!exists $hash->{READINGS}{diag_fbuf_akkuMode},
        'battery mode diagnostic is deleted immediately');
    ok(!exists $hash->{READINGS}{diag_fbuf_akkuSOC},
        'battery SOC diagnostic is deleted immediately');
    ok(!exists $hash->{READINGS}{diag_fbuf_pAkku},
        'battery power diagnostic is deleted immediately');
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'the shared diagnostic cache is cleared');
};

subtest 'matched response status follows the same diagnostic contract' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;
    $attr{$hash->{NAME}}{diagnosticReadings} = 1;
    $DevIo::NOW = 3_000;

    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fbuf_akkuMode => 1,
        fbuf_akkuSOC => 60,
        fbuf_pAkku => -600,
        nrg => nrg(600),
    }), 'baseline is accepted');

    $hash->{helper}{pendingRequests}{49} = {
        key => 'syntheticBatteryReadback', sentAt => 3_005,
    };
    $DevIo::NOW = 3_005;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => 49,
        success => JSON::true(),
        status => {
            fbuf_akkuSOC => 61.75,
            fbuf_pAkku => -1200.875,
            fbuf_akkuMode => 2,
        },
    })), 'successful matched response is accepted');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-600.00',
        'response diagnostic remains cached before the tick');
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '1.00',
        'response mode change remains cached before the tick');

    DevIo::run_due_timers(3_030);
    is(reading_value($hash, 'diag_fbuf_akkuMode'), '2.00',
        'response mode becomes visible at the tick');
    is(reading_value($hash, 'diag_fbuf_akkuSOC'), '61.75',
        'response SOC becomes visible at the tick');
    is(reading_value($hash, 'diag_fbuf_pAkku'), '-1200.88',
        'response power becomes visible at the tick');
};

my $interface = main::Wattpilot_InterfaceSnapshot();
is($interface->{readings}{diag_fbuf_akku_mode}, 'diag_fbuf_akkuMode',
    'public interface exposes the raw optional battery mode diagnostic');
is($interface->{readings}{diag_fbuf_akku_soc}, 'diag_fbuf_akkuSOC',
    'public interface exposes the raw optional battery SOC diagnostic');
is($interface->{readings}{diag_fbuf_p_akku}, 'diag_fbuf_pAkku',
    'public interface exposes the raw optional battery power diagnostic');
ok(!exists $interface->{readings}{pv_battery_mode_code},
    'public interface removes the former normal battery mode reading');

my $hash = fresh_device();
my $help = main::Wattpilot_Set($hash, 'batteryDiagnosticWallbox', '?');
unlike($help, qr/diag_fbuf_(?:akkuSOC|pAkku)/,
    'raw diagnostics do not invent setters');

done_testing;
