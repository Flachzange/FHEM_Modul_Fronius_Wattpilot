use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'architectureWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000035',
        DeviceName => 'ws:192.0.2.35:80/ws',
        STATE => 'disconnected',
        TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub stable_key {
    my ($hash, $suffix) = @_;
    return 'Wattpilot_' . $hash->{FUUID} . '_' . $suffix;
}

my $interface = main::Wattpilot_InterfaceSnapshot();
is_deeply(
    $interface->{commands},
    {
        password => 'password',
        force_state => 'forceState',
        charging_current => 'chargingCurrent',
        charging_mode => 'chargingMode',
        pv_surplus_start_power => 'pvSurplusStartPower',
        pv_surplus_enabled => 'pvSurplusEnabled',
        zero_feed_in_enabled => 'zeroFeedInEnabled',
        pv_control_preference => 'pvControlPreference',
        phase_switch => 'phaseSwitch',
        minimum_charging => 'minimumCharging',
        charging_pause_allowed => 'chargingPauseAllowed',
        reconnect => 'reconnect',
        reboot => 'reboot',
        pv_battery => 'pvBattery',
        next_trip_time => 'nextTripTime',
    },
    '2.0 public Set command names have one central definition');
is(scalar(keys %{$interface->{readings}}), 88,
    'central reading definition contains all 88 public readings');
is_deeply(
    $interface->{readings},
    {
        state => 'state',
        connection_last_reconnect_reason => 'connectionLastReconnectReason',
        connection_automatic_reconnect_count => 'connectionAutomaticReconnectCount',
        firmware_version => 'deviceFirmwareVersion',
        device_type => 'deviceType',
        device_model => 'deviceModel',
        device_sub_type => 'deviceSubType',
        device_variant => 'deviceVariant',
        hello_protocol => 'deviceHelloProtocol',
        status_protocol => 'deviceStatusProtocol',
        auth_hash_mode => 'authHashMode',
        car_state => 'carState',
        force_state => 'configForceState',
        charging_current => 'configChargingCurrent',
        charging_mode => 'configChargingMode',
        charging_allowed => 'chargingAllowed',
        charging_decision_code => 'chargingDecisionCode',
        charging_decision => 'chargingDecision',
        charging_decision_internal_code => 'chargingDecisionInternalCode',
        charging_decision_internal => 'chargingDecisionInternal',
        error_code => 'errorCode',
        maximum_current_limit => 'configMaximumCurrentLimit',
        temperature_current_limit => 'temperatureCurrentLimit',
        minimum_charging_current => 'configMinimumChargingCurrent',
        pv_surplus_start_power => 'configPvSurplusStartPower',
        pv_surplus_enabled => 'configPvSurplusEnabled',
        zero_feed_in_enabled => 'configZeroFeedInEnabled',
        pv_control_preference => 'configPvControlPreference',
        phase_switch_mode => 'configPhaseSwitchMode',
        three_phase_switch_power => 'configThreePhaseSwitchPower',
        phase_switch_delay => 'configPhaseSwitchDelay',
        minimum_phase_switch_interval => 'configMinimumPhaseSwitchInterval',
        minimum_charge_time => 'configMinimumChargeTime',
        charging_pause_allowed => 'configChargingPauseAllowed',
        minimum_charging_pause_duration => 'configMinimumChargingPauseDuration',
        minimum_charging_interval => 'configMinimumChargingInterval',
        diag_fbuf_akku_soc => 'diag_fbuf_akkuSOC',
        diag_fbuf_p_akku => 'diag_fbuf_pAkku',
        diag_fbuf_akku_mode => 'diag_fbuf_akkuMode',
        device_reboot_count => 'deviceRebootCount',
        device_uptime => 'uptime',
        device_controller_firmware_version => 'deviceControllerFirmwareVersion',
        device_controller_firmware_crc => 'deviceControllerFirmwareCRC',
        device_controller_firmware_integrity => 'deviceControllerFirmwareIntegrity',
        device_controller_stack_size => 'deviceControllerStackSize',
        device_controller_reset_reason => 'deviceControllerResetReason',
        device_controller_mid_firmware_version => 'deviceControllerMidFirmwareVersion',
        device_controller_hardware_id => 'deviceControllerHardwareId',
        diag_temperature_sensor_1 => 'diag_temperatureSensor1',
        diag_temperature_sensor_2 => 'diag_temperatureSensor2',
        diag_temperature_sensor_3 => 'diag_temperatureSensor3',
        diag_temperature_sensor_4 => 'diag_temperatureSensor4',
        diag_temperature_sensor_5 => 'diag_temperatureSensor5',
        diag_temperature_sensor_6 => 'diag_temperatureSensor6',
        diag_fbuf_p_grid => 'diag_fbuf_pGrid',
        diag_fbuf_p_pv => 'diag_fbuf_pPv',
        diag_pvopt_average_p_grid => 'diag_pvopt_averagePGrid',
        diag_pvopt_average_p_pv => 'diag_pvopt_averagePPv',
        diag_pvopt_average_p_akku => 'diag_pvopt_averagePAkku',
        diag_pvopt_average_p_ohmpilot => 'diag_pvopt_averagePOhmpilot',
        diag_pvopt_delta_p => 'diag_pvopt_deltaP',
        diag_pvopt_delta_a => 'diag_pvopt_deltaA',
        diag_pvopt_special_case => 'diag_pvopt_specialCase',
        diag_fbuf_p_ac_total => 'diag_fbuf_pAcTotal',
        diag_fbuf_ohmpilot_state => 'diag_fbuf_ohmpilotState',
        diag_fbuf_ohmpilot_temperature => 'diag_fbuf_ohmpilotTemperature',
        pv_battery_charge_above_soc => 'configPvBatteryChargeAboveSoC',
        pv_battery_discharge_enabled => 'configPvBatteryDischargeEnabled',
        pv_battery_discharge_until_soc => 'configPvBatteryDischargeUntilSoC',
        pv_battery_discharge_time_limit_enabled => 'configPvBatteryDischargeTimeLimitEnabled',
        pv_battery_discharge_start_time => 'configPvBatteryDischargeStartTime',
        pv_battery_discharge_stop_time => 'configPvBatteryDischargeStopTime',
        next_trip_time => 'configNextTripTime',
        energy_total => 'energyTotal',
        energy_since_plug_in => 'energySincePlugIn',
        voltage_l1 => 'voltageL1',
        voltage_l2 => 'voltageL2',
        voltage_l3 => 'voltageL3',
        current_l1 => 'currentL1',
        current_l2 => 'currentL2',
        current_l3 => 'currentL3',
        power_l1 => 'powerL1',
        power_l2 => 'powerL2',
        power_l3 => 'powerL3',
        power => 'power',
        last_command_request_id => 'lastCommandRequestId',
        last_command_status => 'lastCommandStatus',
        last_command_error => 'lastCommandError',
    },
    'all 88 public reading names match the 2.x contract');
is_deeply(
    $interface->{readingCategories},
    {
        state => 'lifecycle',
        connection_last_reconnect_reason => 'lifecycle',
        connection_automatic_reconnect_count => 'lifecycle',
        firmware_version => 'identity',
        device_type => 'identity',
        device_model => 'identity',
        device_sub_type => 'identity',
        device_variant => 'identity',
        hello_protocol => 'identity',
        status_protocol => 'identity',
        auth_hash_mode => 'diagnostic',
        car_state => 'status',
        force_state => 'configuration',
        charging_current => 'configuration',
        charging_mode => 'configuration',
        charging_allowed => 'status',
        charging_decision_code => 'diagnostic',
        charging_decision => 'diagnostic',
        charging_decision_internal_code => 'diagnostic',
        charging_decision_internal => 'diagnostic',
        error_code => 'diagnostic',
        maximum_current_limit => 'configuration',
        temperature_current_limit => 'status',
        minimum_charging_current => 'configuration',
        pv_surplus_start_power => 'configuration',
        pv_surplus_enabled => 'configuration',
        zero_feed_in_enabled => 'configuration',
        pv_control_preference => 'configuration',
        phase_switch_mode => 'configuration',
        three_phase_switch_power => 'configuration',
        phase_switch_delay => 'configuration',
        minimum_phase_switch_interval => 'configuration',
        minimum_charge_time => 'configuration',
        charging_pause_allowed => 'configuration',
        minimum_charging_pause_duration => 'configuration',
        minimum_charging_interval => 'configuration',
        diag_fbuf_akku_soc => 'optional_diagnostic',
        diag_fbuf_p_akku => 'optional_diagnostic',
        diag_fbuf_akku_mode => 'optional_diagnostic',
        device_reboot_count => 'device_health',
        device_uptime => 'device_health',
        device_controller_firmware_version => 'device_health',
        device_controller_firmware_crc => 'device_health',
        device_controller_firmware_integrity => 'device_health',
        device_controller_stack_size => 'device_health',
        device_controller_reset_reason => 'device_health',
        device_controller_mid_firmware_version => 'device_health',
        device_controller_hardware_id => 'device_health',
        diag_temperature_sensor_1 => 'optional_diagnostic',
        diag_temperature_sensor_2 => 'optional_diagnostic',
        diag_temperature_sensor_3 => 'optional_diagnostic',
        diag_temperature_sensor_4 => 'optional_diagnostic',
        diag_temperature_sensor_5 => 'optional_diagnostic',
        diag_temperature_sensor_6 => 'optional_diagnostic',
        diag_fbuf_p_grid => 'optional_diagnostic',
        diag_fbuf_p_pv => 'optional_diagnostic',
        diag_pvopt_average_p_grid => 'optional_diagnostic',
        diag_pvopt_average_p_pv => 'optional_diagnostic',
        diag_pvopt_average_p_akku => 'optional_diagnostic',
        diag_pvopt_average_p_ohmpilot => 'optional_diagnostic',
        diag_pvopt_delta_p => 'optional_diagnostic',
        diag_pvopt_delta_a => 'optional_diagnostic',
        diag_pvopt_special_case => 'optional_diagnostic',
        diag_fbuf_p_ac_total => 'optional_diagnostic',
        diag_fbuf_ohmpilot_state => 'optional_diagnostic',
        diag_fbuf_ohmpilot_temperature => 'optional_diagnostic',
        pv_battery_charge_above_soc => 'configuration',
        pv_battery_discharge_enabled => 'configuration',
        pv_battery_discharge_until_soc => 'configuration',
        pv_battery_discharge_time_limit_enabled => 'configuration',
        pv_battery_discharge_start_time => 'configuration',
        pv_battery_discharge_stop_time => 'configuration',
        next_trip_time => 'configuration',
        energy_total => 'telemetry',
        energy_since_plug_in => 'telemetry',
        voltage_l1 => 'telemetry',
        voltage_l2 => 'telemetry',
        voltage_l3 => 'telemetry',
        current_l1 => 'telemetry',
        current_l2 => 'telemetry',
        current_l3 => 'telemetry',
        power_l1 => 'telemetry',
        power_l2 => 'telemetry',
        power_l3 => 'telemetry',
        power => 'telemetry',
        last_command_request_id => 'command_diagnostic',
        last_command_status => 'command_diagnostic',
        last_command_error => 'command_diagnostic',
    },
    'every public reading has one explicit category');
for my $key (sort keys %{$interface->{readings}}) {
    my $name = $interface->{readings}{$key};
    my $category = $interface->{readingCategories}{$key};
    if ($category eq 'configuration') {
        like($name, qr/^config[A-Z]/,
            "$name uses the mandatory configuration prefix");
    }
    else {
        unlike($name, qr/^config[A-Z]/,
            "$name is not accidentally classified as configuration");
    }
}
my $category_doc_path = File::Spec->catfile(
    $root, 'docs', 'READING-CATEGORIES.md');
open my $category_doc_fh, '<:encoding(UTF-8)', $category_doc_path
    or die "Cannot read $category_doc_path: $!";
my $category_doc = do { local $/; <$category_doc_fh> };
close $category_doc_fh;
for my $key (sort keys %{$interface->{readings}}) {
    my $name = $interface->{readings}{$key};
    my $category = $interface->{readingCategories}{$key};
    like(
        $category_doc,
        qr/^\| `\Q$key\E` \| `\Q$name\E` \| `\Q$category\E` \|/m,
        "reading-category audit documents $key as $name/$category");
}
is($interface->{readings}{car_state}, 'carState',
    'central reading definition exposes the 2.0 car-state name');
is_deeply($interface->{carStates},
    { 0 => 'unknown', 1 => 'idle', 2 => 'charging', 3 => 'waitingForCar', 4 => 'complete', 5 => 'error' },
    'central car-state labels expose the 2.0 contract');
is_deeply($interface->{forceStates},
    { 0 => 'neutral', 1 => 'off', 2 => 'on' },
    'central force-state labels expose the 2.0 contract');
is_deeply($interface->{chargingModes},
    { 3 => 'default', 4 => 'eco', 5 => 'nextTrip' },
    'central charging-mode labels expose the 2.0 contract');
is_deeply($interface->{pvControlPreferences},
    { 0 => 'preferFromGrid', 1 => 'default', 2 => 'preferToGrid' },
    'central PV-control-preference labels expose the public contract');
is_deeply($interface->{phaseSwitchModes},
    { 0 => 'auto', 1 => 'force1', 2 => 'force3' },
    'central phase-switch labels expose the public contract');
is_deeply($interface->{chargingDecisions},
    {
        0 => 'notChargingBecauseNoChargeCtrlData',
        1 => 'notChargingBecauseOvertemperature',
        2 => 'notChargingBecauseAccessControlWait',
        3 => 'chargingBecauseForceStateOn',
        4 => 'notChargingBecauseForceStateOff',
        5 => 'notChargingBecauseScheduler',
        6 => 'notChargingBecauseEnergyLimit',
        7 => 'chargingBecauseAwattarPriceLow',
        8 => 'chargingBecauseAutomaticStopTestLadung',
        9 => 'chargingBecauseAutomaticStopNotEnoughTime',
        10 => 'chargingBecauseAutomaticStop',
        11 => 'chargingBecauseAutomaticStopNoClock',
        12 => 'chargingBecausePvSurplus',
        13 => 'chargingBecauseFallbackGoEDefault',
        14 => 'chargingBecauseFallbackGoEScheduler',
        15 => 'chargingBecauseFallbackDefault',
        16 => 'notChargingBecauseFallbackGoEAwattar',
        17 => 'notChargingBecauseFallbackAwattar',
        18 => 'notChargingBecauseFallbackAutomaticStop',
        19 => 'chargingBecauseCarCompatibilityKeepAlive',
        20 => 'chargingBecauseChargePauseNotAllowed',
        22 => 'notChargingBecauseSimulateUnplugging',
        23 => 'notChargingBecausePhaseSwitch',
        24 => 'notChargingBecauseMinPauseDuration',
        26 => 'notChargingBecauseError',
        27 => 'notChargingBecauseLoadManagementDoesntWant',
        28 => 'notChargingBecauseOcppDoesntWant',
        29 => 'notChargingBecauseReconnectDelay',
        30 => 'notChargingBecauseAdapterBlocking',
        31 => 'notChargingBecauseUnderfrequencyControl',
        32 => 'notChargingBecauseUnbalancedLoad',
        33 => 'chargingBecauseDischargingPvBattery',
        34 => 'notChargingBecauseGridMonitoring',
        35 => 'notChargingBecauseOcppFallback',
    },
    'central charging-decision labels expose the compatibility mapping');
is($interface->{lifecycle}{credential_error}, 'credentialError',
    'central lifecycle definition exposes the 2.0 credential error value');
is_deeply(
    $interface->{lifecycle},
    {
        disabled => 'disabled',
        credential_error => 'credentialError',
        password_missing => 'passwordMissing',
        disconnected => 'disconnected',
        connecting => 'connecting',
        connection_failed => 'connectionFailed',
        authenticating => 'authenticating',
        initializing => 'initializing',
        connected => 'connected',
        rebooting => 'rebooting',
        auth_failed => 'authFailed',
        auth_timeout => 'authTimeout',
        initialization_timeout => 'initializationTimeout',
        auth_sequence_invalid => 'authSequenceInvalid',
        auth_config_missing => 'authConfigMissing',
        auth_challenge_invalid => 'authChallengeInvalid',
        auth_hash_unsupported => 'authHashUnsupported',
        auth_hash_failed => 'authHashFailed',
        auth_hash_store_failed => 'authHashStoreFailed',
        auth_nonce_failed => 'authNonceFailed',
    },
    'all lifecycle values match the 2.0 lowerCamelCase contract');

my $normalizer_hash = fresh_device();
my $original_status = {
    amp => 'invalid',
    car => 2,
    customField => { preserved => 1 },
};
my $normalized_status = main::Wattpilot_NormalizeStatus(
    $normalizer_hash, $original_status);
ok(exists $original_status->{amp},
    'status normalization does not mutate the caller input');
ok(!exists $normalized_status->{amp},
    'status normalization removes an invalid known field from its copy');
is($normalized_status->{car}, 2,
    'status normalization preserves a valid known field');
is_deeply($normalized_status->{customField}, { preserved => 1 },
    'status normalization preserves unknown fields');

my $hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, {
    car => 2,
    frc => 0,
    ftt => 7 * 3600 + 30 * 60,
    amp => 16,
    lmo => 4,
    alw => 0,
    modelStatus => 23,
    msi => 27,
    err => 0,
    ama => 32,
    amt => 31,
    mca => 6,
    fst => 1400,
    fup => JSON::true(),
    fzf => JSON::false(),
    frm => 0,
    psm => 0,
    spl3 => 5200,
    mpwst => 120000,
    mptwt => 600000,
    fmt => 300000,
    fap => JSON::true(),
    mcpd => 120000,
    mci => 0,
    eto => 123456,
    wh => 789,
    nrg => [230, 231, 232, 0, 1.1, 2.2, 3.3, 100, 200, 300, 0, 600],
});

my %expected_reading = (
    carState => 'charging',
    configForceState => 'neutral',
    configNextTripTime => '07:30',
    configChargingCurrent => 16,
    configChargingMode => 'eco',
    chargingAllowed => 0,
    chargingDecisionCode => 23,
    chargingDecision => 'notChargingBecausePhaseSwitch',
    chargingDecisionInternalCode => 27,
    chargingDecisionInternal => 'notChargingBecauseLoadManagementDoesntWant',
    errorCode => 0,
    configMaximumCurrentLimit => 32,
    temperatureCurrentLimit => 31,
    configMinimumChargingCurrent => 6,
    configPvSurplusStartPower => '1400.00',
    configPvSurplusEnabled => 1,
    configZeroFeedInEnabled => 0,
    configPvControlPreference => 'preferFromGrid',
    configPhaseSwitchMode => 'auto',
    configThreePhaseSwitchPower => '5200.00',
    configPhaseSwitchDelay => 120,
    configMinimumPhaseSwitchInterval => 600,
    configMinimumChargeTime => 300,
    configChargingPauseAllowed => 1,
    configMinimumChargingPauseDuration => 120,
    configMinimumChargingInterval => 0,
    energyTotal => '123.46',
    energySincePlugIn => '789.00',
    voltageL1 => '230.00',
    voltageL2 => '231.00',
    voltageL3 => '232.00',
    currentL1 => '1.10',
    currentL2 => '2.20',
    currentL3 => '3.30',
    powerL1 => '100.00',
    powerL2 => '200.00',
    powerL3 => '300.00',
    power => '600.00',
);
for my $reading (sort keys %expected_reading) {
    is($hash->{READINGS}{$reading}{VAL}, $expected_reading{$reading},
        "2.0 reading contract is exposed for $reading");
}

$hash = fresh_device();
my $password_key = stable_key($hash, 'password');
my $hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'stored-password';
$DevIo::KEY_VALUES{$hash_key} = 'stored-hash';
is_deeply(main::Wattpilot_GetPassword($hash),
    { status => 'value', value => 'stored-password' },
    'stable password getter returns an explicit value result');
is_deeply(main::Wattpilot_GetPasswordHash($hash),
    { status => 'value', value => 'stored-hash' },
    'stable hash getter returns an explicit value result');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
is_deeply(main::Wattpilot_GetPassword($hash), { status => 'absent' },
    'missing stable password remains distinguishable from storage failure');
$DevIo::GET_KEY_ERRORS{$password_key} = 'synthetic read failure';
is(main::Wattpilot_GetPassword($hash)->{status}, 'error',
    'stable password storage failure remains explicit');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'old-password';
$DevIo::KEY_VALUES{$hash_key} = 'old-hash';
is(main::Wattpilot_StoreNewPassword($hash, 'new-password'), undef,
    'password replacement succeeds transactionally');
is($DevIo::KEY_VALUES{$password_key}, 'new-password',
    'password replacement stores the new stable password');
ok(!exists $DevIo::KEY_VALUES{$hash_key},
    'password replacement invalidates the stable derived hash');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'old-password';
$DevIo::KEY_VALUES{$hash_key} = 'old-hash';
$DevIo::SET_KEY_ERRORS{$password_key} = 'synthetic write failure';
like(main::Wattpilot_StoreNewPassword($hash, 'new-password'), qr/previous credentials restored/,
    'failed password write reports transactional restoration');
is($DevIo::KEY_VALUES{$password_key}, 'old-password',
    'failed password write preserves the old stable password');
is($DevIo::KEY_VALUES{$hash_key}, 'old-hash',
    'failed password write restores the old stable hash');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'stored-password';
$DevIo::KEY_VALUES{$hash_key} = 'stored-hash';
$DevIo::SET_KEY_ERRORS{$hash_key} = 'synthetic second delete failure';
like(main::Wattpilot_DeleteStoredSecrets($hash), qr/prior values restored/,
    'second stable-key delete failure reports rollback');
is($DevIo::KEY_VALUES{$password_key}, 'stored-password',
    'delete rollback restores the first stable key');
is($DevIo::KEY_VALUES{$hash_key}, 'stored-hash',
    'delete failure leaves the second stable key intact');

done_testing;
