##############################################
#
# Steuerung für Fronius Wattpilot Wallbox via WebSocket API V2
#
# (c) 2026 Dennis Gramespacher
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# The GNU General Public License can be found at http://www.gnu.org/copyleft/gpl.html.
# A copy of the license is distributed with this module as LICENSE.
#
# Original author: Dennis Gramespacher
# Author of the version 2.x redesign and implementation: Flachzange
# AI-assisted development support: OpenAI ChatGPT
# Technical decisions and release responsibility: Flachzange
#
# Protocol-source provenance and confidence boundaries are maintained in
# docs/PROTOCOL-SOURCES.md.
##############################################

package main;

use strict;
use warnings;
use bytes ();
use B qw(
    svref_2object
    SVf_POK SVp_POK
    SVf_IOK SVp_IOK
    SVf_NOK SVp_NOK
);
use DevIo;
use FHEM::Meta;
use JSON;
use Digest::SHA qw(sha256_hex);
use Crypt::PBKDF2;
use Crypt::URandom qw(urandom);

my $WATTPILOT_VERSION = '2.1.7';
my $WATTPILOT_REQUEST_TIMEOUT = 30;
my $WATTPILOT_AUTH_TIMEOUT = 30;
my $WATTPILOT_INITIALIZATION_TIMEOUT = 30;
my $WATTPILOT_TIMEOUT_RETRY_DELAY = 5;
my $WATTPILOT_IDLE_REFRESH_TIMEOUT = 30;
my $WATTPILOT_MAX_PENDING_REQUESTS = 32;
my $WATTPILOT_MAX_JSON_BYTES = 1024 * 1024;
my $WATTPILOT_MAX_JSON_DOCUMENTS = 256;
my $WATTPILOT_CHARGING_CURRENT_MINIMUM = 6;
my $WATTPILOT_CHARGING_CURRENT_MAXIMUM = 32;
# key, public name, category, source, publication, idle gate, owner,
# formatter, incoming validator, formatter detail
my @WATTPILOT_READING_DEFINITION = (
    [qw(state state lifecycle event:connection immediate none connection lifecycle none none)],
    [qw(firmware_version firmwareVersion identity event:hello immediate-on-change none identity text none none)],
    [qw(device_type deviceType identity status:typ immediate-on-change none typ text nonempty_string none)],
    [qw(device_model deviceModel identity status:grp immediate-on-change none grp text nonempty_string none)],
    [qw(device_sub_type deviceSubType identity status:styp immediate-on-change none styp text nonempty_string none)],
    [qw(device_variant deviceVariant identity status:var immediate-on-change none var integer nonnegative_integer none)],
    [qw(hello_protocol helloProtocol identity event:hello immediate-on-change none hello_protocol integer none none)],
    [qw(status_protocol statusProtocol identity status:proto immediate-on-change none proto integer nonnegative_integer none)],
    [qw(auth_hash_mode authHashMode diagnostic event:authentication immediate none authentication enum none none)],
    [qw(car_state carState status status:car immediate-on-change none car enum integer car)],
    [qw(force_state configForceState configuration status:frc immediate none frc enum integer force)],
    [qw(next_trip_time configNextTripTime configuration
            status:ftt immediate none ftt clock clock_seconds strict)],
    [qw(charging_current configChargingCurrent configuration status:amp immediate none amp integer integer none)],
    [qw(charging_mode configChargingMode configuration status:lmo immediate none lmo enum integer charging_mode)],
    [qw(charging_allowed chargingAllowed status status:alw immediate-on-change none alw boolean boolean none)],
    [qw(charging_decision_code chargingDecisionCode diagnostic
            status:modelStatus immediate-on-change none modelStatus integer integer none)],
    [qw(charging_decision chargingDecision diagnostic
            status:modelStatus immediate-on-change none modelStatus enum integer charging_decision)],
    [qw(charging_decision_internal_code chargingDecisionInternalCode diagnostic
            status:msi immediate-on-change none msi integer integer none)],
    [qw(charging_decision_internal chargingDecisionInternal diagnostic
            status:msi immediate-on-change none msi enum integer charging_decision)],
    [qw(pv_surplus_start_power configPvSurplusStartPower configuration
            status:fst immediate none fst decimal2 nonnegative_number none)],
    [qw(pv_surplus_enabled configPvSurplusEnabled configuration
            status:fup immediate none fup boolean boolean none)],
    [qw(zero_feed_in_enabled configZeroFeedInEnabled configuration
            status:fzf immediate none fzf boolean boolean none)],
    [qw(charging_pause_allowed configChargingPauseAllowed configuration
            status:fap immediate none fap boolean boolean none)],
    [qw(pv_battery_discharge_enabled configPvBatteryDischargeEnabled configuration
            status:pdte immediate none pdte boolean boolean none)],
    [qw(pv_battery_discharge_time_limit_enabled configPvBatteryDischargeTimeLimitEnabled configuration
            status:pdle immediate none pdle boolean boolean none)],
    [qw(pv_battery_charge_above_soc configPvBatteryChargeAboveSoC configuration
            status:fam immediate none fam percentage percentage none)],
    [qw(pv_battery_discharge_until_soc configPvBatteryDischargeUntilSoC configuration
            status:pdt immediate none pdt percentage percentage none)],
    [qw(pv_battery_discharge_start_time configPvBatteryDischargeStartTime configuration
            status:pdls immediate none pdls clock clock_seconds strict)],
    [qw(pv_battery_discharge_stop_time configPvBatteryDischargeStopTime configuration
            status:pdlo immediate none pdlo clock clock_seconds end_of_day)],
    [qw(pv_control_preference configPvControlPreference configuration
            status:frm immediate none frm enum integer pv_control)],
    [qw(phase_switch_mode configPhaseSwitchMode configuration
            status:psm immediate none psm enum integer phase_switch)],
    [qw(three_phase_switch_power configThreePhaseSwitchPower configuration
            status:spl3 immediate none spl3 decimal2 nonnegative_number none)],
    [qw(phase_switch_delay configPhaseSwitchDelay configuration
            status:mpwst immediate none mpwst seconds nonnegative_number none)],
    [qw(minimum_phase_switch_interval configMinimumPhaseSwitchInterval configuration
            status:mptwt immediate none mptwt seconds nonnegative_number none)],
    [qw(minimum_charge_time configMinimumChargeTime configuration
            status:fmt immediate none fmt seconds nonnegative_number none)],
    [qw(minimum_charging_pause_duration configMinimumChargingPauseDuration configuration
            status:mcpd immediate none mcpd seconds nonnegative_number none)],
    [qw(minimum_charging_interval configMinimumChargingInterval configuration
            status:mci immediate none mci seconds nonnegative_number none)],
    [qw(error_code errorCode diagnostic status:err immediate-on-change none err integer integer none)],
    [qw(maximum_current_limit configMaximumCurrentLimit configuration
            status:ama immediate none ama integer integer none)],
    [qw(temperature_current_limit temperatureCurrentLimit status
            status:amt immediate-on-change none amt integer integer none)],
    [qw(minimum_charging_current configMinimumChargingCurrent configuration
            status:mca immediate none mca integer integer none)],
    [qw(pv_battery_mode_code pvBatteryModeCode status
            status:fbuf_akkuMode immediate-on-change none fbuf_akkuMode integer nonnegative_integer none)],
    [qw(device_reboot_count deviceRebootCount device_health
            status:rbc interval none device_health integer nonnegative_integer none)],
    [qw(device_uptime uptime device_health
            status:rbt interval device device_uptime hours_minutes_ms nonnegative_integer none)],
    [qw(diag_fbuf_akku_soc diag_fbuf_akkuSOC optional_diagnostic
            status:fbuf_akkuSOC interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_p_akku diag_fbuf_pAkku optional_diagnostic
            status:fbuf_pAkku interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_p_grid diag_fbuf_pGrid optional_diagnostic
            status:fbuf_pGrid interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_p_pv diag_fbuf_pPv optional_diagnostic
            status:fbuf_pPv interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_average_p_grid diag_pvopt_averagePGrid optional_diagnostic
            status:pvopt_averagePGrid interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_average_p_pv diag_pvopt_averagePPv optional_diagnostic
            status:pvopt_averagePPv interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_average_p_akku diag_pvopt_averagePAkku optional_diagnostic
            status:pvopt_averagePAkku interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_average_p_ohmpilot diag_pvopt_averagePOhmpilot optional_diagnostic
            status:pvopt_averagePOhmpilot interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_delta_p diag_pvopt_deltaP optional_diagnostic
            status:pvopt_deltaP interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_delta_a diag_pvopt_deltaA optional_diagnostic
            status:pvopt_deltaA interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_pvopt_special_case diag_pvopt_specialCase optional_diagnostic
            status:pvopt_specialCase interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_p_ac_total diag_fbuf_pAcTotal optional_diagnostic
            status:fbuf_pAcTotal interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_ohmpilot_state diag_fbuf_ohmpilotState optional_diagnostic
            status:fbuf_ohmpilotState interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(diag_fbuf_ohmpilot_temperature diag_fbuf_ohmpilotTemperature optional_diagnostic
            status:fbuf_ohmpilotTemperature interval diagnostic diagnostic diagnostic2 raw_scalar none)],
    [qw(energy_total energyTotal telemetry
            status:eto interval none energy decimal2 number none)],
    [qw(energy_since_plug_in energySincePlugIn telemetry
            status:wh interval none energy decimal2 number none)],
    [qw(voltage_l1 voltageL1 telemetry status:nrg[0] interval electrical nrg decimal2 nrg none)],
    [qw(voltage_l2 voltageL2 telemetry status:nrg[1] interval electrical nrg decimal2 nrg none)],
    [qw(voltage_l3 voltageL3 telemetry status:nrg[2] interval electrical nrg decimal2 nrg none)],
    [qw(current_l1 currentL1 telemetry status:nrg[4] interval electrical nrg decimal2 nrg none)],
    [qw(current_l2 currentL2 telemetry status:nrg[5] interval electrical nrg decimal2 nrg none)],
    [qw(current_l3 currentL3 telemetry status:nrg[6] interval electrical nrg decimal2 nrg none)],
    [qw(power_l1 powerL1 telemetry status:nrg[7] interval electrical nrg decimal2 nrg none)],
    [qw(power_l2 powerL2 telemetry status:nrg[8] interval electrical nrg decimal2 nrg none)],
    [qw(power_l3 powerL3 telemetry status:nrg[9] interval electrical nrg decimal2 nrg none)],
    [qw(power power telemetry status:nrg[11] interval electrical nrg decimal2 nrg none)],
    [qw(last_command_request_id lastCommandRequestId command_diagnostic
            event:response immediate none command integer none none)],
    [qw(last_command_status lastCommandStatus command_diagnostic
            event:response immediate none command enum none none)],
    [qw(last_command_error lastCommandError command_diagnostic
            event:response immediate none command text none none)],
);

my @WATTPILOT_READING_POLICY_FIELD = qw(
    category source publication idleGate owner formatter validator detail
);
my (
    %WATTPILOT_READING_NAME,
    %WATTPILOT_READING_POLICY,
    %WATTPILOT_STATUS_SCHEMA,
    %WATTPILOT_STATUS_READING_KEYS,
);
my @WATTPILOT_IMMEDIATE_STATUS_READING;
for my $definition (@WATTPILOT_READING_DEFINITION) {
    my ($key, $name, @values) = @$definition;
    $WATTPILOT_READING_NAME{$key} = $name;
    my %policy = map {
        $WATTPILOT_READING_POLICY_FIELD[$_] => $values[$_]
    } 0 .. $#WATTPILOT_READING_POLICY_FIELD;
    $policy{invalid} = 'preserve';
    $WATTPILOT_READING_POLICY{$key} = \%policy;

    next if $policy{source} !~ /^status:([A-Za-z0-9_]+)(?:\[\d+\])?$/;
    my $protocol_key = $1;
    push @{$WATTPILOT_STATUS_READING_KEYS{$protocol_key}}, $key;
    if ($policy{validator} ne 'none') {
        my %spec = (kind => $policy{validator});
        $spec{allow_end_of_day} = $policy{detail} eq 'end_of_day' ? 1 : 0
            if $policy{validator} eq 'clock_seconds';
        if (my $existing = $WATTPILOT_STATUS_SCHEMA{$protocol_key}) {
            die "Conflicting validators for Wattpilot status field $protocol_key"
                if $existing->{kind} ne $spec{kind}
                || (($existing->{allow_end_of_day} // 0)
                    != ($spec{allow_end_of_day} // 0));
        }
        else {
            $WATTPILOT_STATUS_SCHEMA{$protocol_key} = \%spec;
        }
    }
    push @WATTPILOT_IMMEDIATE_STATUS_READING, [$protocol_key, $key]
        if $policy{publication} eq 'immediate'
        || $policy{publication} eq 'immediate-on-change';
}

my %WATTPILOT_READING_CATEGORY = map {
    $_ => $WATTPILOT_READING_POLICY{$_}{category}
} keys %WATTPILOT_READING_POLICY;

my %WATTPILOT_READING_KEY_BY_NAME = reverse %WATTPILOT_READING_NAME;

my (
    %WATTPILOT_TELEMETRY_OWNER_IDLE_GATE,
    %WATTPILOT_SCALAR_TELEMETRY_BY_OWNER,
);
my @WATTPILOT_TELEMETRY_OWNER_DISCOVERY_ORDER;
my %WATTPILOT_TELEMETRY_OWNER_SEEN;
for my $definition (@WATTPILOT_READING_DEFINITION) {
    my ($reading_key) = @$definition;
    my $policy = $WATTPILOT_READING_POLICY{$reading_key};
    next if $policy->{publication} ne 'interval';
    my $owner = $policy->{owner};
    my $idle_gate = $policy->{idleGate};
    die "Conflicting idle gates for telemetry owner $owner"
        if exists($WATTPILOT_TELEMETRY_OWNER_IDLE_GATE{$owner})
        && $WATTPILOT_TELEMETRY_OWNER_IDLE_GATE{$owner} ne $idle_gate;
    $WATTPILOT_TELEMETRY_OWNER_IDLE_GATE{$owner} = $idle_gate;
    if (!$WATTPILOT_TELEMETRY_OWNER_SEEN{$owner}++) {
        push @WATTPILOT_TELEMETRY_OWNER_DISCOVERY_ORDER, $owner;
    }
    if ($policy->{source} =~ /^status:([A-Za-z0-9_]+)$/) {
        push @{$WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$owner}},
            [$1, $reading_key];
    }
}

my $WATTPILOT_ENERGY_OWNER = $WATTPILOT_READING_POLICY{energy_total}{owner};
my $WATTPILOT_NRG_OWNER = $WATTPILOT_READING_POLICY{power}{owner};
my $WATTPILOT_DIAGNOSTIC_OWNER =
    $WATTPILOT_READING_POLICY{diag_fbuf_p_grid}{owner};
my @WATTPILOT_TELEMETRY_OWNER_ORDER = (
    $WATTPILOT_ENERGY_OWNER,
    $WATTPILOT_NRG_OWNER,
    grep {
        $_ ne $WATTPILOT_ENERGY_OWNER && $_ ne $WATTPILOT_NRG_OWNER
    } @WATTPILOT_TELEMETRY_OWNER_DISCOVERY_ORDER,
);

for my $owner (@WATTPILOT_TELEMETRY_OWNER_ORDER) {
    next if $owner eq $WATTPILOT_ENERGY_OWNER;
    next if $owner eq $WATTPILOT_NRG_OWNER;
    my $fields = $WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$owner};
    die "Missing scalar telemetry mapping for Wattpilot owner $owner"
        if ref($fields) ne 'ARRAY' || !@$fields;
}

my %WATTPILOT_OPTIONAL_DIAGNOSTIC_PROTOCOL_KEY = map {
    $_->[0] => 1
} @{$WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$WATTPILOT_DIAGNOSTIC_OWNER}};
my @WATTPILOT_OPTIONAL_DIAGNOSTIC_READING = map {
    $WATTPILOT_READING_NAME{$_->[1]}
} @{$WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$WATTPILOT_DIAGNOSTIC_OWNER}};

# key, public name, FHEMWEB widget, protocol key, parser, usage, invalid mode
my @WATTPILOT_COMMAND_DEFINITION = (
    ['password', 'password', 'none', 'none', 'special', '<secret>', 'usage'],
    ['force_state', 'forceState', 'neutral,off,on', 'frc', 'force_state', '<neutral|off|on>', 'usage'],
    ['charging_current', 'chargingCurrent', 'slider,6,1,32', 'amp', 'charging_current', '<6-32>', 'usage'],
    ['charging_mode', 'chargingMode', 'default,eco,nextTrip', 'lmo', 'charging_mode', '<default|eco|nextTrip>', 'unknown_mode'],
    ['pv_surplus_start_power', 'pvSurplusStartPower', 'none', 'fst', 'nonnegative_number', '<watts>', 'usage'],
    ['pv_surplus_enabled', 'pvSurplusEnabled', '0,1', 'fup', 'boolean', '<0|1>', 'usage'],
    ['zero_feed_in_enabled', 'zeroFeedInEnabled', '0,1', 'fzf', 'boolean', '<0|1>', 'usage'],
    ['pv_control_preference', 'pvControlPreference', 'preferFromGrid,default,preferToGrid', 'frm', 'pv_control', '<preferFromGrid|default|preferToGrid>', 'usage'],
    ['phase_switch', 'phaseSwitch', 'none', 'none', 'special', 'none', 'usage'],
    ['minimum_charging', 'minimumCharging', 'none', 'none', 'special', 'none', 'usage'],
    ['charging_pause_allowed', 'chargingPauseAllowed', '0,1', 'fap', 'boolean', '<0|1>', 'usage'],
    ['reconnect', 'reconnect', 'noArg', 'none', 'special', 'none', 'usage'],
    ['pv_battery', 'pvBattery', 'none', 'none', 'special', 'none', 'usage'],
    ['next_trip_time', 'nextTripTime', 'none', 'ftt', 'clock', '<HH:MM>', 'usage'],
);

my (%WATTPILOT_COMMAND_NAME, %WATTPILOT_COMMAND_SCHEMA, %WATTPILOT_COMMAND_BY_NAME);
for my $definition (@WATTPILOT_COMMAND_DEFINITION) {
    my ($key, $name, $widget, $protocol_key, $parser, $usage, $invalid) = @$definition;
    my $schema = {
        name => $name,
        widget => $widget,
        protocolKey => $protocol_key,
        parser => $parser,
        usage => $usage,
        invalid => $invalid,
    };
    $WATTPILOT_COMMAND_NAME{$key} = $name;
    $WATTPILOT_COMMAND_SCHEMA{$key} = $schema;
    $WATTPILOT_COMMAND_BY_NAME{$name} = $schema;
}

# group key => ordered [subcommand, protocol key, parser, usage]
my %WATTPILOT_GROUPED_COMMAND_DEFINITION = (
    minimum_charging => [
        ['duration', 'fmt', 'seconds', '<seconds>'],
        ['interval', 'mci', 'seconds', '<seconds>'],
        ['pauseDuration', 'mcpd', 'seconds', '<seconds>'],
    ],
    phase_switch => [
        ['delay', 'mpwst', 'seconds', '<seconds>'],
        ['mode', 'psm', 'phase_switch', '<auto|force1|force3>'],
        ['minInterval', 'mptwt', 'seconds', '<seconds>'],
        ['threePhasePower', 'spl3', 'nonnegative_number', '<watts>'],
    ],
);

my (%WATTPILOT_GROUPED_COMMAND_SCHEMA, %WATTPILOT_GROUPED_COMMAND_BY_NAME);
for my $group_key (keys %WATTPILOT_GROUPED_COMMAND_DEFINITION) {
    my $group_name = $WATTPILOT_COMMAND_NAME{$group_key};
    $WATTPILOT_GROUPED_COMMAND_BY_NAME{$group_name} = $group_key;
    for my $definition (@{$WATTPILOT_GROUPED_COMMAND_DEFINITION{$group_key}}) {
        my ($setting, $protocol_key, $parser, $usage) = @$definition;
        $WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$setting} = {
            protocolKey => $protocol_key,
            parser => $parser,
            usage => $usage,
        };
    }
}

my %WATTPILOT_OBSERVED_IGNORED_MESSAGE_TYPE = map { $_ => 1 } qw(
    clearInverters
    updateInverter
    clearSmips
);

my %WATTPILOT_CAR_STATE = (
    0 => 'unknown',
    1 => 'idle',
    2 => 'charging',
    3 => 'waitingForCar',
    4 => 'complete',
    5 => 'error',
);

my %WATTPILOT_FORCE_STATE = (
    0 => 'neutral',
    1 => 'off',
    2 => 'on',
);

my %WATTPILOT_CHARGING_MODE = (
    3 => 'default',
    4 => 'eco',
    5 => 'nextTrip',
);

my %WATTPILOT_CHARGING_DECISION = (
    0  => 'notChargingBecauseNoChargeCtrlData',
    1  => 'notChargingBecauseOvertemperature',
    2  => 'notChargingBecauseAccessControlWait',
    3  => 'chargingBecauseForceStateOn',
    4  => 'notChargingBecauseForceStateOff',
    5  => 'notChargingBecauseScheduler',
    6  => 'notChargingBecauseEnergyLimit',
    7  => 'chargingBecauseAwattarPriceLow',
    8  => 'chargingBecauseAutomaticStopTestLadung',
    9  => 'chargingBecauseAutomaticStopNotEnoughTime',
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
);

my %WATTPILOT_FORCE_COMMAND_VALUE = (
    neutral => 0,
    off     => 1,
    on      => 2,
);

my %WATTPILOT_CHARGING_MODE_VALUE = reverse %WATTPILOT_CHARGING_MODE;

my %WATTPILOT_PV_CONTROL_PREFERENCE = (
    0 => 'preferFromGrid',
    1 => 'default',
    2 => 'preferToGrid',
);

my %WATTPILOT_PV_CONTROL_PREFERENCE_VALUE =
    reverse %WATTPILOT_PV_CONTROL_PREFERENCE;

my %WATTPILOT_PHASE_SWITCH_MODE = (
    0 => 'auto',
    1 => 'force1',
    2 => 'force3',
);

my %WATTPILOT_PHASE_SWITCH_MODE_VALUE = reverse %WATTPILOT_PHASE_SWITCH_MODE;

my %WATTPILOT_STATUS_ENUM_MAP = (
    car => \%WATTPILOT_CAR_STATE,
    force => \%WATTPILOT_FORCE_STATE,
    charging_mode => \%WATTPILOT_CHARGING_MODE,
    charging_decision => \%WATTPILOT_CHARGING_DECISION,
    pv_control => \%WATTPILOT_PV_CONTROL_PREFERENCE,
    phase_switch => \%WATTPILOT_PHASE_SWITCH_MODE,
);

my %WATTPILOT_LIFECYCLE_STATE = (
    disabled               => 'disabled',
    credential_error       => 'credentialError',
    password_missing       => 'passwordMissing',
    disconnected           => 'disconnected',
    connecting             => 'connecting',
    connection_failed      => 'connectionFailed',
    authenticating         => 'authenticating',
    initializing           => 'initializing',
    connected              => 'connected',
    auth_failed            => 'authFailed',
    auth_timeout           => 'authTimeout',
    initialization_timeout => 'initializationTimeout',
    auth_sequence_invalid  => 'authSequenceInvalid',
    auth_config_missing    => 'authConfigMissing',
    auth_challenge_invalid => 'authChallengeInvalid',
    auth_hash_unsupported  => 'authHashUnsupported',
    auth_hash_failed       => 'authHashFailed',
    auth_hash_store_failed => 'authHashStoreFailed',
    auth_nonce_failed      => 'authNonceFailed',
);

eval {
    require Crypt::Bcrypt;
    Crypt::Bcrypt->import(qw(bcrypt));
    1;
};


sub Wattpilot_Initialize($) {
    my ($hash) = @_;

    # FHEM CommandReload calls Initialize while existing device hashes remain
    # in %defs. Refresh only the module-version Internal; do not alter runtime
    # state, connections, credentials, timers, or readings.
    for my $device_hash (values %defs) {
        next if ref($device_hash) ne 'HASH';
        next if ($device_hash->{TYPE} // '') ne 'Wattpilot';
        $device_hash->{VERSION} = $WATTPILOT_VERSION;
        if (AttrVal($device_hash->{NAME}, 'diagnosticReadings', 0) eq '1') {
            Wattpilot_ClearOptionalDiagnosticCache($device_hash);
        }
        else {
            Wattpilot_ClearOptionalDiagnosticReadings($device_hash);
        }
    }

    $hash->{DefFn}    = \&Wattpilot_Define;
    $hash->{UndefFn}  = \&Wattpilot_Undefine;
    $hash->{DeleteFn} = \&Wattpilot_Delete;
    $hash->{RenameFn} = \&Wattpilot_Rename;
    $hash->{SetFn}    = \&Wattpilot_Set;
    $hash->{AttrFn}   = \&Wattpilot_Attr;
    $hash->{ReadFn}   = \&Wattpilot_Read;
    $hash->{ReadyFn}  = \&Wattpilot_Ready;
    $hash->{ShutdownFn} = \&Wattpilot_Shutdown;
    
    $hash->{AttrList} = "interval:slider,0,5,300 update_while_idle:0,1 diagnosticReadings:0,1 disable:0,1 rawJsonLog:0,1 authHash:auto,pbkdf2,bcrypt authHashCost:slider,4,1,14 " .
        $readingFnAttributes;

    return FHEM::Meta::InitMod(__FILE__, $hash);
}

sub Wattpilot_InterfaceSnapshot() {
    return {
        readings       => { %WATTPILOT_READING_NAME },
        readingCategories => { %WATTPILOT_READING_CATEGORY },
        readingPolicy   => { map { $_ => { %{$WATTPILOT_READING_POLICY{$_}} } }
            keys %WATTPILOT_READING_POLICY },
        telemetryCadence => {
            mode => 'shared',
            owners => [sort keys %WATTPILOT_TELEMETRY_OWNER_IDLE_GATE],
        },
        commands       => { %WATTPILOT_COMMAND_NAME },
        commandSchema  => { map { $_ => { %{$WATTPILOT_COMMAND_SCHEMA{$_}} } }
            keys %WATTPILOT_COMMAND_SCHEMA },
        groupedCommandSchema => { map {
            my $group_key = $_;
            $group_key => { map {
                $_ => { %{$WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$_}} }
            } keys %{$WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}} }
        } keys %WATTPILOT_GROUPED_COMMAND_SCHEMA },
        statusFields   => { map {
            $_ => {
                %{$WATTPILOT_STATUS_SCHEMA{$_}},
                readings => [@{$WATTPILOT_STATUS_READING_KEYS{$_} // []}],
            }
        } keys %WATTPILOT_STATUS_SCHEMA },
        carStates      => { %WATTPILOT_CAR_STATE },
        forceStates    => { %WATTPILOT_FORCE_STATE },
        chargingModes     => { %WATTPILOT_CHARGING_MODE },
        pvControlPreferences => { %WATTPILOT_PV_CONTROL_PREFERENCE },
        phaseSwitchModes     => { %WATTPILOT_PHASE_SWITCH_MODE },
        chargingDecisions => { %WATTPILOT_CHARGING_DECISION },
        lifecycle          => { %WATTPILOT_LIFECYCLE_STATE },
    };
}

sub Wattpilot_NextLifecycleGeneration($) {
    my ($hash) = @_;
    $hash->{helper}{lifecycleGeneration} = ($hash->{helper}{lifecycleGeneration} // 0) + 1;
    return $hash->{helper}{lifecycleGeneration};
}

sub Wattpilot_CurrentLifecycleGeneration($) {
    my ($hash) = @_;
    $hash->{helper}{lifecycleGeneration} //= 0;
    return $hash->{helper}{lifecycleGeneration};
}

sub Wattpilot_IsRuntimeActive($;$) {
    my ($hash, $disable_override) = @_;
    return 0 if ref($hash) ne 'HASH';
    return 0 if $hash->{helper}{undefined} || $hash->{helper}{deleting} || $hash->{helper}{shuttingDown};
    my $disabled = defined($disable_override)
        ? $disable_override
        : Wattpilot_IsDisabled($hash->{NAME});
    return 0 if $disabled;
    return 0 if !defined($defs{$hash->{NAME}}) || $defs{$hash->{NAME}} != $hash;
    return 1;
}

sub Wattpilot_TimerContextValid($$) {
    my ($hash, $ctx) = @_;
    return 0 if ref($ctx) ne 'HASH' || ref($hash) ne 'HASH';
    my $kind = $ctx->{kind};
    return 0 if !defined($kind);
    return 0 if !defined($hash->{helper}{timers}{$kind});
    return 0 if $hash->{helper}{timers}{$kind} != $ctx;
    return 0 if ($ctx->{generation} // -1) != Wattpilot_CurrentLifecycleGeneration($hash);
    return 0 if !defined($defs{$ctx->{name}}) || $defs{$ctx->{name}} != $hash;
    return 0 if defined($ctx->{fuuid}) && defined($hash->{FUUID}) && $ctx->{fuuid} ne $hash->{FUUID};
    return Wattpilot_IsRuntimeActive($hash);
}

sub Wattpilot_CancelTimer($$) {
    my ($hash, $kind) = @_;
    my $ctx = delete $hash->{helper}{timers}{$kind};
    return if ref($ctx) ne 'HASH';
    RemoveInternalTimer($ctx, $ctx->{fn});
}

sub Wattpilot_CancelAllTimers($) {
    my ($hash) = @_;
    for my $kind (keys %{ $hash->{helper}{timers} // {} }) {
        Wattpilot_CancelTimer($hash, $kind);
    }
}

sub Wattpilot_ScheduleTimer($$$$;$$) {
    my ($hash, $kind, $delay, $fn, $extra, $disable_override) = @_;
    Wattpilot_CancelTimer($hash, $kind);
    return undef if !Wattpilot_IsRuntimeActive($hash, $disable_override);
    my $ctx = {
        hash => $hash,
        kind => $kind,
        fn => $fn,
        generation => Wattpilot_CurrentLifecycleGeneration($hash),
        name => $hash->{NAME},
        fuuid => $hash->{FUUID},
        %{ ref($extra) eq 'HASH' ? $extra : {} },
    };
    $hash->{helper}{timers}{$kind} = $ctx;
    InternalTimer(gettimeofday() + $delay, $fn, $ctx, 0);
    return $ctx;
}

sub Wattpilot_ScheduleConnect($;$$) {
    my ($hash, $delay, $disable_override) = @_;
    $delay //= 1;
    return undef if !Wattpilot_IsRuntimeActive($hash, $disable_override);
    return undef if DevIo_IsOpen($hash) || $hash->{helper}{openInFlight};
    return Wattpilot_ScheduleTimer($hash, 'connect', $delay, 'Wattpilot_Connect', undef, $disable_override);
}

sub Wattpilot_CloseDevIoForContext($;$) {
    my ($hash, $ctx) = @_;
    my $close_name = ref($ctx) eq 'HASH' && defined($ctx->{devioName})
        ? $ctx->{devioName}
        : $hash->{NAME};
    my $close_device = ref($ctx) eq 'HASH' && defined($ctx->{devioDevice})
        ? $ctx->{devioDevice}
        : $hash->{DeviceName};
    if ((defined($close_name) && $close_name ne ($hash->{NAME} // ''))
        || (defined($close_device) && $close_device ne ($hash->{DeviceName} // ''))) {
        my $current_name = $hash->{NAME};
        my $current_device = $hash->{DeviceName};
        $hash->{NAME} = $close_name;
        $hash->{DeviceName} = $close_device;
        DevIo_CloseDev($hash);
        $hash->{NAME} = $current_name;
        $hash->{DeviceName} = $current_device;
    } else {
        DevIo_CloseDev($hash);
    }
}

sub Wattpilot_InvalidateSession($;$$) {
    my ($hash, $close_ctx, $command_reason) = @_;
    my $open_ctx = $hash->{helper}{openInFlight};
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash, $command_reason);
    Wattpilot_CloseDevIoForContext(
        $hash, defined($close_ctx) ? $close_ctx : $open_ctx);
    return $open_ctx;
}

sub Wattpilot_ApplyConfiguredState($;$$$) {
    my ($hash, $delay, $disable_override, $connect) = @_;
    $delay //= 1;
    $connect = 1 if !defined $connect;

    my $disabled = defined($disable_override)
        ? $disable_override
        : Wattpilot_IsDisabled($hash->{NAME});
    if ($disabled) {
        delete $hash->{helper}{pendingReconnectAfterOpen};
        readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disabled}, 1);
        return $WATTPILOT_LIFECYCLE_STATE{disabled};
    }

    my $password_result = Wattpilot_GetPassword($hash);
    if ($password_result->{status} eq "error") {
        delete $hash->{helper}{pendingReconnectAfterOpen};
        readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{credential_error}, 1);
        return $WATTPILOT_LIFECYCLE_STATE{credential_error};
    }
    if ($password_result->{status} ne "value"
        || $password_result->{value} eq "") {
        delete $hash->{helper}{pendingReconnectAfterOpen};
        readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{password_missing}, 1);
        return $WATTPILOT_LIFECYCLE_STATE{password_missing};
    }

    return "configured" if !$connect;

    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1);
    if ($hash->{helper}{openInFlight}) {
        $hash->{helper}{pendingReconnectAfterOpen} = 1;
    } else {
        delete $hash->{helper}{pendingReconnectAfterOpen};
        Wattpilot_ScheduleConnect($hash, $delay, $disable_override);
    }
    return $WATTPILOT_LIFECYCLE_STATE{disconnected};
}

sub Wattpilot_FinishTimer($$) {
    my ($hash, $ctx) = @_;
    delete $hash->{helper}{timers}{$ctx->{kind}}
        if ref($ctx) eq 'HASH'
        && ($hash->{helper}{timers}{$ctx->{kind}} // undef) == $ctx;
}

sub Wattpilot_ParseDefinition($) {
    my ($def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    return (undef, "Usage: define <name> Wattpilot <IP> [Serial]")
        if @a < 3 || @a > 4;

    my $serial = $a[3] if defined $a[3];
    return (undef, "Serial must contain digits only")
        if defined($serial) && $serial !~ /^\d+$/;

    return ({
        name => $a[0],
        device_name => "ws:$a[2]:80/ws",
        serial => $serial,
    }, undef);
}

sub Wattpilot_SameOptionalScalar($$) {
    my ($left, $right) = @_;
    return 1 if !defined($left) && !defined($right);
    return 0 if !defined($left) || !defined($right);
    return $left eq $right;
}

sub Wattpilot_ClearDefinitionSessionState($) {
    my ($hash) = @_;
    Wattpilot_StopIdleRefresh($hash);
    delete $hash->{helper}{idleRefreshAttempted};
    delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
    delete $hash->{helper}{pendingReconnectAfterOpen};
    delete $hash->{helper}{car_state};
    delete $hash->{helper}{maximumCurrentLimitReceived};
    delete $hash->{helper}{telemetryPublication};
    delete $hash->{helper}{telemetryClock};
    delete $hash->{LAST_UPDATE};
    delete $hash->{LAST_BATTERY_UPDATE};
}

sub Wattpilot_Define($$) {
    my ($hash, $def) = @_;
    my ($definition, $error) = Wattpilot_ParseDefinition($def);
    return $error if defined $error;

    my $is_modify = exists $hash->{OLDDEF};
    my $old_device_name = $hash->{DeviceName};
    my $old_serial = $hash->{SERIAL};
    my $definition_changed = !$is_modify
        || !Wattpilot_SameOptionalScalar(
            $old_device_name, $definition->{device_name})
        || !Wattpilot_SameOptionalScalar(
            $old_serial, $definition->{serial});

    if ($is_modify && $definition_changed) {
        Wattpilot_ClearDefinitionSessionState($hash);
        Wattpilot_InvalidateSession($hash, {
            devioName => $hash->{NAME},
            devioDevice => $old_device_name,
        }, 'definition changed');
    } elsif (!$is_modify) {
        Wattpilot_NextLifecycleGeneration($hash);
    }

    delete $hash->{helper}{undefined};
    delete $hash->{helper}{deleting};
    delete $hash->{helper}{shuttingDown};
    delete $hash->{helper}{timeoutRetryUsed};

    $hash->{DeviceName} = $definition->{device_name};
    $hash->{VERSION} = $WATTPILOT_VERSION;
    if (defined $definition->{serial}) {
        $hash->{SERIAL} = $definition->{serial};
    } else {
        delete $hash->{SERIAL};
    }

    # DevIo privacy masks only its initial opening line. devioLoglevel reduces
    # direct DevIo diagnostics, but cannot control transitive HttpUtils logs.
    $hash->{devioLoglevel} = 6;
    $hash->{header}{'User-Agent'} = 'FHEM';

    Wattpilot_ApplyConfiguredState($hash, 2)
        if !$is_modify || $definition_changed;
    return undef;
}

sub Wattpilot_Undefine($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{undefined} = 1;
    Wattpilot_InvalidateSession($hash, undef, 'session removed');
    RemoveInternalTimer($hash);

    return undef;
}

sub Wattpilot_Delete($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{deleting} = 1;
    Wattpilot_InvalidateSession($hash, undef, 'session removed');
    RemoveInternalTimer($hash);
    my $error = Wattpilot_DeleteStoredSecrets($hash);
    Wattpilot_RestoreAfterFailedDelete($hash, $name) if defined $error;
    return $error;
}

sub Wattpilot_RestoreAfterFailedDelete($$) {
    my ($hash, $name) = @_;

    delete $hash->{helper}{undefined};
    delete $hash->{helper}{deleting};
    delete $hash->{helper}{shuttingDown};
    delete $hash->{helper}{timeoutRetryUsed};
    Wattpilot_InvalidateSession($hash, undef, 'session replaced');
    Wattpilot_ApplyConfiguredState($hash, 2);
}

sub Wattpilot_Shutdown($) {
    my ($hash) = @_;
    $hash->{helper}{shuttingDown} = 1;
    Wattpilot_InvalidateSession($hash, undef, 'session removed');
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1);
    RemoveInternalTimer($hash);
    return undef;
}

sub Wattpilot_Rename($$) {
    my ($new_name, $old_name) = @_;
    my $hash = $defs{$new_name};
    return undef if !defined $hash;

    my $was_active = Wattpilot_IsRuntimeActive($hash);
    my $open_ctx = $hash->{helper}{openInFlight};
    Wattpilot_InvalidateSession($hash, {
        devioName => $old_name,
        devioDevice => ref($open_ctx) eq 'HASH'
            ? ($open_ctx->{devioDevice} // $hash->{DeviceName})
            : $hash->{DeviceName},
    }, 'session replaced');

    Wattpilot_ApplyConfiguredState($hash, 1, undef, $was_active);
    return undef; # CommandRename ignores RenameFn replies in the audited FHEM revision.
}

sub Wattpilot_Connect($) {
    my ($arg) = @_;
    my $ctx = ref($arg) eq 'HASH' && exists($arg->{hash}) ? $arg : undef;
    my $hash = $ctx ? $ctx->{hash} : $arg;

    if ($ctx) {
        return if !Wattpilot_TimerContextValid($hash, $ctx);
        Wattpilot_FinishTimer($hash, $ctx);
    }

    return if !$ctx && defined($hash->{helper}{timers}{connect});
    return Wattpilot_StartOpen($hash, 0);
}

sub Wattpilot_StartOpen($$) {
    my ($hash, $reopen) = @_;
    return 0 if !Wattpilot_IsRuntimeActive($hash);
    return 0 if DevIo_IsOpen($hash) || $hash->{helper}{openInFlight};
    Wattpilot_ClearConnectionState($hash, 'connection lost');
    
    Log3 $hash, 3, "Wattpilot ($hash->{NAME}) - Opening WebSocket connection";
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{connecting}, 1);
    my $generation = Wattpilot_CurrentLifecycleGeneration($hash);
    my $open_ctx = {
        generation => $generation,
        name => $hash->{NAME},
        devioName => $hash->{NAME},
        devioDevice => $hash->{DeviceName},
        fuuid => $hash->{FUUID},
    };
    $hash->{helper}{openInFlight} = $open_ctx;
    
    # WebSocket in DevIo benötigt einen Callback für den asynchronen Verbindungsaufbau
    return Wattpilot_OpenDev($hash, $reopen, sub {
        my ($hash, $error) = @_;
        my $is_owner = defined($hash->{helper}{openInFlight})
            && $hash->{helper}{openInFlight} == $open_ctx
            && ($open_ctx->{name} // '') eq ($hash->{NAME} // '')
            && Wattpilot_CurrentLifecycleGeneration($hash) == $generation
            && Wattpilot_IsRuntimeActive($hash);
        if (!$is_owner) {
            Wattpilot_CloseDevIoForContext($hash, $open_ctx);
            if (defined($hash->{helper}{openInFlight})
                && $hash->{helper}{openInFlight} == $open_ctx) {
                delete $hash->{helper}{openInFlight};
            }
            my $pending_reconnect =
                delete $hash->{helper}{pendingReconnectAfterOpen};
            if ($pending_reconnect && Wattpilot_IsRuntimeActive($hash)) {
                Wattpilot_ApplyConfiguredState($hash, 1);
            } elsif (Wattpilot_IsDisabled($hash->{NAME})) {
                readingsSingleUpdate(
                    $hash, $WATTPILOT_READING_NAME{state},
                    $WATTPILOT_LIFECYCLE_STATE{disabled}, 1);
            } elsif ($hash->{helper}{shuttingDown}) {
                readingsSingleUpdate(
                    $hash, $WATTPILOT_READING_NAME{state},
                    $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1);
            }
            return;
        }
        delete $hash->{helper}{openInFlight};
        if($error) {
            Log3 $hash, 1, "Wattpilot ($hash->{NAME}) - WebSocket connection failed";
            readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{connection_failed}, 1);
            Wattpilot_ScheduleConnect($hash, 60)
                if !defined($hash->{NEXT_OPEN}) || $hash->{NEXT_OPEN} <= gettimeofday();
            return;
        }
        if (!DevIo_IsOpen($hash)) {
            readingsSingleUpdate(
                $hash, $WATTPILOT_READING_NAME{state},
                $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1)
                if Wattpilot_IsRuntimeActive($hash)
                && ($hash->{STATE} // '') ne $WATTPILOT_LIFECYCLE_STATE{disconnected};
            return;
        }
        Wattpilot_DoInit($hash);
    });
}

sub Wattpilot_OpenDev($$$) {
    my ($hash, $reopen, $callback) = @_;

    # Preserve DevIo's lifecycle semantics: 0 for an initial connection and 1
    # only for ReadyFn reconnects. Current DevIo does not expose hideurl or an
    # HttpUtils loglevel for its internal WebSocket HttpUtils_Connect hash, so
    # transitive URL/DNS logs cannot be reliably suppressed by this module.
    $hash->{devioLoglevel} = 6;
    return DevIo_OpenDev($hash, $reopen, undef, $callback);
}

sub Wattpilot_DoInit($) {
    my ($hash) = @_;
    return if !Wattpilot_IsRuntimeActive($hash);
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{authenticating}, 1);
    Wattpilot_ScheduleTimer(
        $hash, 'lifecycle_timeout', $WATTPILOT_AUTH_TIMEOUT,
        'Wattpilot_LifecycleTimeout', { phase => 'auth' });
    # Hier könnten Initialisierungsbefehle gesendet werden, falls nötig
    return undef;
}

sub Wattpilot_LifecycleTimeout($) {
    my ($ctx) = @_;
    my $hash = $ctx->{hash};
    return if !Wattpilot_TimerContextValid($hash, $ctx);
    Wattpilot_FinishTimer($hash, $ctx);

    my $phase = $ctx->{phase} // 'auth';
    my $state = $phase eq 'initialization'
        ? $WATTPILOT_LIFECYCLE_STATE{initialization_timeout}
        : $WATTPILOT_LIFECYCLE_STATE{auth_timeout};
    Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - $state";
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $state, 1);

    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash, 'lifecycle timeout');
    delete $hash->{helper}{openInFlight};
    DevIo_CloseDev($hash);

    return if $hash->{helper}{timeoutRetryUsed};
    $hash->{helper}{timeoutRetryUsed} = 1;
    Wattpilot_ScheduleConnect($hash, $WATTPILOT_TIMEOUT_RETRY_DELAY);
}

sub Wattpilot_Read($) {
    my ($hash) = @_;
    my $buf = DevIo_SimpleRead($hash);

    if (!defined($buf)) {
        my $devio_owns_reconnect = $hash->{DevIoJustClosed} ? 1 : 0;
        my $idle_refresh_pending = $hash->{helper}{idleRefreshPending} ? 1 : 0;
        Wattpilot_NextLifecycleGeneration($hash);
        Wattpilot_CancelAllTimers($hash);
        if ($idle_refresh_pending && !$hash->{helper}{idleRefreshAttempted}) {
            $hash->{helper}{idleRefreshAttempted} = 1;
            $hash->{helper}{idleRefreshAwaitingReconnectNrg} = 1;
        }
        delete $hash->{helper}{idleRefreshPending};
        delete $hash->{helper}{openInFlight};
        Wattpilot_ClearConnectionState($hash, 'connection lost');
        if (Wattpilot_IsRuntimeActive($hash)) {
            readingsSingleUpdate(
                $hash, $WATTPILOT_READING_NAME{state},
                $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1)
                if ($hash->{STATE} // '') ne $WATTPILOT_LIFECYCLE_STATE{disconnected};
            Wattpilot_ScheduleConnect($hash, 1) if !$devio_owns_reconnect;
        }
        return "";
    }
    return "" if $buf eq "";

    Wattpilot_ProcessJsonPayload($hash, $buf);
    return "";
}

sub Wattpilot_ProcessJsonPayload($$) {
    my ($hash, $payload) = @_;
    my $name = $hash->{NAME};

    if (!defined($payload) || ref($payload)) {
        Log3 $name, 1, "Wattpilot ($name) - JSON input rejected as oversized or invalid; payload suppressed";
        return 0;
    }

    my $buffered = $hash->{helper}{jsonBuffer} // '';
    if (bytes::length($buffered) + bytes::length($payload) > $WATTPILOT_MAX_JSON_BYTES) {
        delete $hash->{helper}{jsonBuffer};
        Log3 $name, 1, "Wattpilot ($name) - JSON input rejected as oversized or invalid; payload suppressed";
        return 0;
    }
    my $combined = $buffered . $payload;
    if ($combined !~ /\S/) {
        delete $hash->{helper}{jsonBuffer};
        return 0;
    }

    my $decoder = JSON->new->allow_nonref;
    my $remaining = $combined;
    my @documents;
    while ($remaining =~ /\S/) {
        if (@documents >= $WATTPILOT_MAX_JSON_DOCUMENTS) {
            delete $hash->{helper}{jsonBuffer};
            Log3 $name, 1,
                "Wattpilot ($name) - JSON input rejected because document count exceeds limit; payload suppressed";
            return 0;
        }
        my ($json, $used);
        my $ok = eval {
            ($json, $used) = $decoder->decode_prefix($remaining);
            1;
        };
        if (!$ok || !$used) {
            if (Wattpilot_JsonLooksIncomplete($remaining)) {
                $hash->{helper}{jsonBuffer} = $combined;
                return 0;
            }
            delete $hash->{helper}{jsonBuffer};
            Log3 $name, 1, "Wattpilot ($name) - JSON decoding failed; payload suppressed";
            return 0;
        }
        my $raw = substr($remaining, 0, $used, "");
        push @documents, [$raw, $json];
    }
    delete $hash->{helper}{jsonBuffer};
    for my $document (@documents) {
        my ($raw, $json) = @$document;
        Wattpilot_LogRawJson($hash, "IN", $raw);
        Wattpilot_DispatchMessage($hash, $json);
    }
    return scalar @documents;
}

sub Wattpilot_JsonLooksIncomplete($) {
    my ($text) = @_;
    $text =~ s/^\s+//;
    return 0 if $text eq '' || substr($text, 0, 1) ne '{';

    my @stack;
    my $in_string = 0;
    my $escaped = 0;
    for my $char (split //, $text) {
        if ($in_string) {
            if ($escaped) {
                $escaped = 0;
            } elsif ($char eq '\\') {
                $escaped = 1;
            } elsif ($char eq '"') {
                $in_string = 0;
            }
            next;
        }
        if ($char eq '"') {
            $in_string = 1;
        } elsif ($char eq '{' || $char eq '[') {
            push @stack, $char;
        } elsif ($char eq '}' || $char eq ']') {
            return 0 if !@stack;
            my $open = pop @stack;
            return 0 if ($open eq '{' && $char ne '}') || ($open eq '[' && $char ne ']');
            return 0 if !@stack;
        }
    }
    return $in_string || $escaped || @stack ? 1 : 0;
}

sub Wattpilot_Parse($$) {
    my ($hash, $msg) = @_;
    return Wattpilot_ProcessJsonPayload($hash, $msg);
}

sub Wattpilot_IsScalarString($) {
    my ($value) = @_;
    return defined($value) && !ref($value);
}

sub Wattpilot_ScalarFlags($) {
    my ($value) = @_;
    return 0 if !defined($value) || ref($value);
    return svref_2object(\$value)->FLAGS;
}

sub Wattpilot_IsJsonString($) {
    my ($value) = @_;
    my $flags = Wattpilot_ScalarFlags($value);
    return ($flags & (SVf_POK | SVp_POK)) ? 1 : 0;
}

sub Wattpilot_IsJsonNumber($) {
    my ($value) = @_;
    my $flags = Wattpilot_ScalarFlags($value);
    return 0 if !$flags;
    return 0 if $flags & (SVf_POK | SVp_POK);
    return ($flags & (SVf_IOK | SVp_IOK | SVf_NOK | SVp_NOK)) ? 1 : 0;
}

sub Wattpilot_ParseJsonFiniteNumber($) {
    my ($value) = @_;
    return undef if !Wattpilot_IsJsonNumber($value);
    my $number = 0 + $value;
    return undef if "$number" =~ /(?:inf|nan)/i;
    return $number;
}

sub Wattpilot_IsJsonInteger($) {
    my ($value) = @_;
    my $number = Wattpilot_ParseJsonFiniteNumber($value);
    return 0 if !defined $number;
    return $number == int($number) ? 1 : 0;
}

sub Wattpilot_IsJsonBoolean($) {
    my ($value) = @_;
    return JSON::is_bool($value) ? 1 : 0;
}

sub Wattpilot_MessageTypeForLog($) {
    my ($type) = @_;
    return 'redacted'
        if !Wattpilot_IsJsonString($type)
        || bytes::length($type) > 64
        || $type !~ /\A[A-Za-z][A-Za-z0-9_.:-]{0,63}\z/;
    return $type;
}

# User-entered Set values arrive as strings. These parsers are intentionally
# separate from the exact JSON-type validators used for incoming messages.
sub Wattpilot_IsNumber($) {
    my ($value) = @_;
    return 0 if !Wattpilot_IsScalarString($value);
    return $value =~ /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
}

sub Wattpilot_ParseFiniteNumber($) {
    my ($value) = @_;
    return undef if !Wattpilot_IsNumber($value);

    my $number;
    {
        no warnings 'numeric';
        $number = 0 + $value;
    }
    return undef if "$number" =~ /(?:inf|nan)/i;
    return $number;
}

sub Wattpilot_ParseFiniteNonNegativeNumber($) {
    my ($value) = @_;
    my $number = Wattpilot_ParseFiniteNumber($value);
    return undef if !defined($number) || $number < 0;
    return $number;
}

sub Wattpilot_ParsePercentage($) {
    my ($value) = @_;
    my $number = Wattpilot_ParseFiniteNonNegativeNumber($value);
    return undef if !defined($number) || $number > 100;
    return $number;
}

sub Wattpilot_ParseSecondsToMilliseconds($) {
    my ($value) = @_;
    my $seconds = Wattpilot_ParseFiniteNonNegativeNumber($value);
    return undef if !defined $seconds;

    my $milliseconds = $seconds * 1000;
    return undef if "$milliseconds" =~ /(?:inf|nan)/i;
    my $rounded = int($milliseconds + 0.5);
    return undef if abs($milliseconds - $rounded) > 0.000000001;
    return $rounded;
}

sub Wattpilot_MillisecondsToSeconds($) {
    my ($value) = @_;
    return $value / 1000;
}

sub Wattpilot_ParseClockTimeToSeconds($$) {
    my ($value, $allow_end_of_day) = @_;
    return undef if !Wattpilot_IsScalarString($value);
    return 86400 if $allow_end_of_day && $value eq '24:00';
    return undef if $value !~ /^(?:[01]\d|2[0-3]):[0-5]\d$/;
    my ($hours, $minutes) = split(':', $value);
    return ($hours * 3600) + ($minutes * 60);
}

sub Wattpilot_SecondsSinceMidnightToTime($;$) {
    my ($value, $allow_end_of_day) = @_;
    $allow_end_of_day = 1 if !defined $allow_end_of_day;
    return undef if !Wattpilot_IsJsonInteger($value);
    my $maximum = $allow_end_of_day ? 86400 : 86340;
    return undef if $value < 0 || $value > $maximum || $value % 60 != 0;
    my $hours = int($value / 3600);
    my $minutes = int(($value % 3600) / 60);
    return sprintf("%02d:%02d", $hours, $minutes);
}

sub Wattpilot_DiagnosticReadingsEnabled($) {
    my ($hash) = @_;
    return AttrVal($hash->{NAME}, 'diagnosticReadings', 0) eq '1';
}

sub Wattpilot_NormalizeStatusValue($$) {
    my ($value, $spec) = @_;
    my $kind = $spec->{kind};

    if ($kind eq 'nonempty_string') {
        return undef if !Wattpilot_IsJsonString($value) || $value eq '';
        return $value;
    }

    if ($kind eq 'raw_scalar') {
        return $value if Wattpilot_IsJsonBoolean($value);
        return $value if Wattpilot_IsJsonString($value);
        if (Wattpilot_IsJsonNumber($value)) {
            return defined(Wattpilot_ParseJsonFiniteNumber($value))
                ? $value
                : undef;
        }
        return undef;
    }

    if ($kind eq 'integer' || $kind eq 'nonnegative_integer') {
        return undef if !Wattpilot_IsJsonInteger($value);
        my $normalized = int($value);
        return undef if $kind eq 'nonnegative_integer' && $normalized < 0;
        return $normalized;
    }

    if ($kind eq 'number' || $kind eq 'nonnegative_number'
        || $kind eq 'percentage') {
        my $normalized = Wattpilot_ParseJsonFiniteNumber($value);
        return undef if !defined $normalized;
        return undef if $kind ne 'number' && $normalized < 0;
        return undef if $kind eq 'percentage' && $normalized > 100;
        return $normalized;
    }

    if ($kind eq 'clock_seconds') {
        return undef if !Wattpilot_IsJsonInteger($value);
        my $maximum = $spec->{allow_end_of_day} ? 86400 : 86340;
        return undef if $value < 0 || $value > $maximum || $value % 60 != 0;
        return int($value);
    }

    if ($kind eq 'boolean') {
        return Wattpilot_IsJsonBoolean($value) ? $value : undef;
    }

    if ($kind eq 'nrg') {
        return undef if ref($value) ne 'ARRAY' || @$value < 12;
        for my $entry (@$value[0 .. 11]) {
            return undef if !defined Wattpilot_ParseJsonFiniteNumber($entry);
        }
        return [@$value];
    }

    die "Unknown Wattpilot status schema kind: $kind";
}

sub Wattpilot_NormalizeStatus($$) {
    my ($hash, $input_status) = @_;
    return undef if ref($input_status) ne 'HASH';

    my %status = %$input_status;
    for my $key (keys %WATTPILOT_STATUS_SCHEMA) {
        next if !exists $status{$key};
        if ($WATTPILOT_OPTIONAL_DIAGNOSTIC_PROTOCOL_KEY{$key}
            && !Wattpilot_DiagnosticReadingsEnabled($hash)) {
            delete $status{$key};
            next;
        }
        if (!defined $status{$key}) {
            delete $status{$key};
            next;
        }

        my $normalized = Wattpilot_NormalizeStatusValue(
            $status{$key}, $WATTPILOT_STATUS_SCHEMA{$key});
        if (!defined $normalized) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
            next;
        }
        $status{$key} = $normalized;
    }
    return \%status;
}

sub Wattpilot_DispatchMessage($$) {
    my ($hash, $json) = @_;
    my $name = $hash->{NAME};

    if (ref($json) ne 'HASH') {
        Log3 $name, 2, "Wattpilot ($name) - Ignoring JSON message with non-object top level";
        return 0;
    }
    if (!Wattpilot_IsJsonString($json->{type}) || $json->{type} eq '') {
        Log3 $name, 2, "Wattpilot ($name) - Ignoring JSON message with missing or invalid type";
        return 0;
    }

    my $type = $json->{type};
    my $type_for_log = Wattpilot_MessageTypeForLog($type);
    Log3 $name, 4, "Wattpilot ($name) - Received JSON message type=$type_for_log";

    if ($type eq 'hello') {
        $hash->{helper}{deviceType} = $json->{devicetype}
            if Wattpilot_IsJsonString($json->{devicetype});
        $hash->{helper}{protocol} = int($json->{protocol})
            if Wattpilot_IsJsonInteger($json->{protocol});
        $hash->{SERIAL} = $json->{serial}
            if (!$hash->{SERIAL}
                && Wattpilot_IsJsonString($json->{serial})
                && $json->{serial} =~ /^\d+$/);

        readingsBeginUpdate($hash);
        Wattpilot_PublishReading(
            $hash, $WATTPILOT_READING_NAME{firmware_version},
            $json->{version})
            if Wattpilot_IsJsonString($json->{version})
            && $json->{version} ne '';
        Wattpilot_PublishReading(
            $hash, $WATTPILOT_READING_NAME{hello_protocol},
            int($json->{protocol}))
            if Wattpilot_IsJsonInteger($json->{protocol})
            && $json->{protocol} >= 0;
        readingsEndUpdate($hash, 1);
        Log3 $name, 4, "Wattpilot ($name) - Hello received";
    } elsif ($type eq 'authRequired') {
        Log3 $name, 4, "Wattpilot ($name) - Auth Required";
        Wattpilot_ClearCommandState($hash, 'authentication aborted');
        Wattpilot_SendAuth($hash, $json);
    } elsif ($type eq 'authSuccess') {
        if (!$hash->{helper}{authPending}) {
            Log3 $name, 1, "Wattpilot ($name) - Authentication success arrived outside an active challenge";
            Wattpilot_AbortAuthentication(
                $hash, $WATTPILOT_LIFECYCLE_STATE{auth_sequence_invalid});
            return 0;
        }
        Log3 $name, 2, "Wattpilot ($name) - Authentication Successful";
        $hash->{helper}{authenticated} = 1;
        delete $hash->{helper}{authPending};
        delete $hash->{helper}{authHashMode};
        Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
        readingsSingleUpdate(
            $hash, $WATTPILOT_READING_NAME{state},
            $WATTPILOT_LIFECYCLE_STATE{initializing}, 1);
        Wattpilot_ScheduleTimer(
            $hash, 'lifecycle_timeout', $WATTPILOT_INITIALIZATION_TIMEOUT,
            'Wattpilot_LifecycleTimeout', { phase => 'initialization' });
    } elsif ($type eq 'authError') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication failed";
        Wattpilot_AbortAuthentication(
            $hash, $WATTPILOT_LIFECYCLE_STATE{auth_failed});
    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {
        if (ref($json->{status}) ne 'HASH') {
            Log3 $name, 2, "Wattpilot ($name) - Ignoring status message with missing or invalid status";
            return 0;
        }

        my $partial = $type eq 'deltaStatus' ? 1 : 0;
        if ($type eq 'fullStatus' && exists $json->{partial}) {
            if (!Wattpilot_IsJsonBoolean($json->{partial})) {
                Log3 $name, 2,
                    "Wattpilot ($name) - Ignoring fullStatus with invalid partial value";
                return 0;
            }
            $partial = $json->{partial} ? 1 : 0;
        }

        my $status = Wattpilot_NormalizeStatus($hash, $json->{status});
        my $message = { type => $type, partial => $partial };
        Wattpilot_UpdateReadings($hash, $status, $message);
        Wattpilot_MarkInitialized($hash)
            if $hash->{helper}{authenticated}
            && ($hash->{STATE} // '') eq $WATTPILOT_LIFECYCLE_STATE{initializing};
    } elsif ($type eq 'response') {
        if (exists($json->{success})
            && !Wattpilot_IsJsonBoolean($json->{success})) {
            Log3 $name, 2,
                "Wattpilot ($name) - Ignoring response with invalid success value";
            return 0;
        }
        if (exists($json->{success}) && $json->{success}
            && ref($json->{status}) ne 'HASH') {
            Log3 $name, 2,
                "Wattpilot ($name) - Ignoring successful response with missing or invalid status";
            return 0;
        }
        if (ref($json->{status}) eq 'HASH') {
            $json = {
                %$json,
                status => Wattpilot_NormalizeStatus($hash, $json->{status}),
            };
        }
        Wattpilot_HandleResponse($hash, $json);
    } elsif ($WATTPILOT_OBSERVED_IGNORED_MESSAGE_TYPE{$type}) {
        # Observed on Wattpilot Flex firmware 43.4 during connection startup.
        # The module does not use their payloads and deliberately ignores them.
    } else {
        Log3 $name, 3,
            "Wattpilot ($name) - Ignoring unsupported JSON message type=$type_for_log";
    }
    return 1;
}

sub Wattpilot_MarkInitialized($) {
    my ($hash) = @_;
    Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
    delete $hash->{helper}{timeoutRetryUsed};
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{connected}, 1);
}

sub Wattpilot_StartIdleRefreshWindow($) {
    my ($hash) = @_;
    return if !DevIo_IsOpen($hash);
    return if $hash->{helper}{idleRefreshAttempted};
    return if $hash->{helper}{idleRefreshPending};
    $hash->{helper}{idleRefreshPending} = 1;
    Wattpilot_ScheduleTimer(
        $hash, 'idle_refresh', $WATTPILOT_IDLE_REFRESH_TIMEOUT,
        'Wattpilot_IdleRefreshTimeout');
}

sub Wattpilot_ClearIdleRefreshWindow($) {
    my ($hash) = @_;
    delete $hash->{helper}{idleRefreshPending};
    Wattpilot_CancelTimer($hash, 'idle_refresh');
}

sub Wattpilot_StopIdleRefresh($) {
    my ($hash) = @_;
    Wattpilot_ClearIdleRefreshWindow($hash);
    delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
}

sub Wattpilot_IdleRefreshTimeout($) {
    my ($ctx) = @_;
    my $hash = $ctx->{hash};
    return if !Wattpilot_TimerContextValid($hash, $ctx);
    Wattpilot_FinishTimer($hash, $ctx);
    delete $hash->{helper}{idleRefreshPending};
    return if $hash->{helper}{idleRefreshAttempted};
    $hash->{helper}{idleRefreshAttempted} = 1;
    $hash->{helper}{idleRefreshAwaitingReconnectNrg} = 1;
    Log3 $hash->{NAME}, 3,
        "Wattpilot ($hash->{NAME}) - idle refresh fallback closes the session once for this idle episode";
    Wattpilot_InvalidateSession($hash, undef, 'connection lost');
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1);
    Wattpilot_ScheduleConnect($hash, 1);
}

sub Wattpilot_FormatDecimal($$) {
    my ($value, $places) = @_;
    my $formatted = sprintf('%.*f', $places, $value);
    return sprintf('%.*f', $places, 0)
        if $formatted =~ /\A-0(?:\.0+)?\z/;
    return $formatted;
}

sub Wattpilot_FormatReadingValue($$) {
    my ($reading_key, $value) = @_;
    my $policy = $WATTPILOT_READING_POLICY{$reading_key}
        or die "Unknown Wattpilot reading key: $reading_key";
    my $formatter = $policy->{formatter};

    return $value
        if $formatter eq 'lifecycle'
        || $formatter eq 'text'
        || $formatter eq 'percentage';
    return int($value) if $formatter eq 'integer';
    return $value ? 1 : 0 if $formatter eq 'boolean';
    return Wattpilot_MillisecondsToSeconds($value) if $formatter eq 'seconds';
    return Wattpilot_SecondsSinceMidnightToTime(
        $value, $policy->{detail} eq 'end_of_day')
        if $formatter eq 'clock';
    if ($formatter eq 'enum') {
        return $value if $policy->{detail} eq 'none';
        my $map = $WATTPILOT_STATUS_ENUM_MAP{$policy->{detail}};
        die "Missing enum map for Wattpilot reading $reading_key" if !$map;
        my $normalized = int($value);
        return $map->{$normalized} // 'unknown:' . $normalized;
    }
    return Wattpilot_FormatDecimal($value, 2) if $formatter eq 'decimal2';
    if ($formatter eq 'diagnostic2') {
        return $value ? 1 : 0 if Wattpilot_IsJsonBoolean($value);
        return Wattpilot_FormatDecimal($value, 2)
            if Wattpilot_IsJsonNumber($value);
        return $value;
    }
    if ($formatter eq 'hours_minutes_ms') {
        my $seconds = int(Wattpilot_MillisecondsToSeconds($value));
        my $hours = int($seconds / 3600);
        my $minutes = int(($seconds % 3600) / 60);
        return sprintf('%d:%02d', $hours, $minutes);
    }
    die "Unknown Wattpilot reading formatter: $formatter";
}

sub Wattpilot_PublishReading($$$) {
    my ($hash, $reading, $value) = @_;
    my $reading_key = $WATTPILOT_READING_KEY_BY_NAME{$reading};
    my $publication = defined($reading_key)
        ? $WATTPILOT_READING_POLICY{$reading_key}{publication}
        : 'immediate';
    $value = Wattpilot_FormatReadingValue($reading_key, $value)
        if defined $reading_key;
    return readingsBulkUpdateIfChanged($hash, $reading, $value)
        if $publication eq 'immediate-on-change';
    return readingsBulkUpdate($hash, $reading, $value);
}

sub Wattpilot_UpdateInternalStatus($$) {
    my ($hash, $status) = @_;
    $hash->{helper}{car_state} = int($status->{car})
        if defined $status->{car};
    $hash->{helper}{maximumCurrentLimitReceived} = 1
        if defined $status->{ama};
}

sub Wattpilot_UpdateImmediateReadings($$) {
    my ($hash, $status) = @_;

    for my $field (@WATTPILOT_IMMEDIATE_STATUS_READING) {
        my ($protocol_key, $reading_key) = @$field;
        next if !defined $status->{$protocol_key};
        Wattpilot_PublishReading(
            $hash, $WATTPILOT_READING_NAME{$reading_key},
            $status->{$protocol_key});
    }
}

sub Wattpilot_HasValidNrg($) {
    my ($status) = @_;
    return 0 if ref($status->{nrg}) ne 'ARRAY';
    return 0 if @{$status->{nrg}} < 12;
    return !grep { !defined(Wattpilot_ParseJsonFiniteNumber($_)) }
        @{$status->{nrg}}[0..11];
}

sub Wattpilot_HasEnergyTelemetry($) {
    my ($status) = @_;
    return 1 if defined $status->{eto};
    return 1 if defined $status->{wh};
    return 0;
}

sub Wattpilot_HasScalarTelemetry($$) {
    my ($status, $fields) = @_;
    for my $field (@$fields) {
        return 1 if defined $status->{$field->[0]};
    }
    return 0;
}

sub Wattpilot_TelemetryGroupState($$) {
    my ($hash, $owner) = @_;
    my $state = $hash->{helper}{telemetryPublication}{$owner} //= {
        cache => {},
        dirty => {},
    };
    delete $state->{lastUpdate};
    return $state;
}

sub Wattpilot_FormatEnergyTelemetry($$) {
    my ($key, $value) = @_;
    return Wattpilot_FormatReadingValue('energy_total', $value / 1000)
        if $key eq 'eto';
    return Wattpilot_FormatReadingValue('energy_since_plug_in', $value)
        if $key eq 'wh';
    return undef;
}

sub Wattpilot_CacheEnergyTelemetry($$$) {
    my ($hash, $state, $key) = @_;
    my $value = $state->{cache}{$key};
    my $formatted = Wattpilot_FormatEnergyTelemetry($key, $value);
    return if !defined $formatted;
    my $reading_key = $key eq 'eto' ? 'energy_total' : 'energy_since_plug_in';
    my $reading = $WATTPILOT_READING_NAME{$reading_key};
    my $published = $hash->{READINGS}{$reading}{VAL};
    if (!defined($published) || $published ne $formatted) {
        $state->{dirty}{$key} = 1;
    } else {
        delete $state->{dirty}{$key};
    }
}

sub Wattpilot_CacheScalarTelemetryGroup($$$$) {
    my ($hash, $status, $owner, $fields) = @_;
    my $state = Wattpilot_TelemetryGroupState($hash, $owner);
    for my $field (@$fields) {
        my ($protocol_key) = @$field;
        next if !defined $status->{$protocol_key};
        $state->{cache}{$protocol_key} = $status->{$protocol_key};
        $state->{dirty}{$protocol_key} = 1;
    }
}

sub Wattpilot_CacheTelemetry($$) {
    my ($hash, $status) = @_;

    if (Wattpilot_HasValidNrg($status)) {
        my $state = Wattpilot_TelemetryGroupState($hash, $WATTPILOT_NRG_OWNER);
        $state->{cache}{nrg} = [@{$status->{nrg}}];
        $state->{dirty}{nrg} = 1;
    }

    my $energy = Wattpilot_TelemetryGroupState($hash, $WATTPILOT_ENERGY_OWNER);
    for my $key (qw(eto wh)) {
        next if !defined $status->{$key};
        $energy->{cache}{$key} = $status->{$key};
        Wattpilot_CacheEnergyTelemetry($hash, $energy, $key);
    }

    for my $owner (@WATTPILOT_TELEMETRY_OWNER_ORDER) {
        next if $owner eq $WATTPILOT_ENERGY_OWNER;
        next if $owner eq $WATTPILOT_NRG_OWNER;
        next if $owner eq $WATTPILOT_DIAGNOSTIC_OWNER
            && !Wattpilot_DiagnosticReadingsEnabled($hash);
        my $fields = $WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$owner};
        Wattpilot_CacheScalarTelemetryGroup(
            $hash, $status, $owner, $fields);
    }
}

sub Wattpilot_ClearOptionalDiagnosticCache($) {
    my ($hash) = @_;
    return if ref($hash) ne 'HASH';
    delete $hash->{helper}{telemetryPublication}{$WATTPILOT_DIAGNOSTIC_OWNER}
        if ref($hash->{helper}{telemetryPublication}) eq 'HASH';
}

sub Wattpilot_ClearOptionalDiagnosticReadings($) {
    my ($hash) = @_;
    return if ref($hash) ne 'HASH';
    Wattpilot_ClearOptionalDiagnosticCache($hash);
    for my $reading (@WATTPILOT_OPTIONAL_DIAGNOSTIC_READING) {
        delete $hash->{READINGS}{$reading};
    }
}

sub Wattpilot_TelemetryIdleGateOpen($) {
    my ($hash) = @_;
    return 1 if ($hash->{helper}{car_state} // 0) == 2;
    return AttrVal($hash->{NAME}, 'update_while_idle', 0) eq '1';
}

sub Wattpilot_TelemetryGroupHasDirty($) {
    my ($state) = @_;
    return ref($state->{dirty}) eq 'HASH' && keys %{$state->{dirty}};
}

sub Wattpilot_TelemetryOwnerEligible($$;$) {
    my ($hash, $owner, $bypass) = @_;
    $bypass //= 0;
    my $state = $hash->{helper}{telemetryPublication}{$owner};
    return 0 if ref($state) ne 'HASH';
    return 0 if !Wattpilot_TelemetryGroupHasDirty($state);
    return 1 if $bypass;

    my $idle_gate = $WATTPILOT_TELEMETRY_OWNER_IDLE_GATE{$owner} // 'none';
    return 1 if $idle_gate eq 'none';
    return Wattpilot_TelemetryIdleGateOpen($hash);
}

sub Wattpilot_UpdateScalarTelemetryReadings($$$) {
    my ($hash, $state, $fields) = @_;
    my $cache = $state->{cache} // {};
    my $dirty = $state->{dirty} // {};

    for my $field (@$fields) {
        my ($protocol_key, $reading_key) = @$field;
        next if !$dirty->{$protocol_key};
        next if !defined $cache->{$protocol_key};
        readingsBulkUpdate(
            $hash,
            $WATTPILOT_READING_NAME{$reading_key},
            Wattpilot_FormatReadingValue(
                $reading_key, $cache->{$protocol_key}));
    }
    $state->{dirty} = {};
}

sub Wattpilot_HandleCarTransition($$) {
    my ($hash, $previous_car_state) = @_;
    my $is_charging = ($hash->{helper}{car_state} // 0) == 2;
    my $transitioned_from_charging =
        defined($previous_car_state)
        && $previous_car_state == 2
        && defined($hash->{helper}{car_state})
        && $hash->{helper}{car_state} != 2;

    if ($is_charging) {
        $hash->{helper}{idleRefreshAttempted} = 0;
        Wattpilot_StopIdleRefresh($hash);
    } elsif ($transitioned_from_charging) {
        Wattpilot_StartIdleRefreshWindow($hash);
    }
    return $is_charging;
}

sub Wattpilot_NrgIdleBypass($$$) {
    my ($hash, $status, $message) = @_;
    my $has_valid_nrg = Wattpilot_HasValidNrg($status);
    my $message_type = $message->{type};

    if ($hash->{helper}{idleRefreshAwaitingReconnectNrg}
        && !$has_valid_nrg
        && $message_type eq 'fullStatus'
        && !$message->{partial}) {
        delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
    }

    return 0 if !$has_valid_nrg;
    return 0 if !$hash->{helper}{idleRefreshPending}
        && !$hash->{helper}{idleRefreshAwaitingReconnectNrg};

    Wattpilot_StopIdleRefresh($hash);
    delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
    return 1;
}

sub Wattpilot_UpdateEnergyReadings($$) {
    my ($hash, $state) = @_;
    my $cache = $state->{cache} // {};
    my $dirty = $state->{dirty} // {};

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{energy_total},
        Wattpilot_FormatEnergyTelemetry('eto', $cache->{eto}))
        if $dirty->{eto};
    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{energy_since_plug_in},
        Wattpilot_FormatEnergyTelemetry('wh', $cache->{wh}))
        if $dirty->{wh};

    $state->{dirty} = {};
}

sub Wattpilot_UpdateNrgReadings($$) {
    my ($hash, $state) = @_;
    return if !$state->{dirty}{nrg};
    return if ref($state->{cache}{nrg}) ne 'ARRAY';
    my @nrg = @{$state->{cache}{nrg}};
    return if @nrg <= 11;

    my @fields = (
        [voltage_l1 => 0], [voltage_l2 => 1], [voltage_l3 => 2],
        [current_l1 => 4], [current_l2 => 5], [current_l3 => 6],
        [power_l1 => 7], [power_l2 => 8], [power_l3 => 9],
        [power => 11],
    );
    for my $field (@fields) {
        my ($reading_key, $index) = @$field;
        readingsBulkUpdate(
            $hash,
            $WATTPILOT_READING_NAME{$reading_key},
            Wattpilot_FormatReadingValue($reading_key, $nrg[$index]));
    }
    $state->{dirty} = {};
}

sub Wattpilot_HasDirtyTelemetry($) {
    my ($hash) = @_;
    for my $owner (keys %WATTPILOT_TELEMETRY_OWNER_IDLE_GATE) {
        my $state = $hash->{helper}{telemetryPublication}{$owner};
        return 1 if ref($state) eq 'HASH'
            && Wattpilot_TelemetryGroupHasDirty($state);
    }
    return 0;
}

sub Wattpilot_HasEligibleTelemetry($;$) {
    my ($hash, $nrg_bypass) = @_;
    $nrg_bypass //= 0;
    for my $owner (keys %WATTPILOT_TELEMETRY_OWNER_IDLE_GATE) {
        my $bypass = $owner eq $WATTPILOT_NRG_OWNER ? $nrg_bypass : 0;
        return 1 if Wattpilot_TelemetryOwnerEligible($hash, $owner, $bypass);
    }
    return 0;
}

sub Wattpilot_FlushTelemetryOwners($$;$) {
    my ($hash, $owners, $nrg_bypass) = @_;
    $nrg_bypass //= 0;
    my %wanted = map { $_ => 1 } @$owners;
    my $updated = 0;

    for my $owner (@WATTPILOT_TELEMETRY_OWNER_ORDER) {
        next if !$wanted{$owner};
        next if $owner eq $WATTPILOT_DIAGNOSTIC_OWNER
            && !Wattpilot_DiagnosticReadingsEnabled($hash);
        my $bypass = $owner eq $WATTPILOT_NRG_OWNER ? $nrg_bypass : 0;
        next if !Wattpilot_TelemetryOwnerEligible($hash, $owner, $bypass);

        my $state = Wattpilot_TelemetryGroupState($hash, $owner);
        if ($owner eq $WATTPILOT_ENERGY_OWNER) {
            Wattpilot_UpdateEnergyReadings($hash, $state);
        }
        elsif ($owner eq $WATTPILOT_NRG_OWNER) {
            Wattpilot_UpdateNrgReadings($hash, $state);
        }
        else {
            my $fields = $WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$owner};
            Wattpilot_UpdateScalarTelemetryReadings($hash, $state, $fields);
        }
        $updated = 1;
    }

    return $updated;
}

sub Wattpilot_FlushAllTelemetry($;$) {
    my ($hash, $nrg_bypass) = @_;
    return Wattpilot_FlushTelemetryOwners(
        $hash, \@WATTPILOT_TELEMETRY_OWNER_ORDER, $nrg_bypass);
}

sub Wattpilot_HasTelemetryInput($) {
    my ($status) = @_;
    return 1 if Wattpilot_HasValidNrg($status);
    return 1 if Wattpilot_HasEnergyTelemetry($status);
    for my $owner (@WATTPILOT_TELEMETRY_OWNER_ORDER) {
        next if $owner eq $WATTPILOT_ENERGY_OWNER;
        next if $owner eq $WATTPILOT_NRG_OWNER;
        my $fields = $WATTPILOT_SCALAR_TELEMETRY_BY_OWNER{$owner};
        return 1 if Wattpilot_HasScalarTelemetry($status, $fields);
    }
    return 0;
}

sub Wattpilot_ScheduleTelemetryFlush($) {
    my ($hash) = @_;
    my $clock = $hash->{helper}{telemetryClock};
    return undef if ref($clock) ne 'HASH' || !defined $clock->{nextFlush};
    my $delay = $clock->{nextFlush} - gettimeofday();
    $delay = 0 if $delay < 0;
    return Wattpilot_ScheduleTimer(
        $hash, 'telemetry_flush', $delay, 'Wattpilot_TelemetryFlush');
}

sub Wattpilot_StartTelemetryClock($$$) {
    my ($hash, $now, $interval) = @_;
    $hash->{helper}{telemetryClock} = {
        lastFlush => $now,
        nextFlush => $now + $interval,
        interval => $interval,
    };
    Wattpilot_ScheduleTelemetryFlush($hash);
}

sub Wattpilot_ResetTelemetryClock($) {
    my ($hash) = @_;
    Wattpilot_CancelTimer($hash, 'telemetry_flush');
    delete $hash->{helper}{telemetryClock};
}

sub Wattpilot_AdvanceTelemetryClock($$$) {
    my ($hash, $now, $interval) = @_;
    my $clock = $hash->{helper}{telemetryClock} //= {};
    my $next = $clock->{nextFlush} // $now;
    $next += $interval while $next <= $now;
    $clock->{lastFlush} = $now;
    $clock->{nextFlush} = $next;
    $clock->{interval} = $interval;
    Wattpilot_ScheduleTelemetryFlush($hash);
}

sub Wattpilot_FlushTelemetryClockIfDue($$$) {
    my ($hash, $now, $interval) = @_;
    my $clock = $hash->{helper}{telemetryClock};
    return 0 if ref($clock) ne 'HASH';
    return 0 if !defined($clock->{nextFlush}) || $now < $clock->{nextFlush};
    Wattpilot_CancelTimer($hash, 'telemetry_flush');
    Wattpilot_FlushAllTelemetry($hash);
    Wattpilot_AdvanceTelemetryClock($hash, $now, $interval);
    return 1;
}

sub Wattpilot_TelemetryFlush($) {
    my ($arg) = @_;
    my $ctx = ref($arg) eq 'HASH' && exists($arg->{hash}) ? $arg : undef;
    my $hash = $ctx ? $ctx->{hash} : $arg;
    return if !$ctx || !Wattpilot_TimerContextValid($hash, $ctx);
    Wattpilot_FinishTimer($hash, $ctx);

    my $interval = AttrVal($hash->{NAME}, 'interval', 0);
    if ($interval <= 0) {
        delete $hash->{helper}{telemetryClock};
        return;
    }

    if (Wattpilot_HasEligibleTelemetry($hash)) {
        readingsBeginUpdate($hash);
        Wattpilot_FlushAllTelemetry($hash);
        readingsEndUpdate($hash, 1);
    }

    my $now = gettimeofday();
    Wattpilot_AdvanceTelemetryClock($hash, $now, $interval);
}

sub Wattpilot_UpdateReadings($$;$) {
    my ($hash, $status, $message) = @_;
    return if ref($status) ne 'HASH';
    $message = { type => ($message // 'deltaStatus'), partial => 0 }
        if ref($message) ne 'HASH';
    $message->{type} //= 'deltaStatus';
    $message->{partial} = $message->{partial} ? 1 : 0;

    my $previous_car_state = $hash->{helper}{car_state};
    my $now = gettimeofday();

    delete $hash->{LAST_UPDATE};
    delete $hash->{LAST_BATTERY_UPDATE};
    delete $hash->{helper}{volatileTelemetryCache};

    Wattpilot_UpdateInternalStatus($hash, $status);
    Wattpilot_CacheTelemetry($hash, $status);

    readingsBeginUpdate($hash);
    Wattpilot_UpdateImmediateReadings($hash, $status);
    Wattpilot_HandleCarTransition($hash, $previous_car_state);

    my $idle_bypass = Wattpilot_NrgIdleBypass($hash, $status, $message);
    my $interval = AttrVal($hash->{NAME}, 'interval', 0);
    if ($interval <= 0) {
        Wattpilot_ResetTelemetryClock($hash);
        Wattpilot_FlushAllTelemetry($hash, $idle_bypass);
    } else {
        Wattpilot_FlushTelemetryClockIfDue($hash, $now, $interval);
        Wattpilot_FlushTelemetryOwners(
            $hash, [$WATTPILOT_NRG_OWNER], 1)
            if $idle_bypass;
    }

    if ($interval > 0
        && Wattpilot_HasTelemetryInput($status)
        && ref($hash->{helper}{telemetryClock}) ne 'HASH') {
        Wattpilot_FlushAllTelemetry($hash);
        Wattpilot_StartTelemetryClock($hash, $now, $interval);
    }

    readingsEndUpdate($hash, 1);
}

sub Wattpilot_SendAuth($$) {
    my ($hash, $json) = @_;
    my $name     = $hash->{NAME};
    my $password_result = Wattpilot_GetPassword($hash);
    my $serial   = $hash->{SERIAL};

    if ($password_result->{status} eq "error") {
        Log3 $name, 1, "Wattpilot ($name) - Cannot authenticate because credential storage is unavailable";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{credential_error});
        return;
    }
    my $password = $password_result->{status} eq "value" ? $password_result->{value} : undef;
    if (!$password || !defined($serial) || $serial !~ /^\d+$/) {
        Log3 $name, 1, "Wattpilot ($name) - Missing Password or Serial for authentication";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_config_missing});
        return;
    }

    if (!Wattpilot_IsJsonString($json->{token1}) || $json->{token1} eq ''
        || !Wattpilot_IsJsonString($json->{token2}) || $json->{token2} eq '') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication challenge has invalid tokens";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_challenge_invalid});
        return;
    }

    my $mode = eval { Wattpilot_GetAuthHashMode($hash, $json) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Authentication hash mode is unsupported";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_hash_unsupported});
        return;
    }
    $hash->{helper}{authHashMode} = $mode;

    my $password_hash = eval {
        Wattpilot_DerivePasswordHash($hash, $password, $serial);
    };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Password hash derivation failed for mode=$mode";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_hash_failed});
        return;
    }

    if (!Wattpilot_SetStoredPasswordHash($hash, $password_hash)) {
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_hash_store_failed});
        return;
    }

    my $token1 = $json->{token1};
    my $token2 = $json->{token2};

    my $random_bytes = eval { Wattpilot_SecureRandomBytes(16) };
    if ($@ || !defined($random_bytes) || length($random_bytes) != 16) {
        Log3 $name, 1, "Wattpilot ($name) - Secure authentication nonce generation failed";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_nonce_failed});
        return;
    }
    my $token3 = unpack 'H*', $random_bytes;

    my $hash1_input = $token1 . $password_hash;
    my $hash1       = sha256_hex($hash1_input);

    my $final_hash_input = $token3 . $token2 . $hash1;
    my $final_hash       = sha256_hex($final_hash_input);

    my $auth_response = {
        type   => "auth",
        token3 => $token3,
        hash   => $final_hash,
    };

    my $msg = JSON->new->canonical->encode($auth_response);
    Log3 $name, 3, "Wattpilot ($name) - Sending Auth Response using mode=$mode";
    Wattpilot_WriteJson($hash, $msg);
	$hash->{helper}{authPending} = 1;
	readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{auth_hash_mode}, $mode, 1);
}

sub Wattpilot_SecureRandomBytes($) {
    my ($length) = @_;
    die "Invalid secure random length" if !defined($length) || $length < 1;
    return urandom($length);
}

sub Wattpilot_BcryptPasswordHash($$$) {
    my ($hash, $password, $serial) = @_;
    my $name = $hash->{NAME};

    die "Crypt::Bcrypt not installed"
      unless defined &bcrypt;

    my $cost = AttrVal($name, "authHashCost", 8);

    my $password_sha256 = sha256_hex($password);          # wie im Python-Beispiel
    my $salt_raw        = Wattpilot_BcryptSerialRawSalt($serial, 16);

    my $full = bcrypt($password_sha256, '2a', $cost, $salt_raw);

    # Erwartet: $2a$08$<22-char-salt><31-char-hash>
    $full =~ /^\$2[abxy]\$\d\d\$[\.\/A-Za-z0-9]{22}([\.\/A-Za-z0-9]{31})$/
      or die "Unexpected bcrypt output format";

    return $1;
}

sub Wattpilot_DerivePasswordHash($$$) {
    my ($hash, $password, $serial) = @_;
    my $mode = $hash->{helper}{authHashMode};
    die "Authentication hash mode was not selected" if !defined($mode) || $mode eq "";

    if ($mode eq "pbkdf2") {
        my $h_args = { sha_size => 512 };
        my $pbkdf2_obj = Crypt::PBKDF2->new(
            hash_class => 'HMACSHA2',
            hash_args  => $h_args,
            iterations => 100000,
            output_len => 24
        );

        return $pbkdf2_obj->PBKDF2_base64($serial, $password);
    }

    elsif ($mode eq "bcrypt") {
        return Wattpilot_BcryptPasswordHash($hash, $password, $serial);
    }

    die "Unsupported authHash mode: $mode";
}



sub Wattpilot_BcryptSerialRawSalt($$) {
    my ($serial, $length) = @_;

    die "Check serial - should be digits only"
      unless defined($serial) && $serial =~ /^\d+$/;

    my @vals = map { ord($_) - ord('0') } split //, $serial;
    die "Serial too long" if scalar(@vals) > $length;

    my @bytes = ((0) x ($length - scalar(@vals)), @vals);
    return pack('C*', @bytes);   # genau 16 Byte
}



sub Wattpilot_CommandReadingsMayBePublished($) {
    my ($hash) = @_;
    return 0 if ref($hash) ne 'HASH';
    my $helper = ref($hash->{helper}) eq 'HASH' ? $hash->{helper} : {};
    return 0 if $helper->{undefined}
        || $helper->{deleting}
        || $helper->{shuttingDown};
    return 0 if !defined($hash->{NAME})
        || !defined($defs{$hash->{NAME}})
        || $defs{$hash->{NAME}} != $hash;
    return 1;
}

sub Wattpilot_AbortPendingRequests($$;$) {
    my ($hash, $reason, $publish) = @_;
    my $pending = $hash->{helper}{pendingRequests};
    return if ref($pending) ne 'HASH' || !keys %$pending;

    my ($request_id) = sort {
        ($pending->{$b}{sentAt} // 0) <=> ($pending->{$a}{sentAt} // 0)
            || $b <=> $a
    } keys %$pending;
    Wattpilot_CancelTimer($hash, 'command_timeout');
    delete $hash->{helper}{pendingRequests};
    $publish = Wattpilot_CommandReadingsMayBePublished($hash)
        if !defined $publish;
    Wattpilot_SetCommandReadings($hash, $request_id, 'failed', $reason)
        if $publish;
}

sub Wattpilot_AbortPendingRequestsForReconnect($) {
    my ($hash) = @_;
    return Wattpilot_AbortPendingRequests($hash, 'reconnect requested');
}

sub Wattpilot_ManualReconnect($) {
    my ($hash) = @_;

    return "Wattpilot device is not active"
        if !Wattpilot_IsRuntimeActive($hash);

    my $password_result = Wattpilot_GetPassword($hash);
    return "Wattpilot credential storage is unavailable"
        if $password_result->{status} eq 'error';
    return "Wattpilot password is missing"
        if $password_result->{status} ne 'value'
        || $password_result->{value} eq '';

    Wattpilot_AbortPendingRequestsForReconnect($hash);
    delete $hash->{helper}{timeoutRetryUsed};
    delete $hash->{helper}{pendingReconnectAfterOpen};
    Wattpilot_StopIdleRefresh($hash);
    delete $hash->{helper}{idleRefreshAttempted};
    Wattpilot_InvalidateSession($hash, undef, 'reconnect requested');
    Wattpilot_ApplyConfiguredState($hash, 0);
    return undef;
}


sub Wattpilot_PvBatteryUsage($) {
    my ($name) = @_;
    return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} "
        . "<chargeAboveSoC|dischargeEnabled|dischargeUntilSoC|"
        . "dischargeTimeLimitEnabled|dischargeStartTime|dischargeStopTime> "
        . "<value>";
}

sub Wattpilot_SetPvBattery($@) {
    my ($hash, @args) = @_;
    my $name = $hash->{NAME};
    return Wattpilot_PvBatteryUsage($name) if @args != 2;

    my ($setting, $value) = @args;
    return Wattpilot_PvBatteryUsage($name)
        if !defined($setting) || !defined($value);
    if ($setting eq 'chargeAboveSoC') {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} chargeAboveSoC <0-100>"
            if $value !~ /^(?:0|[1-9]\d?|100)$/;
        return Wattpilot_SendSecure($hash, 'fam', int($value));
    }
    if ($setting eq 'dischargeEnabled') {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} dischargeEnabled <0|1>"
            if $value !~ /^(?:0|1)$/;
        return Wattpilot_SendSecure(
            $hash, 'pdte', $value eq '1' ? JSON::true : JSON::false);
    }
    if ($setting eq 'dischargeUntilSoC') {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} dischargeUntilSoC <0-100>"
            if $value !~ /^(?:0|[1-9]\d?|100)$/;
        return Wattpilot_SendSecure($hash, 'pdt', int($value));
    }
    if ($setting eq 'dischargeTimeLimitEnabled') {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} dischargeTimeLimitEnabled <0|1>"
            if $value !~ /^(?:0|1)$/;
        return Wattpilot_SendSecure(
            $hash, 'pdle', $value eq '1' ? JSON::true : JSON::false);
    }
    if ($setting eq 'dischargeStartTime') {
        my $seconds = Wattpilot_ParseClockTimeToSeconds($value, 0);
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} dischargeStartTime <HH:MM>"
            if !defined $seconds;
        return Wattpilot_SendSecure($hash, 'pdls', int($seconds));
    }
    if ($setting eq 'dischargeStopTime') {
        my $seconds = Wattpilot_ParseClockTimeToSeconds($value, 1);
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_battery} dischargeStopTime <HH:MM|24:00>"
            if !defined $seconds;
        return Wattpilot_SendSecure($hash, 'pdlo', int($seconds));
    }
    return Wattpilot_PvBatteryUsage($name);
}

sub Wattpilot_GroupedCommandUsage($$;$) {
    my ($name, $group_key, $setting) = @_;
    my $group_name = $WATTPILOT_COMMAND_NAME{$group_key};
    if (defined $setting
        && exists $WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$setting}) {
        my $usage = $WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$setting}{usage};
        return "Usage: set $name $group_name $setting $usage";
    }
    my $settings = join('|', map { $_->[0] }
        @{$WATTPILOT_GROUPED_COMMAND_DEFINITION{$group_key}});
    return "Usage: set $name $group_name <$settings> <value>";
}

sub Wattpilot_SetGroupedCommand($$@) {
    my ($hash, $group_key, @args) = @_;
    my $name = $hash->{NAME};
    return Wattpilot_GroupedCommandUsage($name, $group_key)
        if @args != 2;

    my ($setting, $value) = @args;
    return Wattpilot_GroupedCommandUsage($name, $group_key)
        if !defined($setting) || !defined($value)
        || !exists $WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$setting};

    my $schema = $WATTPILOT_GROUPED_COMMAND_SCHEMA{$group_key}{$setting};
    my $protocol_value = Wattpilot_ParseSetCommandValue(
        $schema->{parser}, $value);
    return Wattpilot_GroupedCommandUsage($name, $group_key, $setting)
        if !defined $protocol_value;
    return Wattpilot_SendSecure(
        $hash, $schema->{protocolKey}, $protocol_value);
}

sub Wattpilot_EffectiveChargingCurrentMaximum($) {
    my ($hash) = @_;
    return $WATTPILOT_CHARGING_CURRENT_MAXIMUM
        if ref($hash) ne 'HASH'
        || ref($hash->{helper}) ne 'HASH'
        || !$hash->{helper}{maximumCurrentLimitReceived};

    my $reading = $WATTPILOT_READING_NAME{maximum_current_limit};
    return $WATTPILOT_CHARGING_CURRENT_MAXIMUM
        if ref($hash->{READINGS}) ne 'HASH'
        || ref($hash->{READINGS}{$reading}) ne 'HASH';
    my $value = $hash->{READINGS}{$reading}{VAL};
    return $WATTPILOT_CHARGING_CURRENT_MAXIMUM
        if !defined($value)
        || ref($value)
        || $value !~ /^\d+$/
        || $value < $WATTPILOT_CHARGING_CURRENT_MINIMUM
        || $value > $WATTPILOT_CHARGING_CURRENT_MAXIMUM;
    return int($value);
}

sub Wattpilot_ParseSetCommandValue($$;$) {
    my ($parser, $value, $hash) = @_;
    return undef if !defined $value;

    return int($WATTPILOT_FORCE_COMMAND_VALUE{$value})
        if $parser eq 'force_state'
        && exists $WATTPILOT_FORCE_COMMAND_VALUE{$value};
    if ($parser eq 'charging_current') {
        my $maximum = Wattpilot_EffectiveChargingCurrentMaximum($hash);
        return int($value)
            if $value =~ /^\d+$/
            && $value >= $WATTPILOT_CHARGING_CURRENT_MINIMUM
            && $value <= $maximum;
        return undef;
    }
    return $WATTPILOT_CHARGING_MODE_VALUE{$value}
        if $parser eq 'charging_mode'
        && exists $WATTPILOT_CHARGING_MODE_VALUE{$value};
    return Wattpilot_ParseFiniteNonNegativeNumber($value)
        if $parser eq 'nonnegative_number';
    return $value eq '1' ? JSON::true : JSON::false
        if $parser eq 'boolean' && $value =~ /^(?:0|1)$/;
    return $WATTPILOT_PV_CONTROL_PREFERENCE_VALUE{$value}
        if $parser eq 'pv_control'
        && exists $WATTPILOT_PV_CONTROL_PREFERENCE_VALUE{$value};
    return $WATTPILOT_PHASE_SWITCH_MODE_VALUE{$value}
        if $parser eq 'phase_switch'
        && exists $WATTPILOT_PHASE_SWITCH_MODE_VALUE{$value};
    return Wattpilot_ParseSecondsToMilliseconds($value)
        if $parser eq 'seconds';
    return Wattpilot_ParseClockTimeToSeconds($value, 0)
        if $parser eq 'clock';
    die "Unknown Wattpilot Set parser: $parser"
        if $parser !~ /^(?:force_state|charging_current|charging_mode|nonnegative_number|boolean|pv_control|phase_switch|seconds|clock)$/;
    return undef;
}

sub Wattpilot_SetOptions(;$) {
    my ($hash) = @_;
    return join(' ', map {
        my $schema = $WATTPILOT_COMMAND_SCHEMA{$_->[0]};
        my $widget = $schema->{widget};
        $widget = 'slider,' . $WATTPILOT_CHARGING_CURRENT_MINIMUM
            . ',1,' . Wattpilot_EffectiveChargingCurrentMaximum($hash)
            if $_->[0] eq 'charging_current';
        $schema->{name}
            . ($widget eq 'none' ? '' : ':' . $widget);
    } @WATTPILOT_COMMAND_DEFINITION);
}

sub Wattpilot_SetUsage($$$) {
    my ($hash, $name, $schema) = @_;
    my $usage = $schema->{usage};
    $usage = '<' . $WATTPILOT_CHARGING_CURRENT_MINIMUM . '-'
        . Wattpilot_EffectiveChargingCurrentMaximum($hash) . '>'
        if $schema->{parser} eq 'charging_current';
    return "Usage: set $name $schema->{name} $usage";
}

sub Wattpilot_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $cmd = $a[1] // '';
    my $val = $a[2];
    my $set_options = Wattpilot_SetOptions($hash);

    return "Unknown argument $cmd, choose one of $set_options"
        if $cmd eq '?';
    return "Device is disabled" if Wattpilot_IsDisabled($name);

    if ($cmd eq $WATTPILOT_COMMAND_NAME{reconnect}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{reconnect}"
            if @a != 2;
        return Wattpilot_ManualReconnect($hash);
    }
    if (exists $WATTPILOT_GROUPED_COMMAND_BY_NAME{$cmd}) {
        return Wattpilot_SetGroupedCommand(
            $hash, $WATTPILOT_GROUPED_COMMAND_BY_NAME{$cmd}, @a[2 .. $#a]);
    }
    if ($cmd eq $WATTPILOT_COMMAND_NAME{pv_battery}) {
        return Wattpilot_SetPvBattery($hash, @a[2 .. $#a]);
    }
    if ($cmd eq $WATTPILOT_COMMAND_NAME{password}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{password} <secret>"
            if @a != 3 || !defined($val) || $val eq '';

        my $password_err = Wattpilot_StoreNewPassword($hash, $val);
        return $password_err if defined $password_err;

        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_InvalidateSession($hash, undef, 'credentials changed');
        Wattpilot_ApplyConfiguredState($hash, 1);
        return undef;
    }

    my $schema = $WATTPILOT_COMMAND_BY_NAME{$cmd};
    if ($schema && $schema->{parser} ne 'special') {
        return Wattpilot_SetUsage($hash, $name, $schema)
            if @a != 3 || !defined $val;
        my $protocol_value = Wattpilot_ParseSetCommandValue(
            $schema->{parser}, $val, $hash);
        if (!defined $protocol_value) {
            return "Unknown mode $val"
                if $schema->{invalid} eq 'unknown_mode';
            return Wattpilot_SetUsage($hash, $name, $schema);
        }
        return Wattpilot_SendSecure(
            $hash, $schema->{protocolKey}, $protocol_value);
    }

    return "Unknown argument $cmd, choose one of $set_options";
}

sub Wattpilot_SendSecure($$$) {
    my ($hash, $key, $val) = @_;
    my $name = $hash->{NAME};

    return "Device is disabled" if Wattpilot_IsDisabled($name);
    return "Wattpilot is disconnected" if !DevIo_IsOpen($hash);
    return "Wattpilot is not authenticated" if !$hash->{helper}{authenticated}
        || (($hash->{STATE} // '') ne $WATTPILOT_LIFECYCLE_STATE{connected}
            && (($hash->{READINGS}{$WATTPILOT_READING_NAME{state}}{VAL} // '') ne $WATTPILOT_LIFECYCLE_STATE{connected}));

    my $stored_hash_result = Wattpilot_GetPasswordHash($hash);
    if ($stored_hash_result->{status} eq "error") {
        Log3 $name, 1, "Wattpilot ($name) - Cannot send command because credential storage is unavailable";
        readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{credential_error}, 1);
        return "Wattpilot credential storage is unavailable";
    }
    my $stored_hash = $stored_hash_result->{status} eq "value" ? $stored_hash_result->{value} : undef;
    if (!$stored_hash) {
        Log3 $name, 1, "Wattpilot ($name) - Cannot send command because the signing key is missing";
        return "Wattpilot signing key is missing; reconnect and authenticate first";
    }

    Wattpilot_CleanupPendingRequests($hash);
    my $pending = $hash->{helper}{pendingRequests} //= {};
    return "Too many Wattpilot commands are awaiting responses"
        if scalar(keys %$pending) >= $WATTPILOT_MAX_PENDING_REQUESTS;

    $hash->{msg_id} = 0 if !defined $hash->{msg_id};
    my $requestId;
    do {
        $hash->{msg_id}++;
        $requestId = $hash->{msg_id};
    } while (exists $pending->{$requestId});
    $requestId = int($hash->{msg_id});

    my $payload = {
        type => "setValue",
        requestId => $requestId,
        key => $key,
        value => $val
    };
    my $payload_str = JSON->new->canonical->encode($payload);
    my $hmac = Digest::SHA::hmac_sha256_hex($payload_str, $stored_hash);
    my $secure_msg = {
        type => "securedMsg",
        data => $payload_str,
        requestId => "${requestId}sm",
        hmac => $hmac
    };

    my $final_msg = JSON->new->canonical->encode($secure_msg);
    Log3 $name, 3, "Wattpilot ($name) - Sending secured command key=$key requestId=$requestId";
    Wattpilot_WriteJson($hash, $final_msg);
    $pending->{$requestId} = { key => $key, value => $val, sentAt => gettimeofday() };
    Wattpilot_SetCommandReadings($hash, $requestId, 'pending', 'none');
    Wattpilot_ScheduleRequestTimeout($hash);
    return undef;
}

sub Wattpilot_SetCommandReadings($$$$) {
    my ($hash, $request_id, $status, $error) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{last_command_request_id}, $request_id);
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{last_command_status}, $status);
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{last_command_error}, $error);
    readingsEndUpdate($hash, 1);
}

sub Wattpilot_NormalizeRequestId($) {
    my ($request_id) = @_;
    if (Wattpilot_IsJsonInteger($request_id)) {
        return undef if $request_id < 0;
        return int($request_id);
    }
    return undef if !Wattpilot_IsJsonString($request_id);
    my $normalized = $request_id;
    $normalized =~ s/sm$//;
    return $normalized =~ /^\d+$/ ? int($normalized) : undef;
}

sub Wattpilot_ClearCommandState($;$) {
    my ($hash, $reason) = @_;
    my $pending = $hash->{helper}{pendingRequests};
    if (ref($pending) eq 'HASH' && keys %$pending) {
        $reason //= Wattpilot_CommandReadingsMayBePublished($hash)
            ? 'session replaced'
            : 'session removed';
        Wattpilot_AbortPendingRequests($hash, $reason);
    } else {
        Wattpilot_CancelTimer($hash, 'command_timeout');
        delete $hash->{helper}{pendingRequests};
    }
    delete $hash->{helper}{authenticated};
    delete $hash->{helper}{authPending};
    delete $hash->{helper}{authHashMode};
}

sub Wattpilot_ClearConnectionState($;$) {
    my ($hash, $command_reason) = @_;
    Wattpilot_ClearCommandState($hash, $command_reason);
    delete $hash->{helper}{deviceType};
    delete $hash->{helper}{protocol};
    delete $hash->{helper}{jsonBuffer};
    delete $hash->{helper}{volatileTelemetryCache};
    delete $hash->{helper}{telemetryClock};
    if (ref($hash->{helper}{telemetryPublication}) eq 'HASH') {
        for my $state (values %{$hash->{helper}{telemetryPublication}}) {
            next if ref($state) ne 'HASH';
            $state->{cache} = {};
            $state->{dirty} = {};
        }
    }
}

sub Wattpilot_AbortAuthentication($$) {
    my ($hash, $state) = @_;
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash, 'authentication aborted');
    delete $hash->{helper}{openInFlight};
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $state, 1);
    DevIo_CloseDev($hash);
}

sub Wattpilot_ScheduleRequestTimeout($) {
    my ($hash) = @_;
    Wattpilot_CancelTimer($hash, 'command_timeout');
    my $pending = $hash->{helper}{pendingRequests} // {};
    return if !keys %$pending;
    my ($next) = sort { $a <=> $b }
        map { $pending->{$_}{sentAt} + $WATTPILOT_REQUEST_TIMEOUT } keys %$pending;
    Wattpilot_ScheduleTimer(
        $hash, 'command_timeout', $next - gettimeofday(),
        'Wattpilot_RequestTimeout');
}

sub Wattpilot_CleanupPendingRequests($) {
    my ($hash) = @_;
    my $pending = $hash->{helper}{pendingRequests} // {};
    my $now = gettimeofday();
    for my $request_id (sort { $pending->{$a}{sentAt} <=> $pending->{$b}{sentAt} } keys %$pending) {
        next if $pending->{$request_id}{sentAt} + $WATTPILOT_REQUEST_TIMEOUT > $now;
        my $key = $pending->{$request_id}{key};
        delete $pending->{$request_id};
        Log3 $hash->{NAME}, 1,
            "Wattpilot ($hash->{NAME}) - Command response timeout key=$key requestId=$request_id";
        Wattpilot_SetCommandReadings($hash, $request_id, 'timeout', 'response timeout');
    }
    delete $hash->{helper}{pendingRequests} if !keys %$pending;
    Wattpilot_ScheduleRequestTimeout($hash);
}

sub Wattpilot_RequestTimeout($) {
    my ($arg) = @_;
    my $ctx = ref($arg) eq 'HASH' && exists($arg->{hash}) ? $arg : undef;
    my $hash = $ctx ? $ctx->{hash} : $arg;
    if ($ctx) {
        return if !Wattpilot_TimerContextValid($hash, $ctx);
        Wattpilot_FinishTimer($hash, $ctx);
    }
    Wattpilot_CleanupPendingRequests($hash);
}

sub Wattpilot_HandleResponse($$) {
    my ($hash, $json) = @_;
    my $request_id = Wattpilot_NormalizeRequestId($json->{requestId});
    Wattpilot_CleanupPendingRequests($hash);
    my $pending = $hash->{helper}{pendingRequests} // {};
    if (!defined($request_id) || !exists $pending->{$request_id}) {
        Log3 $hash->{NAME}, 2,
            "Wattpilot ($hash->{NAME}) - Ignoring unmatched command response";
        return;
    }

    my $request = delete $pending->{$request_id};
    delete $hash->{helper}{pendingRequests} if !keys %$pending;
    Wattpilot_ScheduleRequestTimeout($hash);

    if (!exists $json->{success}) {
        Log3 $hash->{NAME}, 1,
            "Wattpilot ($hash->{NAME}) - Malformed command response requestId=$request_id";
        Wattpilot_SetCommandReadings($hash, $request_id, 'failed', 'malformed response');
        return;
    }

    if ($json->{success}) {
        Wattpilot_UpdateReadings($hash, $json->{status}, 'response')
            if ref($json->{status}) eq 'HASH';
        Wattpilot_SetCommandReadings($hash, $request_id, 'success', 'none');
        return;
    }

    Log3 $hash->{NAME}, 1,
        "Wattpilot ($hash->{NAME}) - Command rejected key=$request->{key} requestId=$request_id";
    Wattpilot_SetCommandReadings($hash, $request_id, 'failed', "device rejected $request->{key}");
}

sub Wattpilot_Ready($) {
    my ($hash) = @_;
    return 0 if !Wattpilot_IsRuntimeActive($hash);
    return 0 if ($hash->{STATE} // '') ne $WATTPILOT_LIFECYCLE_STATE{disconnected}
        && ($hash->{STATE} // '') ne $WATTPILOT_LIFECYCLE_STATE{connection_failed};
    Wattpilot_ClearConnectionState($hash, 'connection lost');
    return 0 if defined($hash->{helper}{timers}{connect});
    return Wattpilot_StartOpen($hash, 1) ? 1 : 0;
}

sub Wattpilot_Attr(@) {
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};

    if ($cmd eq "set") {
        my $validation_error = Wattpilot_ValidateAttribute($attrName, $attrVal);
        return $validation_error if defined $validation_error;
    }

    if($attrName eq "disable") {
        if($cmd eq "set" && $attrVal eq "1") {
            Wattpilot_InvalidateSession($hash, undef, 'device disabled');
            RemoveInternalTimer($hash, 'Wattpilot_Connect');
            RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
            delete $hash->{helper}{pendingReconnectAfterOpen};
            readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disabled}, 1);
        } elsif($cmd eq "del" || $attrVal eq "0") {
            delete $hash->{helper}{timeoutRetryUsed};
            Wattpilot_InvalidateSession($hash, undef, 'session replaced');
            Wattpilot_ApplyConfiguredState($hash, 1, 0);
        }
    }

    if (($attrName eq "authHash" || $attrName eq "authHashCost")
        && ($cmd eq "set" || $cmd eq "del")) {
        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_InvalidateSession($hash, undef, 'credentials changed');
        RemoveInternalTimer($hash, 'Wattpilot_Connect');
        RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
        my $hash_error = Wattpilot_InvalidateStoredPasswordHash($hash);

        if (defined $hash_error) {
            delete $hash->{helper}{pendingReconnectAfterOpen};
            readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{credential_error}, 1);
        } else {
            Wattpilot_ApplyConfiguredState($hash, 1);
        }
    }

    if ($attrName eq "diagnosticReadings"
        && ($cmd eq "del" || ($cmd eq "set" && $attrVal eq "0"))) {
        Wattpilot_ClearOptionalDiagnosticReadings($hash);
    }

    if ($attrName eq "rawJsonLog" && $cmd eq "set" && $attrVal eq "1") {
        Log3 $name, 1, "Wattpilot ($name) - WARNING: raw JSON logging was requested; it becomes active only with verbose=5 and may then contain sensitive authentication, network, device, and operational data";
    }
    if ($attrName eq "verbose" && $cmd eq "set" && defined($attrVal) && $attrVal >= 5
        && AttrVal($name, "rawJsonLog", 0) eq "1") {
        Log3 $name, 1, "Wattpilot ($name) - WARNING: raw JSON logging is active and may contain sensitive authentication, network, device, and operational data";
    }

    if ($attrName eq "interval" && ($cmd eq "set" || $cmd eq "del")) {
        my $previous_interval = 0 + AttrVal($name, "interval", 0);
        Wattpilot_ResetTelemetryClock($hash);
        my $effective_interval = $cmd eq "set" ? 0 + $attrVal : 0;
        if ($effective_interval <= 0 && Wattpilot_HasEligibleTelemetry($hash)) {
            readingsBeginUpdate($hash);
            Wattpilot_FlushAllTelemetry($hash);
            readingsEndUpdate($hash, 1);
        } elsif ($previous_interval > 0
            && $effective_interval > 0
            && Wattpilot_HasDirtyTelemetry($hash)) {
            Wattpilot_StartTelemetryClock(
                $hash, gettimeofday(), $effective_interval);
        }
    }

    return undef;
}

sub Wattpilot_ValidateAttribute($$) {
    my ($attr_name, $attr_value) = @_;

    my %boolean_attribute = map { $_ => 1 } qw(
        update_while_idle diagnosticReadings disable rawJsonLog
    );
    if ($boolean_attribute{$attr_name}) {
        return "$attr_name must be 0 or 1"
            if !defined($attr_value) || $attr_value !~ /^(?:0|1)$/;
        return undef;
    }

    if ($attr_name eq "interval") {
        return "interval must be an integer from 0 to 300"
            if !defined($attr_value)
            || $attr_value !~ /^\d+$/
            || $attr_value < 0
            || $attr_value > 300;
        return undef;
    }

    if ($attr_name eq "authHash") {
        return "authHash must be one of auto, pbkdf2, bcrypt"
            if !defined($attr_value)
            || $attr_value !~ /^(?:auto|pbkdf2|bcrypt)$/;
        return undef;
    }

    if ($attr_name eq "authHashCost") {
        return "authHashCost must be an integer from 4 to 14"
            if !defined($attr_value)
            || $attr_value !~ /^\d+$/
            || $attr_value < 4
            || $attr_value > 14;
        return undef;
    }

    return undef;
}

sub Wattpilot_IsDisabled($) {
    my ($name) = @_;
    return AttrVal($name, "disable", 0);
}


sub Wattpilot_GetAuthHashMode($$) {
    my ($hash, $json) = @_;
    my $name = $hash->{NAME};

    my $attr_mode = AttrVal($name, "authHash", "auto");

    return $attr_mode if $attr_mode eq "pbkdf2" || $attr_mode eq "bcrypt";
    die "Unsupported authHash attribute" if $attr_mode ne "auto";

    if (!exists($json->{hash})) {
        return "pbkdf2"
            if ($hash->{helper}{deviceType} // '') eq 'wattpilot'
                && ($hash->{helper}{protocol} // -1) == 2;
        die "Missing auth hash outside legacy Wattpilot protocol 2";
    }
    die "Invalid announced auth hash" if !Wattpilot_IsJsonString($json->{hash});
    my $device_mode = lc($json->{hash});
    return "bcrypt" if ($device_mode eq "bcrypt");
    return "pbkdf2" if ($device_mode eq "pbkdf2");
    die "Unsupported announced auth hash";
}

sub Wattpilot_GetPassword {
    my ($hash) = @_;
    return Wattpilot_GetStoredSecret($hash, "password");
}

sub Wattpilot_GetPasswordHash {
    my ($hash) = @_;
    return Wattpilot_GetStoredSecret($hash, "passwordhash");
}

sub Wattpilot_SetStoredPasswordHash {
    my ($hash, $password_hash) = @_;
    my $name = $hash->{NAME};
    my $key  = Wattpilot_SecretKey($hash, "passwordhash");

    my $err = setKeyValue($key, $password_hash);
    if (defined $err) {
        Log3 $name, 1, "Wattpilot ($name) - failed to store password hash";
        return 0;
    }

    return 1;
}

sub Wattpilot_InvalidateStoredPasswordHash {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $key = Wattpilot_SecretKey($hash, "passwordhash");
    my ($read_err, $old_value) = getKeyValue($key);
    if (defined $read_err) {
        Log3 $name, 1, "Wattpilot ($name) - failed to inspect stored password hash before authHash change";
        return "failed to inspect stored password hash";
    }
    return undef if !defined $old_value;

    my $delete_err = setKeyValue($key, undef);
    if (defined $delete_err) {
        Log3 $name, 1, "Wattpilot ($name) - failed to invalidate stored password hash";
        return "failed to invalidate stored password hash";
    }
    return undef;
}

sub Wattpilot_DeleteStoredSecrets {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my @keys = eval {
        map { Wattpilot_SecretKey($hash, $_) } qw(password passwordhash);
    };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - failed to determine stable credential keys before deletion";
        return "Wattpilot credential deletion failed before changes were made";
    }

    my %snapshot;
    for my $key (@keys) {
        my ($err, $value) = getKeyValue($key);
        if (defined $err) {
            Log3 $name, 1, "Wattpilot ($name) - failed to snapshot stable credentials before deletion";
            return "Wattpilot credential deletion failed before changes were made";
        }
        $snapshot{$key} = $value;
    }

    my @deleted;
    for my $key (@keys) {
        next if !defined $snapshot{$key};
        my $err = setKeyValue($key, undef);
        if (defined $err) {
            my @rollback_failures;
            for my $deleted_key (reverse @deleted) {
                my $rollback_err = setKeyValue($deleted_key, $snapshot{$deleted_key});
                push @rollback_failures, $deleted_key if defined $rollback_err;
            }
            Log3 $name, 1, "Wattpilot ($name) - stable credential deletion failed; rollback " .
                (@rollback_failures ? "incomplete" : "completed");
            return "Wattpilot credential deletion failed" .
                (@rollback_failures
                    ? "; rollback incomplete for " . scalar(@rollback_failures) . " key(s)"
                    : "; prior values restored");
        }
        push @deleted, $key;
    }
    return undef;
}

sub Wattpilot_StoreNewPassword($$) {
    my ($hash, $new_password) = @_;
    my $name = $hash->{NAME};
    my ($stable_password, $stable_hash) = eval {
        (Wattpilot_SecretKey($hash, "password"),
         Wattpilot_SecretKey($hash, "passwordhash"));
    };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - failed to determine stable credential keys";
        return "failed to determine stable credential key";
    }

    my %old_value;
    for my $key ($stable_password, $stable_hash) {
        my ($err, $value) = getKeyValue($key);
        if (defined $err) {
            Log3 $name, 1, "Wattpilot ($name) - could not inspect stable credential storage before password update";
            return "failed to inspect existing credentials; password unchanged";
        }
        $old_value{$key} = $value;
    }

    my @changed;
    my $rollback = sub {
        my @rollback_failures;
        for my $key (reverse @changed) {
            my $err = setKeyValue($key, $old_value{$key});
            push @rollback_failures, $key if defined $err;
        }
        return @rollback_failures ? "; credential rollback incomplete" : "";
    };

    if (defined $old_value{$stable_hash}) {
        my $delete_err = setKeyValue($stable_hash, undef);
        if (defined $delete_err) {
            Log3 $name, 1, "Wattpilot ($name) - failed to invalidate stable password hash; password unchanged";
            return "failed to invalidate stored password hash; password unchanged";
        }
        push @changed, $stable_hash;
    }

    my $store_err = setKeyValue($stable_password, $new_password);
    if (defined $store_err) {
        my $rollback_error = $rollback->();
        Log3 $name, 1, "Wattpilot ($name) - failed to store new stable password";
        return "failed to store new password; previous credentials restored$rollback_error";
    }
    return undef;
}

sub Wattpilot_SecretKey($$) {
    my ($hash, $suffix) = @_;
    my $fuuid = $hash->{FUUID};
    die "Wattpilot credential storage requires FUUID" if !defined($fuuid) || $fuuid eq "";
    return "Wattpilot_" . $fuuid . "_" . $suffix;
}

sub Wattpilot_CredentialValue($) {
    return { status => "value", value => $_[0] };
}

sub Wattpilot_CredentialAbsent() {
    return { status => "absent" };
}

sub Wattpilot_CredentialError($) {
    return { status => "error", error => $_[0] };
}

sub Wattpilot_GetStoredSecret {
    my ($hash, $suffix) = @_;
    my $name = $hash->{NAME};
    my $key = eval { Wattpilot_SecretKey($hash, $suffix) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - stable credential key is unavailable";
        return Wattpilot_CredentialError("stable credential key unavailable");
    }

    my ($err, $value) = getKeyValue($key);
    if (defined $err) {
        Log3 $name, 1, "Wattpilot ($name) - could not read stored $suffix";
        return Wattpilot_CredentialError("stable credential read failed");
    }
    return defined($value)
        ? Wattpilot_CredentialValue($value)
        : Wattpilot_CredentialAbsent();
}

sub Wattpilot_LogRawJson($$$) {
    my ($hash, $direction, $payload) = @_;
    my $name = $hash->{NAME};
    return if AttrVal($name, "rawJsonLog", 0) ne "1";
    return if AttrVal($name, "verbose", 3) < 5;
    Log3 $name, 5, "Wattpilot ($name) - RAW JSON $direction: $payload";
}

sub Wattpilot_WriteJson($$) {
    my ($hash, $payload) = @_;
    my $name = $hash->{NAME};
    Wattpilot_LogRawJson($hash, "OUT", $payload);

    # DevIo_SimpleWrite logs the complete payload at level 5 before writing.
    # Dynamically lowering only this device's verbose value for this synchronous
    # call suppresses that duplicate leak and restores the exact prior state
    # immediately afterwards. Type 2 passes unpacked text; DevIo determines
    # the WebSocket text/binary opcode from the connection and $hash->{binary}.
    my $effective_verbose = AttrVal($name, "verbose", 3);
    local $attr{$name}{verbose} = $effective_verbose > 4 ? 4 : $effective_verbose;
    return DevIo_SimpleWrite($hash, $payload, 2);
}

1;

# Beginn der Commandref
=pod
=item device
=item summary Controls Fronius Wattpilot Wallbox
=item summary_DE Steuert die Fronius Wattpilot Wallbox

=begin html

<a name="Wattpilot"></a>
<h3>Wattpilot</h3>
<ul>
  <li>This module controls a Fronius Wattpilot wallbox through the local WebSocket API.</li>
  <li>The public 2.0 interface uses English <code>lowerCamelCase</code> reading and set-command names.</li>
  <li>The device Internal <code>VERSION</code> reports the module version. Firmware reported by the wallbox remains separate in <code>firmwareVersion</code>.</li>
  <li>Decoded input is limited to 1 MiB and at most 256 concatenated JSON documents. Known fields are type-checked, omitted partial-update fields remain unchanged, and missing values are never converted to zero.</li>
  <li>The empirically observed Flex startup message types <code>clearInverters</code>, <code>updateInverter</code>, and <code>clearSmips</code> are deliberately ignored because the module does not use their payloads. They remain visible in the level-4 received-type trace but do not produce a level-3 unsupported-type warning. Other unsupported JSON message types are ignored without logging their payload. A type name is shown only when it is a bounded, log-safe ASCII token; otherwise it is reported as <code>redacted</code>.</li>
  <br>

  <a name="Wattpilot-breaking"></a>
  <b>Breaking change from 1.x</b>
  <ul>
    <li>Version 2.0 requires a fresh FHEM definition and a new <code>set &lt;name&gt; password &lt;secret&gt;</code>.</li>
    <li>There are no aliases, compatibility attributes, or automatic migrations for old public reading and set-command names.</li>
    <li>Old readings in an existing device are not deleted automatically. Adapt DOIFs, notifies, plots, DbLog/Influx queries, dashboards, scripts, and other consumers manually.</li>
    <li>Old name-based credential keys are neither read nor removed. Released 1.6.x versions are the final line with that upgrade support.</li>
  </ul>
  <p>Version 2.0.7 classifies every public reading. Stored or user-selectable configuration values use the exact <code>config</code> prefix; Set-command names remain unchanged. There are no compatibility aliases, duplicate readings, automatic reading cleanup, DbLog migration, or transition period. Old reading entries may remain stale in an existing FHEM device after reload and must be removed or avoided through a fresh definition.</p>
  <p>Version 2.0.9 consistently abbreviates state of charge as <code>SoC</code> in public reading names and renames <code>configPvBatteryDischargeEndTime</code> to <code>configPvBatteryDischargeStopTime</code>. No old-name aliases or migration are provided.</p>
  <p>Version 2.0.10 advertises <code>reconnect:noArg</code> in the Set command list, returns the normal command list for <code>set &lt;name&gt; ?</code> even while the device is disabled, and rejects surplus arguments for every single-value Set command. Actual Set operations remain blocked while disabled.</p>
  <p>Version 2.1.0 fixes FHEM <code>modify</code>/<code>defmod</code> lifecycle transitions, preserves top-level <code>fullStatus.partial</code> metadata, enforces exact JSON field types and safe clock validation, and removes the no-op <code>debug</code> and <code>defaultAmp</code> attributes. Changed definitions reconnect once only after successful validation; invalid modifications leave the active session unchanged.</p>
  <p>Version 2.1.1 keeps separate latest-value caches and dirty fields for energy, electrical, and stationary-battery telemetry, but publishes all eligible dirty groups on one shared interval clock and in one FHEM reading transaction. Energy is queued only when its formatted public value changes; discrete status/diagnostic readings publish immediately only when their public value changes.</p>
  <p>Version 2.1.2 formats public measured and calculated values with exactly two decimal places and trailing zeroes. Rounded negative zero is published as positive zero. Percentages, integral settings and codes, clocks, and durations remain explicit exceptions; the then-public stationary-battery percentage intentionally kept one decimal place.</p>
  <p>Version 2.1.3 derives incoming status validation, immediate public formatting, Set discovery, ordinary Set parsing, protocol keys, and Usage text from two small declarative inventories. Special lifecycle, authentication, grouped <code>pvBattery</code>, <code>password</code>, <code>reconnect</code>, telemetry-cache, and car-transition behavior remains explicit. Public names, payloads, cadence, and reading semantics are unchanged.</p>
  <p>Version 2.1.4 replaces the seven individual phase-switch and minimum-charging Set commands with the grouped <code>phaseSwitch</code> and <code>minimumCharging</code> commands. Protocol keys, public units, validation, and confirmed <code>config...</code> readings remain unchanged. The removed individual Set names have no aliases.</p>
  <p>Version 2.1.5 limits <code>chargingCurrent</code> to <code>6..min(32, configMaximumCurrentLimit)</code> after a usable <code>ama</code> value has been received for the current device hash. Missing, stale, malformed, non-integer, or out-of-range values keep the compatibility range <code>6..32</code>. FHEMWEB receives the same dynamic upper bound; rejected commands are not sent and <code>configChargingCurrent</code> remains device-confirmed. The same release also preserves exactly one reconnect owner after ordinary EOF or a WebSocket Close frame, treats the first valid authenticated partial or complete status as initialization, finalizes pending commands on session invalidation, applies the bounded Charging-to-Idle electrical refresh with both <code>update_while_idle</code> values, and flushes already queued eligible telemetry when <code>interval</code> becomes <code>0</code>.</p>
  <p>Version 2.1.6 replaces the shared telemetry timer immediately when <code>interval</code> changes between positive values while telemetry is dirty. The queued values remain rate-limited and publish at the new boundary even without another status message. Repeated changes keep exactly one timer, stale callbacks are harmless, idle-gated electrical and battery data remains passive, and a positive change with no dirty telemetry keeps the clock lazy.</p>
  <p>Version 2.1.7 adds exact device identity and separate hello/status protocol readings, interval-controlled <code>deviceRebootCount</code> and <code>uptime</code>, and fourteen optional scalar field-research readings behind <code>diagnosticReadings</code>. The <code>rbt</code> value is interpreted as milliseconds from the maintainer live-device observation, divided by 1,000, and rendered as cumulative hours and minutes in <code>H:MM</code>. The former standalone stationary-battery SOC/power readings are replaced by raw <code>diag_fbuf_akkuSOC</code> and <code>diag_fbuf_pAkku</code>. Optional diagnostics are removed immediately when disabled and make no semantic, unit, sign, aggregation, or enum claims.</p>
  <table class="block wide">
    <tr><th>Reading through 2.0.6</th><th>Reading from 2.0.7</th></tr>
    <tr><td><code>forceState</code></td><td><code>configForceState</code></td></tr>
    <tr><td><code>chargingCurrent</code></td><td><code>configChargingCurrent</code></td></tr>
    <tr><td><code>chargingMode</code></td><td><code>configChargingMode</code></td></tr>
    <tr><td><code>maximumCurrentLimit</code></td><td><code>configMaximumCurrentLimit</code></td></tr>
    <tr><td><code>minimumChargingCurrent</code></td><td><code>configMinimumChargingCurrent</code></td></tr>
    <tr><td><code>pvSurplusStartPower</code></td><td><code>configPvSurplusStartPower</code></td></tr>
    <tr><td><code>pvSurplusEnabled</code></td><td><code>configPvSurplusEnabled</code></td></tr>
    <tr><td><code>zeroFeedInEnabled</code></td><td><code>configZeroFeedInEnabled</code></td></tr>
    <tr><td><code>pvControlPreference</code></td><td><code>configPvControlPreference</code></td></tr>
    <tr><td><code>phaseSwitchMode</code></td><td><code>configPhaseSwitchMode</code></td></tr>
    <tr><td><code>threePhaseSwitchPower</code></td><td><code>configThreePhaseSwitchPower</code></td></tr>
    <tr><td><code>phaseSwitchDelay</code></td><td><code>configPhaseSwitchDelay</code></td></tr>
    <tr><td><code>minimumPhaseSwitchInterval</code></td><td><code>configMinimumPhaseSwitchInterval</code></td></tr>
    <tr><td><code>minimumChargeTime</code></td><td><code>configMinimumChargeTime</code></td></tr>
    <tr><td><code>chargingPauseAllowed</code></td><td><code>configChargingPauseAllowed</code></td></tr>
    <tr><td><code>minimumChargingPauseDuration</code></td><td><code>configMinimumChargingPauseDuration</code></td></tr>
    <tr><td><code>minimumChargingInterval</code></td><td><code>configMinimumChargingInterval</code></td></tr>
    <tr><td><code>nextTripTime</code></td><td><code>configNextTripTime</code></td></tr>
  </table>
  <!-- BEGIN 2.0 migration names -->
  <table class="block wide">
    <tr><th>Type</th><th>1.x name</th><th>2.0 name</th></tr>
    <tr><td>Reading</td><td><code>state</code></td><td><code>state</code></td></tr>
    <tr><td>Reading</td><td><code>version</code></td><td><code>firmwareVersion</code></td></tr>
    <tr><td>Reading</td><td><code>authHashMode</code></td><td><code>authHashMode</code></td></tr>
    <tr><td>Reading</td><td><code>CarState</code></td><td><code>carState</code></td></tr>
    <tr><td>Reading</td><td><code>Laden_starten</code></td><td><code>configForceState</code></td></tr>
    <tr><td>Reading</td><td><code>Strom</code></td><td><code>configChargingCurrent</code></td></tr>
    <tr><td>Reading</td><td><code>Modus</code></td><td><code>configChargingMode</code></td></tr>
    <tr><td>Reading</td><td><code>Zeit_NextTrip</code></td><td><code>configNextTripTime</code></td></tr>
    <tr><td>Reading</td><td><code>EnergyTotal</code></td><td><code>energyTotal</code></td></tr>
    <tr><td>Reading</td><td><code>Energie_seit_Anstecken</code></td><td><code>energySincePlugIn</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L1</code></td><td><code>voltageL1</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L2</code></td><td><code>voltageL2</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L3</code></td><td><code>voltageL3</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L1</code></td><td><code>currentL1</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L2</code></td><td><code>currentL2</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L3</code></td><td><code>currentL3</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L1</code></td><td><code>powerL1</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L2</code></td><td><code>powerL2</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L3</code></td><td><code>powerL3</code></td></tr>
    <tr><td>Reading</td><td><code>power</code></td><td><code>power</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandRequestId</code></td><td><code>lastCommandRequestId</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandStatus</code></td><td><code>lastCommandStatus</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandError</code></td><td><code>lastCommandError</code></td></tr>
    <tr><td>Set</td><td><code>Password &lt;secret&gt;</code></td><td><code>password &lt;secret&gt;</code></td></tr>
    <tr><td>Set</td><td><code>Strom &lt;6..32&gt;</code></td><td><code>chargingCurrent &lt;6..32&gt;</code></td></tr>
    <tr><td>Set</td><td><code>Laden_starten Start|Stop</code></td><td><code>forceState neutral|off|on</code></td></tr>
    <tr><td>Set</td><td><code>Modus Default|Eco|NextTrip</code></td><td><code>chargingMode default|eco|nextTrip</code></td></tr>
    <tr><td>Set</td><td><code>Zeit_NextTrip HH:MM</code></td><td><code>nextTripTime HH:MM</code></td></tr>
  </table>
  <!-- END 2.0 migration names -->
  <br>

  <a name="Wattpilot-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Wattpilot &lt;IP-Address&gt; [&lt;Serial&gt;]</code>
    <br><br>
    Defines a Wattpilot device.<br>
    <b>&lt;IP-Address&gt;</b>: Local IP address of the Wattpilot.<br>
    <b>&lt;Serial&gt;</b>: Optional digits-only serial number. If omitted, the module uses the value from the device <code>hello</code> message.<br>
    <br>
    Set the password separately with <code>set &lt;name&gt; password &lt;secret&gt;</code>.<br>
    A successful FHEM <code>modify</code> or <code>defmod</code> endpoint/serial change terminates the old session and schedules exactly one reconnect. Invalid modifications are rejected before connection, timer, credential, reading, or helper state changes.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; password &lt;secret&gt;</code><br>
        Stores the password under stable FUUID-based keys and starts a controlled reconnect. Rename does not rewrite credentials. Password replacement and deletion use two-key transactions with rollback. Storage errors remain distinguishable from a missing password.</li>
    <li><code>set &lt;name&gt; chargingCurrent &lt;6-effectiveMaximum&gt;</code><br>
        Sends protocol key <code>amp</code>. The effective upper bound is <code>min(32, configMaximumCurrentLimit)</code> after the current device hash has received a usable integer <code>ama</code> value from 6 through 32. Until then, or when the reading is missing, malformed, non-integer, or outside that range, the compatibility range remains 6 through 32. FHEMWEB uses the same dynamic slider maximum. Rejected values produce no protocol command, and the setter does not update <code>configChargingCurrent</code> optimistically.</li>
    <li><code>set &lt;name&gt; forceState &lt;neutral|off|on&gt;</code><br>
        Sends <code>frc=0</code>, <code>frc=1</code>, or <code>frc=2</code>.</li>
    <li><code>set &lt;name&gt; chargingMode &lt;default|eco|nextTrip&gt;</code><br>
        Sends <code>lmo=3</code>, <code>lmo=4</code>, or <code>lmo=5</code>.</li>
    <li><code>set &lt;name&gt; pvSurplusStartPower &lt;watts&gt;</code><br>
        Sends the non-negative finite numeric value through protocol key <code>fst</code>. The module applies no unverified upper limit; device rejection is reported through the command-status readings. The public unit is watts.</li>
    <li><code>set &lt;name&gt; pvSurplusEnabled &lt;0|1&gt;</code><br>
        Sends the JSON boolean protocol field <code>fup</code>.</li>
    <li><code>set &lt;name&gt; zeroFeedInEnabled &lt;0|1&gt;</code><br>
        Sends the JSON boolean protocol field <code>fzf</code>.</li>
    <li><code>set &lt;name&gt; pvControlPreference &lt;preferFromGrid|default|preferToGrid&gt;</code><br>
        Sends <code>frm=0</code>, <code>frm=1</code>, or <code>frm=2</code>.</li>
    <li><code>set &lt;name&gt; phaseSwitch &lt;setting&gt; &lt;value&gt;</code><br>
        Groups the phase-switch settings under one top-level command:<br>
        <code>mode &lt;auto|force1|force3&gt;</code> &rarr; <code>psm=0|1|2</code>;<br>
        <code>delay &lt;seconds&gt;</code> &rarr; <code>mpwst</code> as exact whole milliseconds;<br>
        <code>minInterval &lt;seconds&gt;</code> &rarr; <code>mptwt</code> as exact whole milliseconds;<br>
        <code>threePhasePower &lt;watts&gt;</code> &rarr; the non-negative finite value through <code>spl3</code>.</li>
    <li><code>set &lt;name&gt; minimumCharging &lt;setting&gt; &lt;seconds&gt;</code><br>
        Groups the minimum-charging timing settings under one top-level command:<br>
        <code>duration</code> &rarr; <code>fmt</code>;<br>
        <code>interval</code> &rarr; <code>mci</code>;<br>
        <code>pauseDuration</code> &rarr; <code>mcpd</code>.<br>
        Each public value is converted exactly to whole protocol milliseconds.</li>
    <li><code>set &lt;name&gt; chargingPauseAllowed &lt;0|1&gt;</code><br>
        Sends the JSON boolean protocol field <code>fap</code>.</li>
    <li><code>set &lt;name&gt; pvBattery &lt;setting&gt; &lt;value&gt;</code><br>
        Groups all stationary-PV-battery configuration writes under one top-level command. Supported subcommands are:<br>
        <code>chargeAboveSoC &lt;0-100&gt;</code> &rarr; <code>fam</code> as an integer percentage;<br>
        <code>dischargeEnabled &lt;0|1&gt;</code> &rarr; <code>pdte</code> as a JSON boolean;<br>
        <code>dischargeUntilSoC &lt;0-100&gt;</code> &rarr; <code>pdt</code> as an integer percentage;<br>
        <code>dischargeTimeLimitEnabled &lt;0|1&gt;</code> &rarr; <code>pdle</code> as a JSON boolean;<br>
        <code>dischargeStartTime &lt;HH:MM&gt;</code> &rarr; <code>pdls</code> as seconds after midnight;<br>
        <code>dischargeStopTime &lt;HH:MM|24:00&gt;</code> &rarr; <code>pdlo</code> as seconds after midnight.<br>
        No reading is changed optimistically; only returned device status confirms a value. All six grouped setters were changed individually on a Wattpilot Flex Home 22 C6 running firmware 43.4, confirmed through device-supplied status/readback, and restored to their original values. Deliberate device rejection, persistence across reboot, and other firmware/model variants remain unverified.</li>
    <li><code>set &lt;name&gt; reconnect</code><br>
        Performs a local controlled WebSocket reconnect without sending a Wattpilot protocol command. Session-owned timers, authentication state, partial JSON, and pending secured commands are invalidated; operational readings and configuration remain intact. Pending commands terminate with <code>lastCommandStatus=failed</code> and <code>lastCommandError=reconnect requested</code>. The command is not a <code>fullStatus</code> request; any initial status after login is device-supplied.</li>
    <li><code>set &lt;name&gt; nextTripTime &lt;HH:MM&gt;</code><br>
        Requires exactly two-digit <code>HH:MM</code> and sends protocol key <code>ftt</code> as seconds after midnight.</li>
  </ul>
  <br>

  <a name="Wattpilot-get"></a>
  <b>Get</b>
  <ul>
    <li>No dedicated <code>get</code> commands are implemented.</li>
  </ul>
  <br>

  <a name="Wattpilot-attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Values outside the documented choices and ranges are rejected before FHEM stores them.</li>
    <li><code>interval &lt;seconds&gt;</code><br>
        Rate-limits cumulative energy, electrical <code>nrg</code>, device-health values, <code>uptime</code>, and enabled optional diagnostics on one shared clock. Every data owner retains only its newest valid values and its own dirty fields; each tick publishes all eligible dirty owners in one FHEM reading transaction. Input from one owner never publishes or advances another owner. Energy becomes dirty only when the formatted public value actually differs from the published reading. <code>0</code> disables rate limiting and publishes eligible dirty values immediately. Changing a positive value to <code>0</code>, or deleting the attribute, cancels the previous timer and immediately flushes every currently eligible dirty owner in one transaction; idle-gated electrical, uptime, and diagnostic data remains dirty/passive. Invalid or incomplete input neither becomes dirty nor moves the shared clock. Configuration readings remain immediate, and discrete status/diagnostic readings are immediate-on-change. The first valid authenticated <code>fullStatus</code> or <code>deltaStatus</code>, including <code>partial=true</code>, completes initialization; partial controls snapshot completeness only. <code>deltaStatus</code> supplies device-side field filtering, but no official per-field Flex update frequency is inferred from it because no public Fronius local-WebSocket specification for such frequencies is evidenced.</li>
    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> keeps ordinary electrical <code>nrg</code>, <code>uptime</code>, and enabled optional diagnostics passive while not charging; <code>1</code> admits real incoming idle values from those owners on the shared telemetry clock. With either value, charging-to-idle starts one bounded electrical refresh: one valid device-supplied <code>nrg</code> in the transition message or grace window may bypass the clock, otherwise at most one controlled reconnect is used. Changing the attribute during the episode neither duplicates nor cancels it. The attribute does not gate energy: <code>eto</code>/<code>wh</code> are queued only when their formatted public values actually change, so identical snapshots do not renew timestamps. No device emission frequency is claimed, no polling command is invented, and no zero value is synthesized.</li>
    <li><code>diagnosticReadings &lt;0|1&gt;</code><br>
        <code>0</code> is the default and immediately deletes all optional <code>diag_...</code> readings and clears their cache/dirty state; deleting the attribute has the same effect. <code>1</code> enables the fourteen raw scalar field-research readings on the normal <code>interval</code>, eligible while charging or with <code>update_while_idle=1</code>. JSON numbers are formatted with exactly two decimal places, strings remain unchanged, and JSON booleans become <code>0|1</code>; missing, <code>null</code>, object, array, or invalid values preserve the previous reading.</li>
    <li><code>disable &lt;0|1&gt;</code><br>
        Disables the module and closes the connection when set to <code>1</code>.</li>
    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Exact JSON is logged only with both <code>rawJsonLog=1</code> and <code>verbose=5</code>. This can expose sensitive authentication, network, device, and operational data. DevIo/HttpUtils core logs may still contain endpoint details at high verbosity.</li>
    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Selects authentication hashing. <code>auto</code> accepts announced PBKDF2 or bcrypt; a missing hash selects PBKDF2 only for the evidenced predecessor <code>devicetype=wattpilot</code>, protocol-2 profile. Changing the attribute invalidates the current session and schedules one fresh login when possible.</li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt cost for newly derived authentication hashes. Changing it invalidates the current session.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Lifecycle state: <code>disabled</code>, <code>passwordMissing</code>, <code>credentialError</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connectionFailed</code>, <code>authFailed</code>, <code>authTimeout</code>, <code>initializationTimeout</code>, <code>authSequenceInvalid</code>, <code>authConfigMissing</code>, <code>authChallengeInvalid</code>, <code>authHashUnsupported</code>, <code>authHashFailed</code>, <code>authHashStoreFailed</code>, or <code>authNonceFailed</code>.</li>
    <li><code>firmwareVersion</code><br>Firmware/version string reported by the device <code>hello</code> message; identical reconnect values do not renew the reading.</li>
    <li><code>deviceType</code>, <code>deviceModel</code>, <code>deviceSubType</code>, <code>deviceVariant</code><br>Exact valid values from <code>typ</code>, <code>grp</code>, <code>styp</code>, and <code>var</code>. No commercial-model mapping is invented.</li>
    <li><code>helloProtocol</code>, <code>statusProtocol</code><br>Raw non-negative integers from <code>hello.protocol</code> and <code>status.proto</code>. They remain separate and no relationship is assumed.</li>
    <li><code>authHashMode</code><br>Effective authentication mode: <code>pbkdf2</code> or <code>bcrypt</code>.</li>
    <li><code>carState</code><br><code>unknown</code>, <code>idle</code>, <code>charging</code>, <code>waitingForCar</code>, <code>complete</code>, <code>error</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>configForceState</code><br><code>neutral</code>, <code>off</code>, <code>on</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>configChargingCurrent</code><br>Configured/requested charging current; interpreted as amperes.</li>
    <li><code>configChargingMode</code><br><code>default</code>, <code>eco</code>, <code>nextTrip</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>chargingAllowed</code><br>Boolean protocol field <code>alw</code>, exposed as <code>0</code> or <code>1</code>. A pinned Wattpilot-specific source describes it as the current charging permission; the Flex capture confirms only the boolean field and value shape.</li>
    <li><code>chargingDecisionCode</code>, <code>chargingDecisionInternalCode</code><br>Unmodified integer values from <code>modelStatus</code> and <code>msi</code>.</li>
    <li><code>chargingDecision</code>, <code>chargingDecisionInternal</code><br>Compatibility text mappings for the two raw codes. Unknown values are exposed as <code>unknown:&lt;code&gt;</code>. The mapping is derived from the pinned official go-e <code>modelStatus</code> enum and Wattpilot-specific third-party evidence for <code>msi</code>; it is not an official Fronius Flex specification. The pinned third-party source calls <code>msi</code> an internal decision variant, but the exact relationship, evaluation order, precedence, and any role of <code>cpDisabledRequest</code> are not confirmed for Wattpilot Flex. In particular, the module does not claim that <code>modelStatus</code> is necessarily the final/effective decision or that <code>msi</code> is necessarily a pre-CP decision. If the values differ, treat them as two device-supplied diagnostic values; do not infer a causal chain from the module documentation.</li>
    <li><code>errorCode</code><br>Raw integer value from <code>err</code>; no error enum is assumed.</li>
    <li><code>configMaximumCurrentLimit</code>, <code>temperatureCurrentLimit</code>, <code>configMinimumChargingCurrent</code><br>Raw integer values from <code>ama</code>, <code>amt</code>, and <code>mca</code>. Their current-limit interpretation and ampere unit come from pinned third-party Wattpilot evidence and are not independently proven by the sanitized Flex capture.</li>
    <li><code>configPvSurplusStartPower</code><br>Non-negative finite numeric value from <code>fst</code>, exposed in watts with exactly two decimal places. Pinned official go-e API metadata and pinned Wattpilot-specific evidence describe it as the PV-surplus start power and as writable; the observed Wattpilot Flex 43.4 value is <code>1400</code>. This evidence supports the compatibility mapping but is not an official Fronius Flex API specification.</li>
    <li><code>configPvSurplusEnabled</code>, <code>configZeroFeedInEnabled</code>, <code>configChargingPauseAllowed</code><br>Boolean fields <code>fup</code>, <code>fzf</code>, and <code>fap</code>, exposed as <code>0</code> or <code>1</code>.</li>
    <li><code>configPvControlPreference</code><br><code>preferFromGrid</code>, <code>default</code>, <code>preferToGrid</code>, or <code>unknown:&lt;raw-value&gt;</code> from <code>frm</code>.</li>
    <li><code>configPhaseSwitchMode</code><br><code>auto</code>, <code>force1</code>, <code>force3</code>, or <code>unknown:&lt;raw-value&gt;</code> from <code>psm</code>.</li>
    <li><code>configThreePhaseSwitchPower</code><br>Non-negative finite numeric value from <code>spl3</code>, exposed in watts with exactly two decimal places.</li>
    <li><code>configPhaseSwitchDelay</code>, <code>configMinimumPhaseSwitchInterval</code>, <code>configMinimumChargeTime</code>, <code>configMinimumChargingPauseDuration</code>, <code>configMinimumChargingInterval</code><br>Non-negative finite values from <code>mpwst</code>, <code>mptwt</code>, <code>fmt</code>, <code>mcpd</code>, and <code>mci</code>, converted from protocol milliseconds to public seconds.</li>
    <li><code>diag_fbuf_akkuSOC</code>, <code>diag_fbuf_pAkku</code><br>Optional raw scalar field-research readings from the two stationary-battery-related protocol fields. Numeric values are rounded to exactly two decimal places without scaling; strings remain unchanged and booleans become <code>0|1</code>. <code>diag_fbuf_pAkku</code> and <code>diag_pvopt_averagePAkku</code> are distinct fields; their exact distinction, aggregation, unit, and sign remain unconfirmed.</li>
    <li><code>pvBatteryModeCode</code><br>Unmodified non-negative integer code from <code>fbuf_akkuMode</code>. No text enum is invented.</li>
    <li><code>deviceRebootCount</code><br>Raw non-negative <code>rbc</code> value on the normal interval without idle gating. Exact semantics remain unverified.</li>
    <li><code>uptime</code><br>Non-negative <code>rbt</code> millisecond value interpreted from the maintainer live-device observation as time since device start, divided by 1,000, and rendered as cumulative hours and minutes in <code>H:MM</code>. Remaining seconds and milliseconds are discarded; publication uses the normal interval while charging or with <code>update_while_idle=1</code>.</li>
    <li><code>diag_fbuf_pGrid</code>, <code>diag_fbuf_pPv</code>, <code>diag_pvopt_averagePGrid</code>, <code>diag_pvopt_averagePPv</code>, <code>diag_pvopt_averagePAkku</code>, <code>diag_pvopt_averagePOhmpilot</code>, <code>diag_pvopt_deltaP</code>, <code>diag_pvopt_deltaA</code>, <code>diag_pvopt_specialCase</code>, <code>diag_fbuf_pAcTotal</code>, <code>diag_fbuf_ohmpilotState</code>, <code>diag_fbuf_ohmpilotTemperature</code><br>Optional raw scalar field-research readings enabled by <code>diagnosticReadings=1</code>. Their original protocol wording is retained after <code>diag_</code>; no meaning, unit, sign, aggregation, or enum is claimed.</li>
    <li><code>configPvBatteryChargeAboveSoC</code><br>App setting <code>Charge above</code> from <code>fam</code>, accepted as a finite percentage from <code>0</code> through <code>100</code>. The grouped setter accepts whole percentages only.</li>
    <li><code>configPvBatteryDischargeEnabled</code><br>App switch <code>Discharge until</code> from <code>pdte</code>, exposed as <code>0</code> or <code>1</code>.</li>
    <li><code>configPvBatteryDischargeUntilSoC</code><br>App setting <code>State of charge SoC</code> from <code>pdt</code>, accepted as a finite percentage from <code>0</code> through <code>100</code>. The grouped setter accepts whole percentages only.</li>
    <li><code>configPvBatteryDischargeTimeLimitEnabled</code><br>App switch <code>Limit discharging time</code> from <code>pdle</code>, exposed as <code>0</code> or <code>1</code>.</li>
    <li><code>configPvBatteryDischargeStartTime</code>, <code>configPvBatteryDischargeStopTime</code><br>App start/stop times from <code>pdls</code> and <code>pdlo</code>, converted from whole seconds after midnight to <code>HH:MM</code>. The six configuration mappings were matched to simultaneous Solar.wattpilot app values on one Flex Home 22 C6 running firmware 43.4. All six grouped setters were subsequently accepted on the same model/firmware, reflected in device-supplied status/readback, and restored to their original values. Deliberate device rejection, persistence across reboot, and broader firmware/model scope remain unverified.</li>
    <li>All 24 configuration readings update immediately after valid device confirmation. Identity and discrete status/diagnostic readings update immediately only when their public value changes. Energy, electrical <code>nrg</code>, device-health values, <code>uptime</code>, and enabled optional diagnostics keep separate caches and dirty fields but share one <code>interval</code> clock; one group never republishes stale values from another. <code>pvBatteryModeCode</code> is discrete status, not battery telemetry. Missing, <code>null</code>, type-invalid, or incomplete fields preserve readings and histories.</li>
  </ul>
  <p><b>Note on aWATTar:</b> aWATTar is a provider or tariff name associated with dynamic electricity prices, not a technical abbreviation introduced by this module. Names containing <code>Awattar</code> in the imported go-e enum refer to price-controlled charging decisions. <code>Fallback</code> denotes the default outcome of a decision branch when no more specific charging reason applies; it does not automatically indicate a technical fault. The exact trigger and full semantics of these codes are not confirmed for Wattpilot Flex. In particular, <code>notChargingBecauseFallbackAwattar</code> alone does not prove that an aWATTar tariff is enabled.</p>
  <p><b>Charging-decision compatibility mapping</b></p>
  <table class="block wide">
    <tr><th>Code</th><th>Text value</th></tr>
      <tr><td><code>0</code></td><td><code>notChargingBecauseNoChargeCtrlData</code></td></tr>
      <tr><td><code>1</code></td><td><code>notChargingBecauseOvertemperature</code></td></tr>
      <tr><td><code>2</code></td><td><code>notChargingBecauseAccessControlWait</code></td></tr>
      <tr><td><code>3</code></td><td><code>chargingBecauseForceStateOn</code></td></tr>
      <tr><td><code>4</code></td><td><code>notChargingBecauseForceStateOff</code></td></tr>
      <tr><td><code>5</code></td><td><code>notChargingBecauseScheduler</code></td></tr>
      <tr><td><code>6</code></td><td><code>notChargingBecauseEnergyLimit</code></td></tr>
      <tr><td><code>7</code></td><td><code>chargingBecauseAwattarPriceLow</code></td></tr>
      <tr><td><code>8</code></td><td><code>chargingBecauseAutomaticStopTestLadung</code></td></tr>
      <tr><td><code>9</code></td><td><code>chargingBecauseAutomaticStopNotEnoughTime</code></td></tr>
      <tr><td><code>10</code></td><td><code>chargingBecauseAutomaticStop</code></td></tr>
      <tr><td><code>11</code></td><td><code>chargingBecauseAutomaticStopNoClock</code></td></tr>
      <tr><td><code>12</code></td><td><code>chargingBecausePvSurplus</code></td></tr>
      <tr><td><code>13</code></td><td><code>chargingBecauseFallbackGoEDefault</code></td></tr>
      <tr><td><code>14</code></td><td><code>chargingBecauseFallbackGoEScheduler</code></td></tr>
      <tr><td><code>15</code></td><td><code>chargingBecauseFallbackDefault</code></td></tr>
      <tr><td><code>16</code></td><td><code>notChargingBecauseFallbackGoEAwattar</code></td></tr>
      <tr><td><code>17</code></td><td><code>notChargingBecauseFallbackAwattar</code></td></tr>
      <tr><td><code>18</code></td><td><code>notChargingBecauseFallbackAutomaticStop</code></td></tr>
      <tr><td><code>19</code></td><td><code>chargingBecauseCarCompatibilityKeepAlive</code></td></tr>
      <tr><td><code>20</code></td><td><code>chargingBecauseChargePauseNotAllowed</code></td></tr>
      <tr><td><code>22</code></td><td><code>notChargingBecauseSimulateUnplugging</code></td></tr>
      <tr><td><code>23</code></td><td><code>notChargingBecausePhaseSwitch</code></td></tr>
      <tr><td><code>24</code></td><td><code>notChargingBecauseMinPauseDuration</code></td></tr>
      <tr><td><code>26</code></td><td><code>notChargingBecauseError</code></td></tr>
      <tr><td><code>27</code></td><td><code>notChargingBecauseLoadManagementDoesntWant</code></td></tr>
      <tr><td><code>28</code></td><td><code>notChargingBecauseOcppDoesntWant</code></td></tr>
      <tr><td><code>29</code></td><td><code>notChargingBecauseReconnectDelay</code></td></tr>
      <tr><td><code>30</code></td><td><code>notChargingBecauseAdapterBlocking</code></td></tr>
      <tr><td><code>31</code></td><td><code>notChargingBecauseUnderfrequencyControl</code></td></tr>
      <tr><td><code>32</code></td><td><code>notChargingBecauseUnbalancedLoad</code></td></tr>
      <tr><td><code>33</code></td><td><code>chargingBecauseDischargingPvBattery</code></td></tr>
      <tr><td><code>34</code></td><td><code>notChargingBecauseGridMonitoring</code></td></tr>
      <tr><td><code>35</code></td><td><code>notChargingBecauseOcppFallback</code></td></tr>
  </table>
  <ul>
    <li><code>configNextTripTime</code><br>Protocol value rendered as <code>HH:MM</code>; interpreted as seconds after midnight.</li>
    <li><code>energyTotal</code><br>Protocol <code>eto</code> divided by 1000 and formatted with two decimals. The Wh-to-kWh interpretation is implementation evidence, not proven by the sanitized Flex capture.</li>
    <li><code>energySincePlugIn</code><br>Protocol <code>wh</code> formatted with two decimals; interpreted as Wh.</li>
    <li>The two energy readings use the shared telemetry clock but a separate latest-value cache. They are queued only when the formatted public value changes; identical <code>fullStatus</code>, <code>deltaStatus</code>, or response values do not renew timestamps or create events. They do not consume or release electrical, uptime, or diagnostic data.</li>
    <li><code>voltageL1</code>, <code>voltageL2</code>, <code>voltageL3</code><br>Values from <code>nrg[0..2]</code>, interpreted as volts.</li>
    <li><code>currentL1</code>, <code>currentL2</code>, <code>currentL3</code><br>Values from <code>nrg[4..6]</code>, interpreted as amperes.</li>
    <li><code>powerL1</code>, <code>powerL2</code>, <code>powerL3</code><br>Values from <code>nrg[7..9]</code>, interpreted as watts.</li>
    <li><code>power</code><br>Value from <code>nrg[11]</code>, interpreted as total watts.</li>
    <li><code>lastCommandRequestId</code>, <code>lastCommandStatus</code>, <code>lastCommandError</code><br>
        Correlation and result of the most recent secured command. Status values are <code>pending</code>, <code>success</code>, <code>failed</code>, or <code>timeout</code>. If a live session is invalidated before a response arrives, all pending requests and their timeout are cleared and the newest request becomes <code>failed</code> with a stable redacted reason such as <code>connection lost</code>, <code>device disabled</code>, <code>credentials changed</code>, <code>authentication aborted</code>, <code>lifecycle timeout</code>, <code>reconnect requested</code>, <code>definition changed</code>, or <code>session replaced</code>. Undefine and shutdown suppress new diagnostic events.</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="Wattpilot"></a>
<h3>Wattpilot</h3>
<ul>
  <li>Dieses Modul steuert eine Fronius-Wattpilot-Wallbox über die lokale WebSocket-API.</li>
  <li>Die öffentliche 2.0-Schnittstelle verwendet englische Reading- und Set-Namen in <code>lowerCamelCase</code>.</li>
  <li>Das Device-Internal <code>VERSION</code> zeigt die Modulversion. Die von der Wallbox gemeldete Firmware bleibt separat im Reading <code>firmwareVersion</code>.</li>
  <li>Decodierte Eingaben sind auf 1 MiB und höchstens 256 verkettete JSON-Dokumente begrenzt. Bekannte Felder werden typgeprüft, ausgelassene Teil-Updates bleiben unverändert und fehlende Werte werden niemals als Null behandelt.</li>
  <li>Die empirisch beobachteten Flex-Startnachrichtentypen <code>clearInverters</code>, <code>updateInverter</code> und <code>clearSmips</code> werden bewusst ignoriert, weil das Modul ihre Payloads nicht verwendet. Sie bleiben im Level-4-Empfangs-Trace sichtbar, erzeugen aber keine Level-3-Warnung wegen eines nicht unterstützten Typs. Andere nicht unterstützte JSON-Nachrichtentypen werden ohne Protokollierung ihres Payloads ignoriert. Ein Typname wird nur als begrenztes, logsicheres ASCII-Token ausgegeben; andernfalls erscheint <code>redacted</code>.</li>
  <br>

  <a name="Wattpilot-breaking"></a>
  <b>Inkompatible Änderung gegenüber 1.x</b>
  <ul>
    <li>Version 2.0 erfordert eine frische FHEM-Definition und ein neues <code>set &lt;name&gt; password &lt;secret&gt;</code>.</li>
    <li>Für alte öffentliche Reading- und Set-Namen gibt es keine Aliase, Kompatibilitätsattribute oder automatische Migration.</li>
    <li>Alte Readings eines bestehenden Devices werden nicht automatisch gelöscht. DOIFs, Notifies, Plots, DbLog-/Influx-Abfragen, Dashboards, Skripte und weitere Verbraucher müssen manuell angepasst werden.</li>
    <li>Alte namensbasierte Credential-Schlüssel werden weder gelesen noch gelöscht. Veröffentlichte 1.6.x-Versionen sind die letzte Linie mit dieser Upgrade-Unterstützung.</li>
  </ul>
  <p>Version 2.0.7 klassifiziert jedes öffentliche Reading. Gespeicherte oder vom Benutzer auswählbare Konfigurationswerte verwenden das feste Präfix <code>config</code>; die Namen der Set-Befehle bleiben unverändert. Es gibt keine Kompatibilitätsaliase, parallelen Readings, automatische Reading-Bereinigung, DbLog-Migration oder Übergangsfrist. Alte Reading-Einträge können nach einem Reload in einem bestehenden FHEM-Device als nicht mehr aktualisierte Werte erhalten bleiben und müssen manuell entfernt oder durch eine frische Definition vermieden werden.</p>
  <p>Version 2.0.9 kürzt den Ladezustand in öffentlichen Reading-Namen einheitlich als <code>SoC</code> ab und benennt <code>configPvBatteryDischargeEndTime</code> in <code>configPvBatteryDischargeStopTime</code> um. Es gibt keine Aliase oder Migration für die alten Namen.</p>
  <p>Version 2.0.10 weist <code>reconnect:noArg</code> in der Set-Befehlsliste aus, liefert die normale Befehlsliste für <code>set &lt;name&gt; ?</code> auch bei deaktiviertem Device und lehnt überzählige Argumente bei allen einwertigen Set-Befehlen ab. Tatsächliche Set-Befehle bleiben im deaktivierten Zustand gesperrt.</p>
  <p>Version 2.1.0 korrigiert die FHEM-Lebenszyklen von <code>modify</code>/<code>defmod</code>, erhält das Top-Level-Metadatum <code>fullStatus.partial</code>, erzwingt exakte JSON-Feldtypen und sichere Uhrzeitvalidierung und entfernt die wirkungslosen Attribute <code>debug</code> und <code>defaultAmp</code>. Geänderte Definitionen verbinden sich erst nach vollständiger erfolgreicher Prüfung genau einmal neu; ungültige Änderungen lassen die aktive Sitzung unverändert.</p>
  <p>Version 2.1.1 behält getrennte Latest-Value-Caches und Dirty-Felder für Energie-, elektrische und stationäre Speichertelemetrie, veröffentlicht aber alle zulässigen geänderten Gruppen über einen gemeinsamen Intervalltakt und eine FHEM-Reading-Transaktion. Energie wird nur bei einer tatsächlichen Änderung des formatierten öffentlichen Werts vorgemerkt; diskrete Status-/Diagnosewerte erscheinen sofort nur bei tatsächlicher Änderung.</p>
  <p>Version 2.1.2 formatiert öffentliche Mess- und Rechenwerte mit genau zwei Nachkommastellen einschließlich nachgestellter Nullen. Gerundetes negatives Null wird als positives Null ausgegeben. Prozentwerte, ganzzahlige Einstellungen und Codes, Uhrzeiten und Dauern bleiben ausdrückliche Ausnahmen; der damals öffentliche stationäre Speicher-Prozentwert behielt bewusst eine Nachkommastelle.</p>
  <p>Version 2.1.3 leitet die Validierung eingehender Statusfelder, die unmittelbare öffentliche Formatierung, die Set-Discovery, das Parsen gewöhnlicher Set-Befehle, Protokollschlüssel und Usage-Texte aus zwei kleinen deklarativen Inventaren ab. Spezielle Lifecycle-, Authentifizierungs-, gruppierte <code>pvBattery</code>-, <code>password</code>-, <code>reconnect</code>-, Telemetrie-Cache- und Car-Transition-Logik bleibt ausdrücklich sichtbar. Öffentliche Namen, Payloads, Taktung und Reading-Semantik ändern sich nicht.</p>
  <p>Version 2.1.4 ersetzt die sieben einzelnen Setter für Phasenumschaltung und Mindestladen durch die gruppierten Befehle <code>phaseSwitch</code> und <code>minimumCharging</code>. Protokollschlüssel, öffentliche Einheiten, Validierung und bestätigte <code>config...</code>-Readings bleiben unverändert. Für die entfernten einzelnen Set-Namen gibt es keine Aliase.</p>
  <p>Version 2.1.5 begrenzt <code>chargingCurrent</code> nach Empfang eines nutzbaren <code>ama</code>-Werts für den aktuellen Device-Hash auf <code>6..min(32, configMaximumCurrentLimit)</code>. Fehlende, noch nicht bestätigte, fehlerhafte, nicht ganzzahlige oder außerhalb des nutzbaren Bereichs liegende Werte behalten den Kompatibilitätsbereich <code>6..32</code>. FHEMWEB erhält dieselbe dynamische Obergrenze; abgelehnte Befehle werden nicht gesendet und <code>configChargingCurrent</code> bleibt gerätebestätigt. Dieselbe Version bewahrt nach normalem EOF oder WebSocket-Close genau einen Reconnect-Eigentümer, behandelt den ersten gültigen authentifizierten partiellen oder vollständigen Status als Initialisierung, beendet ausstehende Befehle bei Sitzungsinvalidierung, führt den begrenzten Charging-zu-Idle-Refresh bei beiden <code>update_while_idle</code>-Werten aus und veröffentlicht bereits gepufferte zulässige Telemetrie sofort, wenn <code>interval</code> auf <code>0</code> wechselt.</p>
  <p>Version 2.1.6 ersetzt den gemeinsamen Telemetrie-Timer sofort, wenn <code>interval</code> zwischen positiven Werten geändert wird und Telemetrie als geändert vorgemerkt ist. Die gepufferten Werte bleiben intervallgesteuert und werden auch ohne weiteres Statuspaket am neuen Zeitpunkt veröffentlicht. Wiederholte Änderungen behalten genau einen Timer, veraltete Callbacks bleiben wirkungslos, im Idle gesperrte elektrische und Batteriedaten bleiben passiv und ohne Dirty-Daten bleibt die Clock weiterhin lazy.</p>
  <p>Version 2.1.7 ergänzt exakte Geräteidentität, getrennte Hello-/Status-Protokollreadings, intervallgesteuerte <code>deviceRebootCount</code> und <code>uptime</code> sowie vierzehn optionale skalare Felderkundungsreadings hinter <code>diagnosticReadings</code>. Der <code>rbt</code>-Wert wird aufgrund der Realgerätbeobachtung des Maintainers als Millisekunden interpretiert, durch 1.000 geteilt und als kumulative Stunden und Minuten in <code>H:MM</code> ausgegeben. Die bisherigen eigenständigen stationären Speicher-SOC-/Leistungsreadings werden durch rohe <code>diag_fbuf_akkuSOC</code> und <code>diag_fbuf_pAkku</code> ersetzt. Optionale Diagnosen werden beim Abschalten sofort gelöscht und behaupten weder Semantik, Einheit, Vorzeichen, Aggregation noch Enum.</p>
  <table class="block wide">
    <tr><th>Reading bis 2.0.6</th><th>Reading ab 2.0.7</th></tr>
    <tr><td><code>forceState</code></td><td><code>configForceState</code></td></tr>
    <tr><td><code>chargingCurrent</code></td><td><code>configChargingCurrent</code></td></tr>
    <tr><td><code>chargingMode</code></td><td><code>configChargingMode</code></td></tr>
    <tr><td><code>maximumCurrentLimit</code></td><td><code>configMaximumCurrentLimit</code></td></tr>
    <tr><td><code>minimumChargingCurrent</code></td><td><code>configMinimumChargingCurrent</code></td></tr>
    <tr><td><code>pvSurplusStartPower</code></td><td><code>configPvSurplusStartPower</code></td></tr>
    <tr><td><code>pvSurplusEnabled</code></td><td><code>configPvSurplusEnabled</code></td></tr>
    <tr><td><code>zeroFeedInEnabled</code></td><td><code>configZeroFeedInEnabled</code></td></tr>
    <tr><td><code>pvControlPreference</code></td><td><code>configPvControlPreference</code></td></tr>
    <tr><td><code>phaseSwitchMode</code></td><td><code>configPhaseSwitchMode</code></td></tr>
    <tr><td><code>threePhaseSwitchPower</code></td><td><code>configThreePhaseSwitchPower</code></td></tr>
    <tr><td><code>phaseSwitchDelay</code></td><td><code>configPhaseSwitchDelay</code></td></tr>
    <tr><td><code>minimumPhaseSwitchInterval</code></td><td><code>configMinimumPhaseSwitchInterval</code></td></tr>
    <tr><td><code>minimumChargeTime</code></td><td><code>configMinimumChargeTime</code></td></tr>
    <tr><td><code>chargingPauseAllowed</code></td><td><code>configChargingPauseAllowed</code></td></tr>
    <tr><td><code>minimumChargingPauseDuration</code></td><td><code>configMinimumChargingPauseDuration</code></td></tr>
    <tr><td><code>minimumChargingInterval</code></td><td><code>configMinimumChargingInterval</code></td></tr>
    <tr><td><code>nextTripTime</code></td><td><code>configNextTripTime</code></td></tr>
  </table>
  <!-- BEGIN 2.0 migration names -->
  <table class="block wide">
    <tr><th>Typ</th><th>1.x-Name</th><th>2.0-Name</th></tr>
    <tr><td>Reading</td><td><code>state</code></td><td><code>state</code></td></tr>
    <tr><td>Reading</td><td><code>version</code></td><td><code>firmwareVersion</code></td></tr>
    <tr><td>Reading</td><td><code>authHashMode</code></td><td><code>authHashMode</code></td></tr>
    <tr><td>Reading</td><td><code>CarState</code></td><td><code>carState</code></td></tr>
    <tr><td>Reading</td><td><code>Laden_starten</code></td><td><code>configForceState</code></td></tr>
    <tr><td>Reading</td><td><code>Strom</code></td><td><code>configChargingCurrent</code></td></tr>
    <tr><td>Reading</td><td><code>Modus</code></td><td><code>configChargingMode</code></td></tr>
    <tr><td>Reading</td><td><code>Zeit_NextTrip</code></td><td><code>configNextTripTime</code></td></tr>
    <tr><td>Reading</td><td><code>EnergyTotal</code></td><td><code>energyTotal</code></td></tr>
    <tr><td>Reading</td><td><code>Energie_seit_Anstecken</code></td><td><code>energySincePlugIn</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L1</code></td><td><code>voltageL1</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L2</code></td><td><code>voltageL2</code></td></tr>
    <tr><td>Reading</td><td><code>Voltage_L3</code></td><td><code>voltageL3</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L1</code></td><td><code>currentL1</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L2</code></td><td><code>currentL2</code></td></tr>
    <tr><td>Reading</td><td><code>Current_L3</code></td><td><code>currentL3</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L1</code></td><td><code>powerL1</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L2</code></td><td><code>powerL2</code></td></tr>
    <tr><td>Reading</td><td><code>Power_L3</code></td><td><code>powerL3</code></td></tr>
    <tr><td>Reading</td><td><code>power</code></td><td><code>power</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandRequestId</code></td><td><code>lastCommandRequestId</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandStatus</code></td><td><code>lastCommandStatus</code></td></tr>
    <tr><td>Reading</td><td><code>lastCommandError</code></td><td><code>lastCommandError</code></td></tr>
    <tr><td>Set</td><td><code>Password &lt;secret&gt;</code></td><td><code>password &lt;secret&gt;</code></td></tr>
    <tr><td>Set</td><td><code>Strom &lt;6..32&gt;</code></td><td><code>chargingCurrent &lt;6..32&gt;</code></td></tr>
    <tr><td>Set</td><td><code>Laden_starten Start|Stop</code></td><td><code>forceState neutral|off|on</code></td></tr>
    <tr><td>Set</td><td><code>Modus Default|Eco|NextTrip</code></td><td><code>chargingMode default|eco|nextTrip</code></td></tr>
    <tr><td>Set</td><td><code>Zeit_NextTrip HH:MM</code></td><td><code>nextTripTime HH:MM</code></td></tr>
  </table>
  <!-- END 2.0 migration names -->
  <br>

  <a name="Wattpilot-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Wattpilot &lt;IP-Adresse&gt; [&lt;Seriennummer&gt;]</code>
    <br><br>
    Definiert ein Wattpilot-Device.<br>
    <b>&lt;IP-Adresse&gt;</b>: Lokale IP-Adresse des Wattpilot.<br>
    <b>&lt;Seriennummer&gt;</b>: Optional und ausschließlich aus Ziffern. Ohne Angabe wird der Wert aus der <code>hello</code>-Nachricht übernommen.<br>
    <br>
    Das Passwort wird separat mit <code>set &lt;name&gt; password &lt;secret&gt;</code> gesetzt.<br>
    Eine erfolgreiche Endpoint-/Seriennummernänderung mit FHEM <code>modify</code> oder <code>defmod</code> beendet die alte Sitzung und plant genau einen Reconnect. Ungültige Änderungen werden abgewiesen, bevor Verbindung, Timer, Credentials, Readings oder Helper-Zustand verändert werden.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; password &lt;secret&gt;</code><br>
        Speichert das Passwort unter stabilen FUUID-basierten Schlüsseln und startet einen kontrollierten Reconnect. Rename schreibt Credentials nicht um. Passwortänderung und Löschung verwenden Zwei-Schlüssel-Transaktionen mit Rollback. Speicherfehler bleiben von einem fehlenden Passwort unterscheidbar.</li>
    <li><code>set &lt;name&gt; chargingCurrent &lt;6-effektivesMaximum&gt;</code><br>
        Sendet den Protokollschlüssel <code>amp</code>. Die effektive Obergrenze ist <code>min(32, configMaximumCurrentLimit)</code>, nachdem der aktuelle Device-Hash einen nutzbaren ganzzahligen <code>ama</code>-Wert von 6 bis 32 empfangen hat. Bis dahin sowie bei fehlendem, fehlerhaftem, nicht ganzzahligem oder außerhalb dieses Bereichs liegendem Reading bleibt der Kompatibilitätsbereich 6 bis 32 bestehen. FHEMWEB verwendet dieselbe dynamische Slider-Obergrenze. Abgelehnte Werte erzeugen keinen Protokollbefehl, und der Setter aktualisiert <code>configChargingCurrent</code> nicht optimistisch.</li>
    <li><code>set &lt;name&gt; forceState &lt;neutral|off|on&gt;</code><br>
        Sendet <code>frc=0</code>, <code>frc=1</code> oder <code>frc=2</code>.</li>
    <li><code>set &lt;name&gt; chargingMode &lt;default|eco|nextTrip&gt;</code><br>
        Sendet <code>lmo=3</code>, <code>lmo=4</code> oder <code>lmo=5</code>.</li>
    <li><code>set &lt;name&gt; pvSurplusStartPower &lt;Watt&gt;</code><br>
        Sendet den nicht negativen, endlichen Zahlenwert über den Protokollschlüssel <code>fst</code>. Das Modul setzt keine unbelegte Obergrenze; eine Ablehnung des Geräts erscheint in den Command-Status-Readings. Die öffentliche Einheit ist Watt.</li>
    <li><code>set &lt;name&gt; pvSurplusEnabled &lt;0|1&gt;</code><br>
        Sendet das boolesche JSON-Protokollfeld <code>fup</code>.</li>
    <li><code>set &lt;name&gt; zeroFeedInEnabled &lt;0|1&gt;</code><br>
        Sendet das boolesche JSON-Protokollfeld <code>fzf</code>.</li>
    <li><code>set &lt;name&gt; pvControlPreference &lt;preferFromGrid|default|preferToGrid&gt;</code><br>
        Sendet <code>frm=0</code>, <code>frm=1</code> oder <code>frm=2</code>.</li>
    <li><code>set &lt;name&gt; phaseSwitch &lt;Einstellung&gt; &lt;Wert&gt;</code><br>
        Bündelt die Einstellungen der Phasenumschaltung unter einem Top-Level-Befehl:<br>
        <code>mode &lt;auto|force1|force3&gt;</code> &rarr; <code>psm=0|1|2</code>;<br>
        <code>delay &lt;Sekunden&gt;</code> &rarr; <code>mpwst</code> als exakte ganze Millisekunden;<br>
        <code>minInterval &lt;Sekunden&gt;</code> &rarr; <code>mptwt</code> als exakte ganze Millisekunden;<br>
        <code>threePhasePower &lt;Watt&gt;</code> &rarr; den nicht negativen, endlichen Wert über <code>spl3</code>.</li>
    <li><code>set &lt;name&gt; minimumCharging &lt;Einstellung&gt; &lt;Sekunden&gt;</code><br>
        Bündelt die Mindestladezeiten unter einem Top-Level-Befehl:<br>
        <code>duration</code> &rarr; <code>fmt</code>;<br>
        <code>interval</code> &rarr; <code>mci</code>;<br>
        <code>pauseDuration</code> &rarr; <code>mcpd</code>.<br>
        Jeder öffentliche Wert wird exakt in ganze Protokoll-Millisekunden umgerechnet.</li>
    <li><code>set &lt;name&gt; chargingPauseAllowed &lt;0|1&gt;</code><br>
        Sendet das boolesche JSON-Protokollfeld <code>fap</code>.</li>
    <li><code>set &lt;name&gt; pvBattery &lt;Einstellung&gt; &lt;Wert&gt;</code><br>
        Bündelt alle Schreibzugriffe auf die Konfiguration des stationären PV-Speichers unter einem Top-Level-Befehl. Unterstützte Unterbefehle sind:<br>
        <code>chargeAboveSoC &lt;0-100&gt;</code> &rarr; <code>fam</code> als ganzzahliger Prozentwert;<br>
        <code>dischargeEnabled &lt;0|1&gt;</code> &rarr; <code>pdte</code> als JSON-Boolean;<br>
        <code>dischargeUntilSoC &lt;0-100&gt;</code> &rarr; <code>pdt</code> als ganzzahliger Prozentwert;<br>
        <code>dischargeTimeLimitEnabled &lt;0|1&gt;</code> &rarr; <code>pdle</code> als JSON-Boolean;<br>
        <code>dischargeStartTime &lt;HH:MM&gt;</code> &rarr; <code>pdls</code> als Sekunden seit Mitternacht;<br>
        <code>dischargeStopTime &lt;HH:MM|24:00&gt;</code> &rarr; <code>pdlo</code> als Sekunden seit Mitternacht.<br>
        Kein Reading wird optimistisch geändert; nur vom Gerät zurückgelieferter Status bestätigt einen Wert. Alle sechs gruppierten Setter wurden auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 einzeln geändert, durch geräteseitigen Status/Readback bestätigt und auf ihre Ausgangswerte zurückgesetzt. Bewusste Geräteablehnung, Persistenz über einen Neustart und weitere Firmware-/Modellstände bleiben unbestätigt.</li>
    <li><code>set &lt;name&gt; reconnect</code><br>
        Baut die lokale WebSocket-Verbindung kontrolliert neu auf, ohne ein Wattpilot-Protokollkommando zu senden. Sitzungsgebundene Timer, Authentifizierungszustand, Teil-JSON und ausstehende gesicherte Befehle werden verworfen; Betriebsreadings und Konfiguration bleiben erhalten. Ausstehende Befehle enden mit <code>lastCommandStatus=failed</code> und <code>lastCommandError=reconnect requested</code>. Der Befehl ist kein <code>fullStatus</code>-Request; ein Initialstatus nach der Anmeldung wird vom Gerät geliefert.</li>
    <li><code>set &lt;name&gt; nextTripTime &lt;HH:MM&gt;</code><br>
        Erfordert exakt zweistelliges <code>HH:MM</code> und sendet <code>ftt</code> als Sekunden nach Mitternacht.</li>
  </ul>
  <br>

  <a name="Wattpilot-get"></a>
  <b>Get</b>
  <ul>
    <li>Es sind keine eigenen <code>get</code>-Befehle implementiert.</li>
  </ul>
  <br>

  <a name="Wattpilot-attr"></a>
  <b>Attribute</b>
  <ul>
    <li>Werte außerhalb der dokumentierten Auswahl- und Wertebereiche werden abgewiesen, bevor FHEM sie speichert.</li>
    <li><code>interval &lt;Sekunden&gt;</code><br>
        Begrenzt kumulative Energie, elektrische <code>nrg</code>-Telemetrie, Gerätegesundheitswerte, <code>uptime</code> und aktivierte optionale Diagnosen über einen gemeinsamen Takt. Jeder Dateneigentümer behält nur seine neuesten gültigen Werte und eigene Dirty-Felder; jeder Tick veröffentlicht alle zulässigen geänderten Eigentümer in einer FHEM-Reading-Transaktion. Eine Gruppe veröffentlicht oder verschiebt niemals eine andere. Energie wird nur dirty, wenn sich der formatierte öffentliche Wert gegenüber dem veröffentlichten Reading tatsächlich ändert. <code>0</code> deaktiviert das Rate-Limit und veröffentlicht zulässige geänderte Werte sofort. Wird ein positiver Wert auf <code>0</code> geändert oder das Attribut gelöscht, wird der alte Timer beendet und jede aktuell zulässige Dirty-Gruppe sofort in einer gemeinsamen Transaktion veröffentlicht; Idle-gesperrte elektrische, Uptime- und Diagnosedaten bleiben dirty/passiv. Ungültige oder unvollständige Eingaben werden nicht dirty und verschieben den Takt nicht. Konfigurationsreadings bleiben sofort, diskrete Status-/Diagnosewerte sofort-bei-Änderung. Der erste gültige authentifizierte <code>fullStatus</code> oder <code>deltaStatus</code>, einschließlich <code>partial=true</code>, beendet die Initialisierung; partial steuert nur die Snapshot-Vollständigkeit. <code>deltaStatus</code> liefert eine geräteseitige Feldfilterung; daraus wird keine offizielle Aktualisierungsfrequenz einzelner Flex-Felder abgeleitet, weil keine öffentliche Fronius-Local-WebSocket-Spezifikation dafür belegt ist.</li>
    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> belässt gewöhnliche elektrische <code>nrg</code>-Telemetrie, <code>uptime</code> und aktivierte optionale Diagnosen im Idle passiv; <code>1</code> verarbeitet echte Idle-Werte dieser Owner im gemeinsamen Telemetrietakt. Bei beiden Werten startet Charging-zu-Idle genau einen begrenzten elektrischen Refresh: Ein gültiges Geräte-<code>nrg</code> in der Übergangsnachricht oder im Zeitfenster darf den Takt einmalig umgehen; andernfalls erfolgt höchstens ein kontrollierter Reconnect. Eine Attributänderung während der Episode dupliziert oder beendet sie nicht. Das Attribut sperrt Energie nicht: <code>eto</code>/<code>wh</code> werden nur vorgemerkt, wenn sich ihr formatierter öffentlicher Wert tatsächlich ändert; identische Statuswerte erneuern keine Zeitstempel. Es wird keine Geräte-Sendefrequenz behauptet, kein Polling-Kommando erfunden und kein Nullwert synthetisiert.</li>
    <li><code>diagnosticReadings &lt;0|1&gt;</code><br>
        <code>0</code> ist Standard und löscht sofort alle optionalen <code>diag_...</code>-Readings sowie deren Cache-/Dirty-Zustand; das Löschen des Attributs wirkt genauso. <code>1</code> aktiviert die vierzehn rohen skalaren Felderkundungsreadings im normalen <code>interval</code>, zulässig beim Laden oder mit <code>update_while_idle=1</code>. JSON-Zahlen werden mit genau zwei Nachkommastellen formatiert, Strings bleiben unverändert und JSON-Booleans erscheinen als <code>0|1</code>; fehlende, <code>null</code>-, Objekt-, Array- oder ungültige Werte erhalten das bisherige Reading.</li>
    <li><code>disable &lt;0|1&gt;</code><br>
        Deaktiviert das Modul und trennt bei <code>1</code> die Verbindung.</li>
    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Exaktes JSON wird nur mit <code>rawJsonLog=1</code> und <code>verbose=5</code> protokolliert. Dabei können sensible Authentifizierungs-, Netzwerk-, Geräte- und Betriebsdaten sichtbar werden. DevIo-/HttpUtils-Core-Logs können bei hohem Verbose weiterhin Endpoint-Details enthalten.</li>
    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Wählt das Authentifizierungsverfahren. <code>auto</code> akzeptiert angekündigtes PBKDF2 oder bcrypt; ein fehlender Hash wählt nur beim belegten Vorgängerprofil <code>devicetype=wattpilot</code>, Protokoll 2, PBKDF2. Eine Änderung verwirft die aktuelle Sitzung und plant nach Möglichkeit genau eine frische Anmeldung.</li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt-Kostenfaktor für neu abgeleitete Authentifizierungs-Hashes. Eine Änderung verwirft die aktuelle Sitzung.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Lifecycle-Zustand: <code>disabled</code>, <code>passwordMissing</code>, <code>credentialError</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connectionFailed</code>, <code>authFailed</code>, <code>authTimeout</code>, <code>initializationTimeout</code>, <code>authSequenceInvalid</code>, <code>authConfigMissing</code>, <code>authChallengeInvalid</code>, <code>authHashUnsupported</code>, <code>authHashFailed</code>, <code>authHashStoreFailed</code> oder <code>authNonceFailed</code>.</li>
    <li><code>firmwareVersion</code><br>Firmware-/Versionsstring aus der <code>hello</code>-Nachricht; identische Reconnect-Werte erneuern das Reading nicht.</li>
    <li><code>deviceType</code>, <code>deviceModel</code>, <code>deviceSubType</code>, <code>deviceVariant</code><br>Exakte gültige Werte aus <code>typ</code>, <code>grp</code>, <code>styp</code> und <code>var</code>. Es wird keine kommerzielle Modellzuordnung erfunden.</li>
    <li><code>helloProtocol</code>, <code>statusProtocol</code><br>Unveränderte nicht negative Ganzzahlen aus <code>hello.protocol</code> und <code>status.proto</code>. Sie bleiben getrennt; eine Beziehung wird nicht angenommen.</li>
    <li><code>authHashMode</code><br>Tatsächlich verwendetes Verfahren: <code>pbkdf2</code> oder <code>bcrypt</code>.</li>
    <li><code>carState</code><br><code>unknown</code>, <code>idle</code>, <code>charging</code>, <code>waitingForCar</code>, <code>complete</code>, <code>error</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>configForceState</code><br><code>neutral</code>, <code>off</code>, <code>on</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>configChargingCurrent</code><br>Konfigurierter/angeforderter Ladestrom; als Ampere interpretiert.</li>
    <li><code>configChargingMode</code><br><code>default</code>, <code>eco</code>, <code>nextTrip</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>chargingAllowed</code><br>Boolesches Protokollfeld <code>alw</code>, ausgegeben als <code>0</code> oder <code>1</code>. Eine gepinnte Wattpilot-spezifische Quelle beschreibt es als aktuelle Ladefreigabe; der Flex-Mitschnitt bestätigt nur Feld, Typ und Wertform.</li>
    <li><code>chargingDecisionCode</code>, <code>chargingDecisionInternalCode</code><br>Unveränderte Ganzzahlwerte aus <code>modelStatus</code> und <code>msi</code>.</li>
    <li><code>chargingDecision</code>, <code>chargingDecisionInternal</code><br>Kompatibilitäts-Klartextwerte für die beiden Rohcodes. Unbekannte Werte erscheinen als <code>unknown:&lt;Code&gt;</code>. Die Zuordnung stammt aus der gepinnten offiziellen go-e-Enum für <code>modelStatus</code> und Wattpilot-spezifischer Drittquellenevidenz für <code>msi</code>; sie ist keine offizielle Fronius-Flex-Spezifikation. Die gepinnte Drittquelle bezeichnet <code>msi</code> als interne Entscheidungsvariante; die genaue Beziehung, Auswertungsreihenfolge, Priorität und eine mögliche Rolle von <code>cpDisabledRequest</code> sind für Wattpilot Flex jedoch nicht bestätigt. Insbesondere behauptet das Modul weder, dass <code>modelStatus</code> zwingend die abschließende/wirksame Entscheidung ist, noch dass <code>msi</code> zwingend eine Entscheidung vor der CP-Ebene darstellt. Weichen die Werte voneinander ab, sind sie als zwei vom Gerät gelieferte Diagnosewerte zu behandeln; aus der Moduldokumentation darf keine Kausalkette abgeleitet werden.</li>
    <li><code>errorCode</code><br>Unveränderter Ganzzahlwert aus <code>err</code>; es wird keine Fehler-Enum angenommen.</li>
    <li><code>configMaximumCurrentLimit</code>, <code>temperatureCurrentLimit</code>, <code>configMinimumChargingCurrent</code><br>Unveränderte Ganzzahlwerte aus <code>ama</code>, <code>amt</code> und <code>mca</code>. Die Interpretation als Stromgrenzen in Ampere stammt aus gepinnter Wattpilot-Drittquellenevidenz und ist durch den bereinigten Flex-Mitschnitt nicht unabhängig bewiesen.</li>
    <li><code>configPvSurplusStartPower</code><br>Nicht negativer, endlicher Zahlenwert aus <code>fst</code>, ausgegeben in Watt mit genau zwei Nachkommastellen. Gepinnte offizielle go-e-API-Metadaten und gepinnte Wattpilot-spezifische Evidenz beschreiben ihn als Startleistung für PV-Überschussladen und als schreibbar; beim beobachteten Wattpilot Flex 43.4 betrug der Wert <code>1400</code>. Diese Evidenz trägt die Kompatibilitätszuordnung, ist aber keine offizielle Fronius-Flex-API-Spezifikation.</li>
    <li><code>configPvSurplusEnabled</code>, <code>configZeroFeedInEnabled</code>, <code>configChargingPauseAllowed</code><br>Boolesche Felder <code>fup</code>, <code>fzf</code> und <code>fap</code>, ausgegeben als <code>0</code> oder <code>1</code>.</li>
    <li><code>configPvControlPreference</code><br><code>preferFromGrid</code>, <code>default</code>, <code>preferToGrid</code> oder <code>unknown:&lt;Rohwert&gt;</code> aus <code>frm</code>.</li>
    <li><code>configPhaseSwitchMode</code><br><code>auto</code>, <code>force1</code>, <code>force3</code> oder <code>unknown:&lt;Rohwert&gt;</code> aus <code>psm</code>.</li>
    <li><code>configThreePhaseSwitchPower</code><br>Nicht negativer, endlicher Zahlenwert aus <code>spl3</code>, ausgegeben in Watt mit genau zwei Nachkommastellen.</li>
    <li><code>configPhaseSwitchDelay</code>, <code>configMinimumPhaseSwitchInterval</code>, <code>configMinimumChargeTime</code>, <code>configMinimumChargingPauseDuration</code>, <code>configMinimumChargingInterval</code><br>Nicht negative, endliche Werte aus <code>mpwst</code>, <code>mptwt</code>, <code>fmt</code>, <code>mcpd</code> und <code>mci</code>, von Protokoll-Millisekunden in öffentliche Sekunden umgerechnet.</li>
    <li><code>diag_fbuf_akkuSOC</code>, <code>diag_fbuf_pAkku</code><br>Optionale rohe skalare Felderkundungsreadings aus den beiden stationären Speicher-bezogenen Protokollfeldern. Numerische Werte werden ohne Skalierung auf genau zwei Nachkommastellen gerundet; Strings bleiben unverändert und Booleans erscheinen als <code>0|1</code>. <code>diag_fbuf_pAkku</code> und <code>diag_pvopt_averagePAkku</code> sind unterschiedliche Felder; ihre genaue Abgrenzung, Aggregation, Einheit und Vorzeichenkonvention bleiben unbestätigt.</li>
    <li><code>pvBatteryModeCode</code><br>Unveränderter nicht negativer Ganzzahlcode aus <code>fbuf_akkuMode</code>. Es wird keine Klartext-Enum erfunden.</li>
    <li><code>deviceRebootCount</code><br>Roher nicht negativer <code>rbc</code>-Wert im normalen Intervall ohne Idle-Sperre. Die genaue Semantik bleibt unbestätigt.</li>
    <li><code>uptime</code><br>Nicht negativer Millisekundenwert aus <code>rbt</code>, aufgrund der Realgerätbeobachtung des Maintainers als Zeit seit dem Gerätestart interpretiert, durch 1.000 geteilt und als kumulative Stunden und Minuten in <code>H:MM</code> ausgegeben. Verbleibende Sekunden und Millisekunden werden verworfen; Aktualisierung im normalen Intervall beim Laden oder mit <code>update_while_idle=1</code>.</li>
    <li><code>diag_fbuf_pGrid</code>, <code>diag_fbuf_pPv</code>, <code>diag_pvopt_averagePGrid</code>, <code>diag_pvopt_averagePPv</code>, <code>diag_pvopt_averagePAkku</code>, <code>diag_pvopt_averagePOhmpilot</code>, <code>diag_pvopt_deltaP</code>, <code>diag_pvopt_deltaA</code>, <code>diag_pvopt_specialCase</code>, <code>diag_fbuf_pAcTotal</code>, <code>diag_fbuf_ohmpilotState</code>, <code>diag_fbuf_ohmpilotTemperature</code><br>Optionale rohe skalare Felderkundungsreadings mit <code>diagnosticReadings=1</code>. Nach <code>diag_</code> bleibt die originale Protokollschreibweise erhalten; Bedeutung, Einheit, Vorzeichen, Aggregation und Enum werden nicht behauptet.</li>
    <li><code>configPvBatteryChargeAboveSoC</code><br>App-Einstellung <code>Charge above</code> aus <code>fam</code>, akzeptiert als endlicher Prozentwert von <code>0</code> bis <code>100</code>. Der gruppierte Setter akzeptiert nur ganze Prozentwerte.</li>
    <li><code>configPvBatteryDischargeEnabled</code><br>App-Schalter <code>Discharge until</code> aus <code>pdte</code>, ausgegeben als <code>0</code> oder <code>1</code>.</li>
    <li><code>configPvBatteryDischargeUntilSoC</code><br>App-Einstellung <code>State of charge SoC</code> aus <code>pdt</code>, akzeptiert als endlicher Prozentwert von <code>0</code> bis <code>100</code>. Der gruppierte Setter akzeptiert nur ganze Prozentwerte.</li>
    <li><code>configPvBatteryDischargeTimeLimitEnabled</code><br>App-Schalter <code>Limit discharging time</code> aus <code>pdle</code>, ausgegeben als <code>0</code> oder <code>1</code>.</li>
    <li><code>configPvBatteryDischargeStartTime</code>, <code>configPvBatteryDischargeStopTime</code><br>App-Start-/Stoppzeiten aus <code>pdls</code> und <code>pdlo</code>, von ganzen Sekunden seit Mitternacht nach <code>HH:MM</code> umgerechnet. Die sechs Konfigurationszuordnungen wurden auf einem Flex Home 22 C6 mit Firmware 43.4 anhand zeitgleich übereinstimmender Solar.wattpilot-App-Werte belegt. Alle sechs gruppierten Setter wurden anschließend auf demselben Modell/Firmwarestand vom Gerät angenommen, im geräteseitigen Status/Readback bestätigt und auf ihre Ausgangswerte zurückgesetzt. Bewusste Geräteablehnung, Persistenz über einen Neustart und weitere Firmware-/Modellstände bleiben unbestätigt.</li>
    <li>Alle 24 Konfigurationsreadings werden nach gültiger Gerätebestätigung sofort aktualisiert. Identitäts- und diskrete Status-/Diagnosereadings werden sofort nur bei tatsächlicher Änderung veröffentlicht. Energie-, elektrische <code>nrg</code>-Telemetrie, Gerätegesundheitswerte, <code>uptime</code> und aktivierte optionale Diagnosen behalten getrennte Caches und Dirty-Felder, teilen aber einen <code>interval</code>-Takt; eine Gruppe veröffentlicht nie alte Werte einer anderen. <code>pvBatteryModeCode</code> ist diskreter Status, keine Batterietelemetrie. Fehlende, <code>null</code>-, typfalsche oder unvollständige Felder erhalten Readings und Historien.</li>
  </ul>
  <p><b>Hinweis zu aWATTar:</b> aWATTar ist ein Anbieter- beziehungsweise Tarifname für dynamische Strompreise und kein technisches Kürzel des Moduls. Die aus der go-e-Enum übernommenen Namen mit <code>Awattar</code> bezeichnen preisabhängige Ladeentscheidungen. <code>Fallback</code> bezeichnet dabei den Standardausgang eines Entscheidungszweigs, wenn kein speziellerer Ladegrund greift, und nicht automatisch einen technischen Fehler. Für den Wattpilot Flex sind der genaue Auslöser dieser Codes und ihre vollständige Semantik nicht bestätigt; insbesondere beweist <code>notChargingBecauseFallbackAwattar</code> allein nicht, dass ein aWATTar-Tarif aktiviert ist.</p>
  <p><b>Kompatibilitäts-Zuordnung der Ladeentscheidung</b></p>
  <table class="block wide">
    <tr><th>Code</th><th>Klartextwert</th></tr>
      <tr><td><code>0</code></td><td><code>notChargingBecauseNoChargeCtrlData</code></td></tr>
      <tr><td><code>1</code></td><td><code>notChargingBecauseOvertemperature</code></td></tr>
      <tr><td><code>2</code></td><td><code>notChargingBecauseAccessControlWait</code></td></tr>
      <tr><td><code>3</code></td><td><code>chargingBecauseForceStateOn</code></td></tr>
      <tr><td><code>4</code></td><td><code>notChargingBecauseForceStateOff</code></td></tr>
      <tr><td><code>5</code></td><td><code>notChargingBecauseScheduler</code></td></tr>
      <tr><td><code>6</code></td><td><code>notChargingBecauseEnergyLimit</code></td></tr>
      <tr><td><code>7</code></td><td><code>chargingBecauseAwattarPriceLow</code></td></tr>
      <tr><td><code>8</code></td><td><code>chargingBecauseAutomaticStopTestLadung</code></td></tr>
      <tr><td><code>9</code></td><td><code>chargingBecauseAutomaticStopNotEnoughTime</code></td></tr>
      <tr><td><code>10</code></td><td><code>chargingBecauseAutomaticStop</code></td></tr>
      <tr><td><code>11</code></td><td><code>chargingBecauseAutomaticStopNoClock</code></td></tr>
      <tr><td><code>12</code></td><td><code>chargingBecausePvSurplus</code></td></tr>
      <tr><td><code>13</code></td><td><code>chargingBecauseFallbackGoEDefault</code></td></tr>
      <tr><td><code>14</code></td><td><code>chargingBecauseFallbackGoEScheduler</code></td></tr>
      <tr><td><code>15</code></td><td><code>chargingBecauseFallbackDefault</code></td></tr>
      <tr><td><code>16</code></td><td><code>notChargingBecauseFallbackGoEAwattar</code></td></tr>
      <tr><td><code>17</code></td><td><code>notChargingBecauseFallbackAwattar</code></td></tr>
      <tr><td><code>18</code></td><td><code>notChargingBecauseFallbackAutomaticStop</code></td></tr>
      <tr><td><code>19</code></td><td><code>chargingBecauseCarCompatibilityKeepAlive</code></td></tr>
      <tr><td><code>20</code></td><td><code>chargingBecauseChargePauseNotAllowed</code></td></tr>
      <tr><td><code>22</code></td><td><code>notChargingBecauseSimulateUnplugging</code></td></tr>
      <tr><td><code>23</code></td><td><code>notChargingBecausePhaseSwitch</code></td></tr>
      <tr><td><code>24</code></td><td><code>notChargingBecauseMinPauseDuration</code></td></tr>
      <tr><td><code>26</code></td><td><code>notChargingBecauseError</code></td></tr>
      <tr><td><code>27</code></td><td><code>notChargingBecauseLoadManagementDoesntWant</code></td></tr>
      <tr><td><code>28</code></td><td><code>notChargingBecauseOcppDoesntWant</code></td></tr>
      <tr><td><code>29</code></td><td><code>notChargingBecauseReconnectDelay</code></td></tr>
      <tr><td><code>30</code></td><td><code>notChargingBecauseAdapterBlocking</code></td></tr>
      <tr><td><code>31</code></td><td><code>notChargingBecauseUnderfrequencyControl</code></td></tr>
      <tr><td><code>32</code></td><td><code>notChargingBecauseUnbalancedLoad</code></td></tr>
      <tr><td><code>33</code></td><td><code>chargingBecauseDischargingPvBattery</code></td></tr>
      <tr><td><code>34</code></td><td><code>notChargingBecauseGridMonitoring</code></td></tr>
      <tr><td><code>35</code></td><td><code>notChargingBecauseOcppFallback</code></td></tr>
  </table>
  <ul>
    <li><code>configNextTripTime</code><br>Protokollwert als <code>HH:MM</code>; als Sekunden nach Mitternacht interpretiert.</li>
    <li><code>energyTotal</code><br>Protokollwert <code>eto</code> geteilt durch 1000 und mit zwei Nachkommastellen formatiert. Die Interpretation Wh nach kWh ist Implementierungswissen und durch den bereinigten Flex-Mitschnitt nicht bewiesen.</li>
    <li><code>energySincePlugIn</code><br>Protokollwert <code>wh</code> mit zwei Nachkommastellen; als Wh interpretiert.</li>
    <li>Die beiden Energie-Readings verwenden den gemeinsamen Telemetrietakt, behalten aber einen getrennten Latest-Value-Cache. Sie werden nur vorgemerkt, wenn sich der formatierte öffentliche Wert ändert; identische Werte aus <code>fullStatus</code>, <code>deltaStatus</code> oder Responses erneuern weder Zeitstempel noch Events. Elektrische oder Batteriedaten werden dadurch weder verbraucht noch freigegeben.</li>
    <li><code>voltageL1</code>, <code>voltageL2</code>, <code>voltageL3</code><br>Werte aus <code>nrg[0..2]</code>, als Volt interpretiert.</li>
    <li><code>currentL1</code>, <code>currentL2</code>, <code>currentL3</code><br>Werte aus <code>nrg[4..6]</code>, als Ampere interpretiert.</li>
    <li><code>powerL1</code>, <code>powerL2</code>, <code>powerL3</code><br>Werte aus <code>nrg[7..9]</code>, als Watt interpretiert.</li>
    <li><code>power</code><br>Wert aus <code>nrg[11]</code>, als Gesamtleistung in Watt interpretiert.</li>
    <li><code>lastCommandRequestId</code>, <code>lastCommandStatus</code>, <code>lastCommandError</code><br>
        Korrelation und Ergebnis des letzten gesicherten Befehls. Statuswerte sind <code>pending</code>, <code>success</code>, <code>failed</code> oder <code>timeout</code>. Wird eine aktive Sitzung vor der Antwort invalidiert, werden alle ausstehenden Requests und ihr Timeout entfernt; der neueste Request endet als <code>failed</code> mit einem stabilen redigierten Grund wie <code>connection lost</code>, <code>device disabled</code>, <code>credentials changed</code>, <code>authentication aborted</code>, <code>lifecycle timeout</code>, <code>reconnect requested</code>, <code>definition changed</code> oder <code>session replaced</code>. Undefine und Shutdown unterdrücken neue Diagnose-Events.</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 72_Wattpilot.pm
{
  "meta-spec": {
    "version": "2",
    "url": "https://metacpan.org/pod/CPAN::Meta::Spec"
  },
  "name": "FHEM-Wattpilot",
  "abstract": "Control a Fronius Wattpilot wallbox from FHEM",
  "description": "FHEM module for the local Wattpilot WebSocket API V2.",
  "version": "v2.1.7",
  "release_status": "testing",
  "author": [
    "Dennis Gramespacher <>",
    "Flachzange <>"
  ],
  "license": [
    "gpl_2"
  ],
  "dynamic_config": 0,
  "generated_by": "FHEM Wattpilot release tooling",
  "prereqs": {
    "runtime": {
      "requires": {
        "perl": "5.010",
        "FHEM": "0",
        "FHEM::Meta": "0",
        "DevIo": "0",
        "JSON": "0",
        "Digest::SHA": "0",
        "Crypt::PBKDF2": "0",
        "Crypt::URandom": "0"
      },
      "recommends": {
        "Crypt::Bcrypt": "0"
      }
    }
  },
  "resources": {
    "repository": {
      "type": "git",
      "url": "https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot.git",
      "web": "https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot",
      "x_branch": "main",
      "x_filepath": "",
      "x_raw": "https://raw.githubusercontent.com/Flachzange/FHEM_Modul_Fronius_Wattpilot/main/72_Wattpilot.pm"
    },
    "bugtracker": {
      "web": "https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot/issues"
    }
  },
  "x_fhem_module_name": "Wattpilot",
  "x_fhem_original_author": [
    "Dennis Gramespacher"
  ],
  "x_fhem_version_2_author": [
    "Flachzange"
  ],
  "x_development_assistance": [
    "OpenAI ChatGPT"
  ],
  "x_fhem_maintainer": [
    "Flachzange"
  ],
  "x_fhem_maintainer_github": [
    "Flachzange"
  ],
  "x_support_status": "experimental",
  "x_spdx_license": "GPL-2.0-or-later"
}
=end :application/json;q=META.json

# Ende der Commandref
=cut
