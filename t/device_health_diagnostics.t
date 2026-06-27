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

my @temperature_readings = map { "diag_temperatureSensor$_" } 1 .. 6;
my @controller_readings = qw(
    deviceControllerFirmwareVersion
    deviceControllerFirmwareCRC
    deviceControllerFirmwareIntegrity
    deviceControllerStackSize
    deviceControllerResetReason
    deviceControllerMidFirmwareVersion
    deviceControllerHardwareId
);

sub fresh_device {
    my ($name) = @_;
    $name //= 'healthDiagnosticsWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => $name,
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000091',
        DeviceName => 'ws:192.0.2.91:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$name} = $hash;
    return $hash;
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    my $message = { type => $type, status => $status };
    $message->{partial} = JSON::false() if $type eq 'fullStatus';
    return main::Wattpilot_Parse($hash, encode_json($message));
}

sub reading_value {
    my ($hash, $reading) = @_;
    return $hash->{READINGS}{$reading}{VAL};
}

sub controller_status {
    return {
        firmware_version => '0.0.17-8',
        firmware_crc => '0x5CC8',
        firmware_integrity => 'verified',
        stack_size => 15464,
        reset_reason => '|por|pin',
        mid_firmware_version => 'BDDF3FF',
        hwid => 'phnx-rts-rev6',
    };
}

subtest 'controller fields are ordinary interval-controlled device readings' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 1_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        cc4 => controller_status(),
    }), 'observed controller object is accepted while idle');

    is(reading_value($hash, 'deviceControllerFirmwareVersion'), '0.0.17-8',
        'controller firmware version is exposed');
    is(reading_value($hash, 'deviceControllerFirmwareCRC'), '0x5CC8',
        'controller firmware CRC is exposed');
    is(reading_value($hash, 'deviceControllerFirmwareIntegrity'), 'verified',
        'controller firmware integrity text is exposed without interpretation');
    is(reading_value($hash, 'deviceControllerStackSize'), 15464,
        'controller stack size is exposed as a non-negative integer');
    is(reading_value($hash, 'deviceControllerResetReason'), '|por|pin',
        'controller reset reason is exposed without token decoding');
    is(reading_value($hash, 'deviceControllerMidFirmwareVersion'), 'BDDF3FF',
        'controller MID firmware version is exposed');
    is(reading_value($hash, 'deviceControllerHardwareId'), 'phnx-rts-rev6',
        'controller hardware identifier is exposed');

    $DevIo::NOW = 1_029;
    ok(parse_status($hash, 'deltaStatus', {
        cc4 => {
            stack_size => 16000,
            firmware_integrity => 'changed',
        },
    }), 'partial controller update is cached');
    is(reading_value($hash, 'deviceControllerStackSize'), 15464,
        'controller update remains interval-controlled');
    DevIo::run_due_timers(1_030);
    is(reading_value($hash, 'deviceControllerStackSize'), 16000,
        'changed controller stack size publishes at the shared interval');
    is(reading_value($hash, 'deviceControllerFirmwareIntegrity'), 'changed',
        'changed controller string publishes at the shared interval');
    is(reading_value($hash, 'deviceControllerFirmwareVersion'), '0.0.17-8',
        'omitted controller members preserve their readings');

    $DevIo::NOW = 1_059;
    ok(parse_status($hash, 'deltaStatus', {
        cc4 => {
            firmware_version => undef,
            firmware_crc => [],
            firmware_integrity => {},
            stack_size => -1,
            reset_reason => JSON::true(),
            mid_firmware_version => 17,
            hwid => undef,
        },
    }), 'null and wrong-type controller fields are ignored');
    DevIo::run_due_timers(1_060);
    is(reading_value($hash, 'deviceControllerFirmwareVersion'), '0.0.17-8',
        'null firmware version preserves the previous reading');
    is(reading_value($hash, 'deviceControllerFirmwareCRC'), '0x5CC8',
        'array firmware CRC preserves the previous reading');
    is(reading_value($hash, 'deviceControllerFirmwareIntegrity'), 'changed',
        'object firmware integrity preserves the previous reading');
    is(reading_value($hash, 'deviceControllerStackSize'), 16000,
        'negative stack size preserves the previous reading');
    is(reading_value($hash, 'deviceControllerResetReason'), '|por|pin',
        'boolean reset reason preserves the previous reading');
    is(reading_value($hash, 'deviceControllerMidFirmwareVersion'), 'BDDF3FF',
        'numeric MID firmware version preserves the previous reading');
    is(reading_value($hash, 'deviceControllerHardwareId'), 'phnx-rts-rev6',
        'null hardware identifier preserves the previous reading');

    ok(parse_status($hash, 'deltaStatus', { cc4 => 'invalid-container' }),
        'wrong-shaped controller object is ignored');
    DevIo::run_due_timers(1_090);
    is(reading_value($hash, 'deviceControllerStackSize'), 16000,
        'wrong-shaped controller object cannot overwrite readings');

    ok(!exists $hash->{READINGS}{deviceHealth},
        'no derived controller-health verdict is invented');
};

subtest 'temperature array is optional diagnostic data with six generic positions' => sub {
    my $hash = fresh_device('temperatureDiagnosticsWallbox');
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;

    $DevIo::NOW = 2_000;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        tma => [undef, undef, 39.0, 41.0, 40, 38.5],
    }), 'temperature array is accepted while diagnostics are disabled');
    for my $reading (@temperature_readings) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading is absent while diagnosticReadings is disabled");
    }

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 1), undef,
        'temperature diagnostics can be enabled');
    $DevIo::NOW = 2_010;
    ok(parse_status($hash, 'fullStatus', {
        car => 1,
        tma => [undef, undef, 39.0, 41.0, 40, 38.5],
    }), 'observed six-position temperature array is accepted');
    ok(!exists $hash->{READINGS}{diag_temperatureSensor1},
        'null position one creates no reading');
    ok(!exists $hash->{READINGS}{diag_temperatureSensor2},
        'null position two creates no reading');
    is(reading_value($hash, 'diag_temperatureSensor3'), '39.00',
        'position three is formatted with two decimals');
    is(reading_value($hash, 'diag_temperatureSensor4'), '41.00',
        'position four is formatted with two decimals');
    is(reading_value($hash, 'diag_temperatureSensor5'), '40.00',
        'position five is formatted with two decimals');
    is(reading_value($hash, 'diag_temperatureSensor6'), '38.50',
        'position six is formatted with two decimals');

    $DevIo::NOW = 2_039;
    ok(parse_status($hash, 'deltaStatus', {
        tma => [12.345, 'invalid', undef, {}, 42.126, 37],
    }), 'mixed valid and invalid temperature positions are accepted field by field');
    DevIo::run_due_timers(2_040);
    is(reading_value($hash, 'diag_temperatureSensor1'), '12.35',
        'new numeric position one is published');
    ok(!exists $hash->{READINGS}{diag_temperatureSensor2},
        'invalid string position two creates no reading');
    is(reading_value($hash, 'diag_temperatureSensor3'), '39.00',
        'null position three preserves the previous reading');
    is(reading_value($hash, 'diag_temperatureSensor4'), '41.00',
        'object position four preserves the previous reading');
    is(reading_value($hash, 'diag_temperatureSensor5'), '42.13',
        'changed position five is rounded to two decimals');
    is(reading_value($hash, 'diag_temperatureSensor6'), '37.00',
        'integer position six is formatted with trailing zeroes');

    ok(parse_status($hash, 'deltaStatus', { tma => 'invalid-container' }),
        'wrong-shaped temperature container is ignored');
    DevIo::run_due_timers(2_070);
    is(reading_value($hash, 'diag_temperatureSensor5'), '42.13',
        'wrong-shaped temperature container preserves existing readings');

    is(DevIo::command_attr($hash->{NAME}, 'diagnosticReadings', 0), undef,
        'temperature diagnostics can be disabled');
    for my $reading (@temperature_readings) {
        ok(!exists $hash->{READINGS}{$reading},
            "$reading is removed immediately when diagnostics are disabled");
    }
    ok(!exists $hash->{helper}{telemetryPublication}{diagnostic},
        'disabling diagnostics clears temperature cache and dirty state');
    ok(!exists $hash->{READINGS}{deviceTemperatureMax},
        'no maximum-temperature reading is derived');
    ok(!exists $hash->{READINGS}{temperatureDerating},
        'no temperature-derating reading is derived');
};

subtest 'reading policies retain the requested categories and evidence limits' => sub {
    my $interface = main::Wattpilot_InterfaceSnapshot();
    my $policy = $interface->{readingPolicy};

    for my $key (qw(
        device_controller_firmware_version
        device_controller_firmware_crc
        device_controller_firmware_integrity
        device_controller_stack_size
        device_controller_reset_reason
        device_controller_mid_firmware_version
        device_controller_hardware_id
    )) {
        is($policy->{$key}{category}, 'device_health',
            "$key is a normal device-health reading");
        is($policy->{$key}{publication}, 'interval',
            "$key is interval-controlled");
        is($policy->{$key}{idleGate}, 'none',
            "$key remains available while idle");
        is($policy->{$key}{owner}, 'device_health',
            "$key shares the device-health telemetry owner");
    }

    for my $index (1 .. 6) {
        my $key = "diag_temperature_sensor_$index";
        is($policy->{$key}{category}, 'optional_diagnostic',
            "$key is optional diagnostic data");
        is($policy->{$key}{source}, 'status:tma[' . ($index - 1) . ']',
            "$key retains only its generic array position");
        is($policy->{$key}{formatter}, 'decimal2',
            "$key uses two-decimal physical-value formatting");
        is($policy->{$key}{validator}, 'number',
            "$key accepts only finite JSON numbers");
    }
};

done_testing;
