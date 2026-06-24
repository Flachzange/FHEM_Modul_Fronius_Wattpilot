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
# Quellen / Referenzen:
# 1. https://github.com/joscha82/wattpilot
# 2. https://wiki.fhem.de/wiki/Websocket
# 3. https://github.com/tim2zg/ioBroker.fronius-wattpilot
##############################################

package main;

use strict;
use warnings;
use bytes ();
use B qw(svref_2object SVf_POK SVp_POK);
use DevIo;
use FHEM::Meta;
use JSON;
use Digest::SHA qw(sha256_hex);
use Crypt::PBKDF2;
use Crypt::URandom qw(urandom);

my $WATTPILOT_VERSION = '2.0.6';
my $WATTPILOT_REQUEST_TIMEOUT = 30;
my $WATTPILOT_AUTH_TIMEOUT = 30;
my $WATTPILOT_INITIALIZATION_TIMEOUT = 30;
my $WATTPILOT_TIMEOUT_RETRY_DELAY = 5;
my $WATTPILOT_IDLE_REFRESH_TIMEOUT = 30;
my $WATTPILOT_MAX_PENDING_REQUESTS = 32;
my $WATTPILOT_MAX_JSON_BYTES = 1024 * 1024;
my $WATTPILOT_MAX_JSON_DOCUMENTS = 256;


my %WATTPILOT_READING_NAME = (
    state                   => 'state',
    firmware_version        => 'firmwareVersion',
    auth_hash_mode          => 'authHashMode',
    car_state               => 'carState',
    force_state             => 'forceState',
    charging_current        => 'chargingCurrent',
    charging_mode           => 'chargingMode',
    charging_allowed        => 'chargingAllowed',
    charging_decision_code  => 'chargingDecisionCode',
    charging_decision        => 'chargingDecision',
    charging_decision_internal_code => 'chargingDecisionInternalCode',
    charging_decision_internal => 'chargingDecisionInternal',
    error_code              => 'errorCode',
    maximum_current_limit   => 'maximumCurrentLimit',
    temperature_current_limit => 'temperatureCurrentLimit',
    minimum_charging_current => 'minimumChargingCurrent',
    pv_surplus_start_power  => 'pvSurplusStartPower',
    pv_surplus_enabled      => 'pvSurplusEnabled',
    zero_feed_in_enabled    => 'zeroFeedInEnabled',
    pv_control_preference   => 'pvControlPreference',
    phase_switch_mode       => 'phaseSwitchMode',
    three_phase_switch_power => 'threePhaseSwitchPower',
    phase_switch_delay      => 'phaseSwitchDelay',
    minimum_phase_switch_interval => 'minimumPhaseSwitchInterval',
    minimum_charge_time     => 'minimumChargeTime',
    charging_pause_allowed  => 'chargingPauseAllowed',
    minimum_charging_pause_duration => 'minimumChargingPauseDuration',
    minimum_charging_interval => 'minimumChargingInterval',
    pv_battery_state_of_charge => 'pvBatteryStateOfCharge',
    pv_battery_power        => 'pvBatteryPower',
    pv_battery_mode_code    => 'pvBatteryModeCode',
    next_trip_time          => 'nextTripTime',
    energy_total            => 'energyTotal',
    energy_since_plug_in    => 'energySincePlugIn',
    voltage_l1              => 'voltageL1',
    voltage_l2              => 'voltageL2',
    voltage_l3              => 'voltageL3',
    current_l1              => 'currentL1',
    current_l2              => 'currentL2',
    current_l3              => 'currentL3',
    power_l1                => 'powerL1',
    power_l2                => 'powerL2',
    power_l3                => 'powerL3',
    power                   => 'power',
    last_command_request_id => 'lastCommandRequestId',
    last_command_status     => 'lastCommandStatus',
    last_command_error      => 'lastCommandError',
);

my %WATTPILOT_COMMAND_NAME = (
    password         => 'password',
    force_state      => 'forceState',
    charging_current => 'chargingCurrent',
    charging_mode    => 'chargingMode',
    pv_surplus_start_power => 'pvSurplusStartPower',
    pv_surplus_enabled => 'pvSurplusEnabled',
    zero_feed_in_enabled => 'zeroFeedInEnabled',
    pv_control_preference => 'pvControlPreference',
    phase_switch_mode => 'phaseSwitchMode',
    three_phase_switch_power => 'threePhaseSwitchPower',
    phase_switch_delay => 'phaseSwitchDelay',
    minimum_phase_switch_interval => 'minimumPhaseSwitchInterval',
    minimum_charge_time => 'minimumChargeTime',
    charging_pause_allowed => 'chargingPauseAllowed',
    minimum_charging_pause_duration => 'minimumChargingPauseDuration',
    minimum_charging_interval => 'minimumChargingInterval',
    reconnect => 'reconnect',
    next_trip_time   => 'nextTripTime',
);

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
    
    # Attribut-Liste:
    # interval: Schieberegler von 0 bis 300, Schrittweite 5 (Sekunden)
    # update_while_idle: Boolean (0/1) um Updates auch im Leerlauf zu erzwingen
    # defaultAmp: Standard-Stromstärke (kann als Slider dargestellt werden, z.B. 6-32A)
    $hash->{AttrList} = "debug:1,0 interval:slider,0,5,300 update_while_idle:0,1 defaultAmp:slider,6,1,32 disable:0,1 rawJsonLog:0,1 authHash:auto,pbkdf2,bcrypt authHashCost:slider,4,1,14 " .
	$readingFnAttributes;

    return FHEM::Meta::InitMod(__FILE__, $hash);
}

sub Wattpilot_InterfaceSnapshot() {
    return {
        readings       => { %WATTPILOT_READING_NAME },
        commands       => { %WATTPILOT_COMMAND_NAME },
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

sub Wattpilot_InvalidateSession($;$) {
    my ($hash, $close_ctx) = @_;
    my $open_ctx = $hash->{helper}{openInFlight};
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
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

sub Wattpilot_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);

    if(@a < 3 || @a > 4) {
        return "Usage: define <name> Wattpilot <IP> [Serial]";
    }

    my $name = $a[0];
    my $ip = $a[2];
    my $serial = $a[3] if (defined $a[3]);
    if (defined($serial) && $serial !~ /^\d+$/) {
        return "Serial must contain digits only";
    }

    delete $hash->{helper}{undefined};
    delete $hash->{helper}{deleting};
    delete $hash->{helper}{shuttingDown};
    delete $hash->{helper}{timeoutRetryUsed};
    Wattpilot_NextLifecycleGeneration($hash);

    # DevIo WebSocket URL Format: ws:host:port/path
    $hash->{DeviceName} = "ws:$ip:80/ws";
    $hash->{VERSION} = $WATTPILOT_VERSION;
    $hash->{SERIAL} = $serial;
    # DevIo privacy masks only its initial opening line. devioLoglevel reduces
    # direct DevIo diagnostics, but cannot control transitive HttpUtils logs.
    $hash->{devioLoglevel} = 6;

    # WebSocket spezifische Header
    $hash->{header}{'User-Agent'} = 'FHEM';

    $modules{Wattpilot}{defptr}{$name} = $hash;
    Wattpilot_ApplyConfiguredState($hash, 2);
    return undef;
}

sub Wattpilot_Undefine($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{undefined} = 1;
    Wattpilot_InvalidateSession($hash);
    RemoveInternalTimer($hash);

    delete $modules{Wattpilot}{defptr}{$name};
    return undef;
}

sub Wattpilot_Delete($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{deleting} = 1;
    Wattpilot_InvalidateSession($hash);
    RemoveInternalTimer($hash);
    my $error = Wattpilot_DeleteStoredSecrets($hash);
    Wattpilot_RestoreAfterFailedDelete($hash, $name) if defined $error;
    return $error;
}

sub Wattpilot_RestoreAfterFailedDelete($$) {
    my ($hash, $name) = @_;

    $modules{Wattpilot}{defptr}{$name} = $hash;
    delete $hash->{helper}{undefined};
    delete $hash->{helper}{deleting};
    delete $hash->{helper}{shuttingDown};
    delete $hash->{helper}{timeoutRetryUsed};
    Wattpilot_InvalidateSession($hash);
    Wattpilot_ApplyConfiguredState($hash, 2);
}

sub Wattpilot_Shutdown($) {
    my ($hash) = @_;
    $hash->{helper}{shuttingDown} = 1;
    Wattpilot_InvalidateSession($hash);
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
    });

    delete $modules{Wattpilot}{defptr}{$old_name};
    $modules{Wattpilot}{defptr}{$new_name} = $hash;
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
    Wattpilot_ClearConnectionState($hash);
    
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
    Wattpilot_ClearConnectionState($hash);
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
        Wattpilot_NextLifecycleGeneration($hash);
        Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
        Wattpilot_CancelTimer($hash, 'idle_refresh');
        delete $hash->{helper}{openInFlight};
        Wattpilot_ClearConnectionState($hash);
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

sub Wattpilot_IsJsonString($) {
    my ($value) = @_;
    return 0 if !defined($value) || ref($value);
    my $flags = svref_2object(\$value)->FLAGS;
    return ($flags & (SVf_POK | SVp_POK)) ? 1 : 0;
}

sub Wattpilot_MessageTypeForLog($) {
    my ($type) = @_;
    return 'redacted'
        if !Wattpilot_IsJsonString($type)
        || bytes::length($type) > 64
        || $type !~ /\A[A-Za-z][A-Za-z0-9_.:-]{0,63}\z/;
    return $type;
}

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

sub Wattpilot_IsInteger($) {
    my ($value) = @_;
    return Wattpilot_IsScalarString($value) && $value =~ /^-?(?:0|[1-9]\d*)$/;
}

sub Wattpilot_IsBoolean($) {
    my ($value) = @_;
    return 1 if JSON::is_bool($value);
    return Wattpilot_IsScalarString($value) && $value =~ /^(?:0|1)$/;
}

sub Wattpilot_NormalizeStatus($$) {
    my ($hash, $input_status) = @_;
    return undef if ref($input_status) ne 'HASH';

    my %status = %$input_status;
    my %integer = map { $_ => 1 } qw(
        car frc ftt amp lmo modelStatus msi err ama amt mca frm psm
    );
    my %nonnegative_integer = map { $_ => 1 } qw(fbuf_akkuMode);
    my %number = map { $_ => 1 } qw(eto wh);
    my %finite_number = map { $_ => 1 } qw(fbuf_pAkku);
    my %percentage = map { $_ => 1 } qw(fbuf_akkuSOC);
    my %nonnegative_number = map { $_ => 1 } qw(
        fst spl3 mpwst mptwt fmt mcpd mci
    );
    my %boolean = map { $_ => 1 } qw(alw fup fzf fap);
    for my $key (keys %integer) {
        next if !exists($status{$key}) || !defined($status{$key});
        if (!Wattpilot_IsInteger($status{$key})) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        }
    }
    for my $key (keys %nonnegative_integer) {
        next if !exists($status{$key}) || !defined($status{$key});
        if (!Wattpilot_IsInteger($status{$key}) || $status{$key} < 0) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        }
    }
    for my $key (keys %number) {
        next if !exists($status{$key}) || !defined($status{$key});
        if (!Wattpilot_IsNumber($status{$key})) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        }
    }
    for my $key (keys %finite_number) {
        next if !exists($status{$key}) || !defined($status{$key});
        my $value = Wattpilot_ParseFiniteNumber($status{$key});
        if (!defined($value)) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        } else {
            $status{$key} = $value;
        }
    }
    for my $key (keys %percentage) {
        next if !exists($status{$key}) || !defined($status{$key});
        my $value = Wattpilot_ParsePercentage($status{$key});
        if (!defined($value)) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        } else {
            $status{$key} = $value;
        }
    }
    for my $key (keys %nonnegative_number) {
        next if !exists($status{$key}) || !defined($status{$key});
        my $value = Wattpilot_ParseFiniteNonNegativeNumber($status{$key});
        if (!defined($value)) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        } else {
            $status{$key} = $value;
        }
    }
    for my $key (keys %boolean) {
        next if !exists($status{$key}) || !defined($status{$key});
        if (!Wattpilot_IsBoolean($status{$key})) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status{$key};
        }
    }
    if (exists($status{nrg}) && defined($status{nrg})) {
        my $valid = ref($status{nrg}) eq 'ARRAY'
            && @{$status{nrg}} >= 12
            && !grep { !defined($_) || !Wattpilot_IsNumber($_) } @{$status{nrg}}[0..11];
        if (!$valid) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=nrg";
            delete $status{nrg};
        }
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
            if Wattpilot_IsScalarString($json->{devicetype});
        $hash->{helper}{protocol} = int($json->{protocol})
            if Wattpilot_IsInteger($json->{protocol});
        $hash->{SERIAL} = $json->{serial}
            if (!$hash->{SERIAL} && Wattpilot_IsScalarString($json->{serial}) && $json->{serial} =~ /^\d+$/);
        if (Wattpilot_IsScalarString($json->{version})) {
            readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{firmware_version}, $json->{version}, 1);
        }
        Log3 $name, 4, "Wattpilot ($name) - Hello received";
    } elsif ($type eq 'authRequired') {
        Log3 $name, 4, "Wattpilot ($name) - Auth Required";
        Wattpilot_ClearCommandState($hash);
        Wattpilot_SendAuth($hash, $json);
    } elsif ($type eq 'authSuccess') {
        if (!$hash->{helper}{authPending}) {
            Log3 $name, 1, "Wattpilot ($name) - Authentication success arrived outside an active challenge";
            Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_sequence_invalid});
            return 0;
        }
        Log3 $name, 2, "Wattpilot ($name) - Authentication Successful";
        $hash->{helper}{authenticated} = 1;
        delete $hash->{helper}{authPending};
        delete $hash->{helper}{authHashMode};
        Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
        readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{initializing}, 1);
        Wattpilot_ScheduleTimer(
            $hash, 'lifecycle_timeout', $WATTPILOT_INITIALIZATION_TIMEOUT,
            'Wattpilot_LifecycleTimeout', { phase => 'initialization' });
    } elsif ($type eq 'authError') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication failed";
        Wattpilot_AbortAuthentication($hash, $WATTPILOT_LIFECYCLE_STATE{auth_failed});
    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {
        if (ref($json->{status}) ne 'HASH') {
            Log3 $name, 2, "Wattpilot ($name) - Ignoring status message with missing or invalid status";
            return 0;
        }
        my $status = Wattpilot_NormalizeStatus($hash, $json->{status});
        Wattpilot_UpdateReadings($hash, $status, $type);
        Wattpilot_MarkInitialized($hash)
            if $hash->{helper}{authenticated}
            && ($hash->{STATE} // '') eq $WATTPILOT_LIFECYCLE_STATE{initializing};
    } elsif ($type eq 'response') {
        if (exists($json->{success}) && !Wattpilot_IsBoolean($json->{success})) {
            Log3 $name, 2, "Wattpilot ($name) - Ignoring response with invalid success value";
            return 0;
        }
        if (exists($json->{success}) && $json->{success}
            && ref($json->{status}) ne 'HASH') {
            Log3 $name, 2, "Wattpilot ($name) - Ignoring successful response with missing or invalid status";
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
        Log3 $name, 3, "Wattpilot ($name) - Ignoring unsupported JSON message type=$type_for_log";
    }
    return 1;
}

sub Wattpilot_MarkInitialized($) {
    my ($hash) = @_;
    Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
    delete $hash->{helper}{timeoutRetryUsed};
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{connected}, 1);
}

sub Wattpilot_NrgReadingsNeedIdleRefresh($) {
    my ($hash) = @_;
    for my $reading (
        @WATTPILOT_READING_NAME{qw(
            power current_l1 current_l2 current_l3
            power_l1 power_l2 power_l3
        )}) {
        return 1 if !exists($hash->{READINGS}{$reading}{VAL});
        my $value = $hash->{READINGS}{$reading}{VAL};
        return 1 if defined($value) && $value =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/ && $value != 0;
    }
    return 0;
}

sub Wattpilot_StartIdleRefreshWindow($;$) {
    my ($hash, $update_while_idle_override) = @_;
    my $update_while_idle = defined($update_while_idle_override)
        ? $update_while_idle_override
        : AttrVal($hash->{NAME}, "update_while_idle", 0);
    return if $update_while_idle ne "1";
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
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
    Wattpilot_ClearConnectionState($hash);
    delete $hash->{helper}{openInFlight};
    DevIo_CloseDev($hash);
    readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disconnected}, 1);
    Wattpilot_ScheduleConnect($hash, 1);
}

sub Wattpilot_UpdateImmediateReadings($$) {
    my ($hash, $status) = @_;

    if (defined $status->{car}) {
        my $car_value = int($status->{car});
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{car_state},
            $WATTPILOT_CAR_STATE{$car_value} // 'unknown:' . $status->{car});
        $hash->{helper}{car_state} = $car_value;
    }

    if (defined $status->{frc}) {
        my $force_value = int($status->{frc});
        my $force_state = exists($WATTPILOT_FORCE_STATE{$force_value})
            ? $WATTPILOT_FORCE_STATE{$force_value}
            : 'unknown:' . $status->{frc};
        readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{force_state}, $force_state);
    }

    if (defined $status->{ftt}) {
        my $secs = $status->{ftt};
        my $h = int($secs / 3600);
        my $m = int(($secs % 3600) / 60);
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{next_trip_time},
            sprintf("%02d:%02d", $h, $m));
    }

    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{charging_current}, $status->{amp})
        if defined $status->{amp};

    if (defined $status->{lmo}) {
        my $mode_value = int($status->{lmo});
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{charging_mode},
            $WATTPILOT_CHARGING_MODE{$mode_value} // 'unknown:' . $status->{lmo});
    }

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{charging_allowed},
        $status->{alw} ? 1 : 0)
        if defined $status->{alw};

    for my $field (
        [modelStatus => 'charging_decision_code', 'charging_decision'],
        [msi => 'charging_decision_internal_code', 'charging_decision_internal'],
    ) {
        my ($protocol_key, $code_reading_key, $text_reading_key) = @$field;
        next if !defined $status->{$protocol_key};
        my $value = int($status->{$protocol_key});
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{$code_reading_key}, $value);
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{$text_reading_key},
            $WATTPILOT_CHARGING_DECISION{$value} // 'unknown:' . $value);
    }

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{pv_surplus_start_power},
        $status->{fst})
        if defined $status->{fst};

    for my $field (
        [fup => 'pv_surplus_enabled'],
        [fzf => 'zero_feed_in_enabled'],
        [fap => 'charging_pause_allowed'],
    ) {
        my ($protocol_key, $reading_key) = @$field;
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{$reading_key},
            $status->{$protocol_key} ? 1 : 0)
            if defined $status->{$protocol_key};
    }

    if (defined $status->{frm}) {
        my $value = int($status->{frm});
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{pv_control_preference},
            $WATTPILOT_PV_CONTROL_PREFERENCE{$value} // 'unknown:' . $value);
    }

    if (defined $status->{psm}) {
        my $value = int($status->{psm});
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{phase_switch_mode},
            $WATTPILOT_PHASE_SWITCH_MODE{$value} // 'unknown:' . $value);
    }

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{three_phase_switch_power},
        $status->{spl3})
        if defined $status->{spl3};

    for my $field (
        [mpwst => 'phase_switch_delay'],
        [mptwt => 'minimum_phase_switch_interval'],
        [fmt => 'minimum_charge_time'],
        [mcpd => 'minimum_charging_pause_duration'],
        [mci => 'minimum_charging_interval'],
    ) {
        my ($protocol_key, $reading_key) = @$field;
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{$reading_key},
            Wattpilot_MillisecondsToSeconds($status->{$protocol_key}))
            if defined $status->{$protocol_key};
    }

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{pv_battery_state_of_charge},
        $status->{fbuf_akkuSOC})
        if defined $status->{fbuf_akkuSOC};

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{pv_battery_power},
        $status->{fbuf_pAkku})
        if defined $status->{fbuf_pAkku};

    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{pv_battery_mode_code},
        $status->{fbuf_akkuMode})
        if defined $status->{fbuf_akkuMode};

    for my $field (
        [err => 'error_code'],
        [ama => 'maximum_current_limit'],
        [amt => 'temperature_current_limit'],
        [mca => 'minimum_charging_current'],
    ) {
        my ($protocol_key, $reading_key) = @$field;
        readingsBulkUpdate(
            $hash, $WATTPILOT_READING_NAME{$reading_key},
            int($status->{$protocol_key}))
            if defined $status->{$protocol_key};
    }
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

sub Wattpilot_ShouldProcessElectricalReadings($$$$) {
    my ($hash, $status, $message_type, $now) = @_;
    my $name = $hash->{NAME};
    my $has_valid_nrg = ref($status->{nrg}) eq 'ARRAY'
        && @{$status->{nrg}} >= 12;
    my $interval = AttrVal($name, "interval", 0);
    my $last_update = $hash->{LAST_UPDATE} // 0;
    my $suppress_electrical =
        $interval > 0 && ($now - $last_update < $interval);
    my $is_charging = ($hash->{helper}{car_state} // 0) == 2;
    my $update_while_idle = AttrVal($name, "update_while_idle", 0);
    my $idle_bypass = ($hash->{helper}{idleRefreshPending}
        || $hash->{helper}{idleRefreshAwaitingReconnectNrg})
        && $has_valid_nrg;

    my $process_electrical = 0;
    if ($idle_bypass) {
        $process_electrical = 1;
        Wattpilot_StopIdleRefresh($hash);
        delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
    } elsif (!$suppress_electrical
        && ($is_charging || $update_while_idle)) {
        $process_electrical = 1;
    }

    if ($hash->{helper}{idleRefreshAwaitingReconnectNrg}
        && !$has_valid_nrg
        && $message_type eq 'fullStatus'
        && !$status->{partial}) {
        delete $hash->{helper}{idleRefreshAwaitingReconnectNrg};
    }

    $hash->{LAST_UPDATE} = $now if $process_electrical;
    return $process_electrical;
}

sub Wattpilot_UpdateEnergyReadings($$) {
    my ($hash, $status) = @_;
    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{energy_total},
        sprintf("%.2f", $status->{eto} / 1000))
        if defined $status->{eto};
    readingsBulkUpdate(
        $hash, $WATTPILOT_READING_NAME{energy_since_plug_in},
        sprintf("%.2f", $status->{wh}))
        if defined $status->{wh};
}

sub Wattpilot_UpdateNrgReadings($$) {
    my ($hash, $status) = @_;
    return if ref($status->{nrg}) ne 'ARRAY';
    my @nrg = @{$status->{nrg}};
    return if @nrg <= 11;

    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{voltage_l1}, sprintf("%.2f", $nrg[0]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{voltage_l2}, sprintf("%.2f", $nrg[1]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{voltage_l3}, sprintf("%.2f", $nrg[2]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{current_l1}, sprintf("%.2f", $nrg[4]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{current_l2}, sprintf("%.2f", $nrg[5]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{current_l3}, sprintf("%.2f", $nrg[6]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{power_l1}, sprintf("%.2f", $nrg[7]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{power_l2}, sprintf("%.2f", $nrg[8]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{power_l3}, sprintf("%.2f", $nrg[9]));
    readingsBulkUpdate($hash, $WATTPILOT_READING_NAME{power}, sprintf("%.2f", $nrg[11]));
}

sub Wattpilot_UpdateReadings($$;$) {
    my ($hash, $status, $message_type) = @_;
    return if ref($status) ne 'HASH';
    $message_type //= 'deltaStatus';

    my $previous_car_state = $hash->{helper}{car_state};
    my $now = gettimeofday();

    readingsBeginUpdate($hash);
    Wattpilot_UpdateImmediateReadings($hash, $status);
    Wattpilot_HandleCarTransition($hash, $previous_car_state);
    Wattpilot_UpdateEnergyReadings($hash, $status);
    if (Wattpilot_ShouldProcessElectricalReadings(
            $hash, $status, $message_type, $now)) {
        Wattpilot_UpdateNrgReadings($hash, $status);
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

    if (!Wattpilot_IsScalarString($json->{token1}) || $json->{token1} eq ''
        || !Wattpilot_IsScalarString($json->{token2}) || $json->{token2} eq '') {
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



sub Wattpilot_AbortPendingRequestsForReconnect($) {
    my ($hash) = @_;
    my $pending = $hash->{helper}{pendingRequests};
    return if ref($pending) ne 'HASH' || !keys %$pending;

    my ($request_id) = sort {
        ($pending->{$b}{sentAt} // 0) <=> ($pending->{$a}{sentAt} // 0)
            || $b <=> $a
    } keys %$pending;
    Wattpilot_CancelTimer($hash, 'command_timeout');
    delete $hash->{helper}{pendingRequests};
    Wattpilot_SetCommandReadings(
        $hash, $request_id, 'failed', 'reconnect requested');
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
    Wattpilot_InvalidateSession($hash);
    Wattpilot_ApplyConfiguredState($hash, 0);
    return undef;
}

sub Wattpilot_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $cmd = $a[1] // '';
    my $val = $a[2];

    return "Device is disabled" if(Wattpilot_IsDisabled($name));

    if ($cmd eq $WATTPILOT_COMMAND_NAME{reconnect}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{reconnect}"
            if @a != 2;
        return Wattpilot_ManualReconnect($hash);
    } elsif($cmd eq $WATTPILOT_COMMAND_NAME{force_state}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{force_state} <neutral|off|on>"
            if !defined($val) || !exists($WATTPILOT_FORCE_COMMAND_VALUE{$val});
        return Wattpilot_SendSecure(
            $hash, "frc", int($WATTPILOT_FORCE_COMMAND_VALUE{$val}));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{charging_current}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{charging_current} <6-32>"
            if !defined($val) || $val !~ /^(?:[6-9]|[12]\d|3[0-2])$/;
        return Wattpilot_SendSecure($hash, "amp", int($val));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{pv_surplus_start_power}) {
        my $watts = defined($val)
            ? Wattpilot_ParseFiniteNonNegativeNumber($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_surplus_start_power} <watts>"
            if @a != 3 || !defined($watts);
        return Wattpilot_SendSecure($hash, "fst", $watts);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{pv_surplus_enabled}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_surplus_enabled} <0|1>"
            if @a != 3 || !defined($val) || $val !~ /^(?:0|1)$/;
        return Wattpilot_SendSecure(
            $hash, "fup", $val eq '1' ? JSON::true : JSON::false);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{zero_feed_in_enabled}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{zero_feed_in_enabled} <0|1>"
            if @a != 3 || !defined($val) || $val !~ /^(?:0|1)$/;
        return Wattpilot_SendSecure(
            $hash, "fzf", $val eq '1' ? JSON::true : JSON::false);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{pv_control_preference}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{pv_control_preference} <preferFromGrid|default|preferToGrid>"
            if @a != 3 || !defined($val)
            || !exists($WATTPILOT_PV_CONTROL_PREFERENCE_VALUE{$val});
        return Wattpilot_SendSecure(
            $hash, "frm", $WATTPILOT_PV_CONTROL_PREFERENCE_VALUE{$val});
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{phase_switch_mode}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{phase_switch_mode} <auto|force1|force3>"
            if @a != 3 || !defined($val)
            || !exists($WATTPILOT_PHASE_SWITCH_MODE_VALUE{$val});
        return Wattpilot_SendSecure(
            $hash, "psm", $WATTPILOT_PHASE_SWITCH_MODE_VALUE{$val});
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{three_phase_switch_power}) {
        my $watts = defined($val)
            ? Wattpilot_ParseFiniteNonNegativeNumber($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{three_phase_switch_power} <watts>"
            if @a != 3 || !defined($watts);
        return Wattpilot_SendSecure($hash, "spl3", $watts);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{phase_switch_delay}) {
        my $milliseconds = defined($val)
            ? Wattpilot_ParseSecondsToMilliseconds($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{phase_switch_delay} <seconds>"
            if @a != 3 || !defined($milliseconds);
        return Wattpilot_SendSecure($hash, "mpwst", $milliseconds);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{minimum_phase_switch_interval}) {
        my $milliseconds = defined($val)
            ? Wattpilot_ParseSecondsToMilliseconds($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{minimum_phase_switch_interval} <seconds>"
            if @a != 3 || !defined($milliseconds);
        return Wattpilot_SendSecure($hash, "mptwt", $milliseconds);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{minimum_charge_time}) {
        my $milliseconds = defined($val)
            ? Wattpilot_ParseSecondsToMilliseconds($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{minimum_charge_time} <seconds>"
            if @a != 3 || !defined($milliseconds);
        return Wattpilot_SendSecure($hash, "fmt", $milliseconds);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{charging_pause_allowed}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{charging_pause_allowed} <0|1>"
            if @a != 3 || !defined($val) || $val !~ /^(?:0|1)$/;
        return Wattpilot_SendSecure(
            $hash, "fap", $val eq '1' ? JSON::true : JSON::false);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{minimum_charging_pause_duration}) {
        my $milliseconds = defined($val)
            ? Wattpilot_ParseSecondsToMilliseconds($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{minimum_charging_pause_duration} <seconds>"
            if @a != 3 || !defined($milliseconds);
        return Wattpilot_SendSecure($hash, "mcpd", $milliseconds);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{minimum_charging_interval}) {
        my $milliseconds = defined($val)
            ? Wattpilot_ParseSecondsToMilliseconds($val)
            : undef;
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{minimum_charging_interval} <seconds>"
            if @a != 3 || !defined($milliseconds);
        return Wattpilot_SendSecure($hash, "mci", $milliseconds);
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{charging_mode}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{charging_mode} <default|eco|nextTrip>"
            if !defined $val;
        return "Unknown mode $val"
            if !exists $WATTPILOT_CHARGING_MODE_VALUE{$val};
        return Wattpilot_SendSecure(
            $hash, "lmo", $WATTPILOT_CHARGING_MODE_VALUE{$val});
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{next_trip_time}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{next_trip_time} <HH:MM>"
            if !defined($val)
            || $val !~ /^(?:[01]\d|2[0-3]):[0-5]\d$/;
        my ($h, $m) = split(':', $val);
        my $seconds = ($h * 3600) + ($m * 60);
        return Wattpilot_SendSecure($hash, "ftt", int($seconds));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{password}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{password} <secret>"
            if !defined($a[2]) || $a[2] eq "";

        my $password_err = Wattpilot_StoreNewPassword($hash, $a[2]);
        return $password_err if defined $password_err;

        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_InvalidateSession($hash);
        Wattpilot_ApplyConfiguredState($hash, 1);
        return undef;
    }

    return "Unknown argument $cmd, choose one of "
        . "$WATTPILOT_COMMAND_NAME{password} "
        . "$WATTPILOT_COMMAND_NAME{force_state}:neutral,off,on "
        . "$WATTPILOT_COMMAND_NAME{charging_current}:slider,6,1,32 "
        . "$WATTPILOT_COMMAND_NAME{charging_mode}:default,eco,nextTrip "
        . "$WATTPILOT_COMMAND_NAME{pv_surplus_start_power} "
        . "$WATTPILOT_COMMAND_NAME{pv_surplus_enabled}:0,1 "
        . "$WATTPILOT_COMMAND_NAME{zero_feed_in_enabled}:0,1 "
        . "$WATTPILOT_COMMAND_NAME{pv_control_preference}:preferFromGrid,default,preferToGrid "
        . "$WATTPILOT_COMMAND_NAME{phase_switch_mode}:auto,force1,force3 "
        . "$WATTPILOT_COMMAND_NAME{three_phase_switch_power} "
        . "$WATTPILOT_COMMAND_NAME{phase_switch_delay} "
        . "$WATTPILOT_COMMAND_NAME{minimum_phase_switch_interval} "
        . "$WATTPILOT_COMMAND_NAME{minimum_charge_time} "
        . "$WATTPILOT_COMMAND_NAME{charging_pause_allowed}:0,1 "
        . "$WATTPILOT_COMMAND_NAME{minimum_charging_pause_duration} "
        . "$WATTPILOT_COMMAND_NAME{minimum_charging_interval} "
        . "$WATTPILOT_COMMAND_NAME{reconnect} "
        . "$WATTPILOT_COMMAND_NAME{next_trip_time}";
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
    return undef if !defined($request_id) || ref($request_id);
    my $normalized = "$request_id";
    $normalized =~ s/sm$//;
    return $normalized =~ /^\d+$/ ? int($normalized) : undef;
}

sub Wattpilot_ClearCommandState($) {
    my ($hash) = @_;
    my $pending = $hash->{helper}{pendingRequests};
    Wattpilot_CancelTimer($hash, 'command_timeout')
        if ref($pending) eq 'HASH' && keys %$pending;
    delete $hash->{helper}{pendingRequests};
    delete $hash->{helper}{authenticated};
    delete $hash->{helper}{authPending};
    delete $hash->{helper}{authHashMode};
}

sub Wattpilot_ClearConnectionState($) {
    my ($hash) = @_;
    Wattpilot_ClearCommandState($hash);
    delete $hash->{helper}{deviceType};
    delete $hash->{helper}{protocol};
    delete $hash->{helper}{jsonBuffer};
}

sub Wattpilot_AbortAuthentication($$) {
    my ($hash, $state) = @_;
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
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
    Wattpilot_ClearConnectionState($hash);
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
            Wattpilot_InvalidateSession($hash);
            RemoveInternalTimer($hash, 'Wattpilot_Connect');
            RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
            delete $hash->{helper}{pendingReconnectAfterOpen};
            readingsSingleUpdate($hash, $WATTPILOT_READING_NAME{state}, $WATTPILOT_LIFECYCLE_STATE{disabled}, 1);
        } elsif($cmd eq "del" || $attrVal eq "0") {
            delete $hash->{helper}{timeoutRetryUsed};
            Wattpilot_InvalidateSession($hash);
            Wattpilot_ApplyConfiguredState($hash, 1, 0);
        }
    }

    if (($attrName eq "authHash" || $attrName eq "authHashCost")
        && ($cmd eq "set" || $cmd eq "del")) {
        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_InvalidateSession($hash);
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

    if ($attrName eq "rawJsonLog" && $cmd eq "set" && $attrVal eq "1") {
        Log3 $name, 1, "Wattpilot ($name) - WARNING: raw JSON logging was requested; it becomes active only with verbose=5 and may then contain sensitive authentication, network, device, and operational data";
    }
    if ($attrName eq "verbose" && $cmd eq "set" && defined($attrVal) && $attrVal >= 5
        && AttrVal($name, "rawJsonLog", 0) eq "1") {
        Log3 $name, 1, "Wattpilot ($name) - WARNING: raw JSON logging is active and may contain sensitive authentication, network, device, and operational data";
    }

    if($attrName eq "interval") {
        # Hier könnte Logik stehen, falls das Intervall sofortige Aktionen erfordert
    }

    if ($attrName eq "update_while_idle") {
        my $enabled = $cmd eq "set" && defined($attrVal) && $attrVal eq "1";
        if ($enabled) {
            if (($hash->{helper}{car_state} // 0) != 2
                && !$hash->{helper}{idleRefreshAttempted}
                && Wattpilot_NrgReadingsNeedIdleRefresh($hash)) {
                Wattpilot_StartIdleRefreshWindow($hash, 1);
            }
        } else {
            Wattpilot_StopIdleRefresh($hash);
        }
    }

    return undef;
}

sub Wattpilot_ValidateAttribute($$) {
    my ($attr_name, $attr_value) = @_;

    my %boolean_attribute = map { $_ => 1 } qw(
        debug update_while_idle disable rawJsonLog
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

    if ($attr_name eq "defaultAmp") {
        return "defaultAmp must be an integer from 6 to 32"
            if !defined($attr_value)
            || $attr_value !~ /^\d+$/
            || $attr_value < 6
            || $attr_value > 32;
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
    die "Invalid announced auth hash" if !Wattpilot_IsScalarString($json->{hash});
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
  <!-- BEGIN 2.0 migration names -->
  <table class="block wide">
    <tr><th>Type</th><th>1.x name</th><th>2.0 name</th></tr>
    <tr><td>Reading</td><td><code>state</code></td><td><code>state</code></td></tr>
    <tr><td>Reading</td><td><code>version</code></td><td><code>firmwareVersion</code></td></tr>
    <tr><td>Reading</td><td><code>authHashMode</code></td><td><code>authHashMode</code></td></tr>
    <tr><td>Reading</td><td><code>CarState</code></td><td><code>carState</code></td></tr>
    <tr><td>Reading</td><td><code>Laden_starten</code></td><td><code>forceState</code></td></tr>
    <tr><td>Reading</td><td><code>Strom</code></td><td><code>chargingCurrent</code></td></tr>
    <tr><td>Reading</td><td><code>Modus</code></td><td><code>chargingMode</code></td></tr>
    <tr><td>Reading</td><td><code>Zeit_NextTrip</code></td><td><code>nextTripTime</code></td></tr>
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
    Set the password separately with <code>set &lt;name&gt; password &lt;secret&gt;</code>.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; password &lt;secret&gt;</code><br>
        Stores the password under stable FUUID-based keys and starts a controlled reconnect. Rename does not rewrite credentials. Password replacement and deletion use two-key transactions with rollback. Storage errors remain distinguishable from a missing password.</li>
    <li><code>set &lt;name&gt; chargingCurrent &lt;6-32&gt;</code><br>
        Sends protocol key <code>amp</code>. Only integer values from 6 through 32 are accepted.</li>
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
    <li><code>set &lt;name&gt; phaseSwitchMode &lt;auto|force1|force3&gt;</code><br>
        Sends <code>psm=0</code>, <code>psm=1</code>, or <code>psm=2</code>.</li>
    <li><code>set &lt;name&gt; threePhaseSwitchPower &lt;watts&gt;</code><br>
        Sends a non-negative finite numeric value through <code>spl3</code>. The public unit is watts.</li>
    <li><code>set &lt;name&gt; phaseSwitchDelay &lt;seconds&gt;</code><br>
        Converts the non-negative finite value exactly to whole milliseconds and sends <code>mpwst</code>.</li>
    <li><code>set &lt;name&gt; minimumPhaseSwitchInterval &lt;seconds&gt;</code><br>
        Converts the non-negative finite value exactly to whole milliseconds and sends <code>mptwt</code>.</li>
    <li><code>set &lt;name&gt; minimumChargeTime &lt;seconds&gt;</code><br>
        Converts the non-negative finite value exactly to whole milliseconds and sends <code>fmt</code>.</li>
    <li><code>set &lt;name&gt; chargingPauseAllowed &lt;0|1&gt;</code><br>
        Sends the JSON boolean protocol field <code>fap</code>.</li>
    <li><code>set &lt;name&gt; minimumChargingPauseDuration &lt;seconds&gt;</code><br>
        Converts the non-negative finite value exactly to whole milliseconds and sends <code>mcpd</code>.</li>
    <li><code>set &lt;name&gt; minimumChargingInterval &lt;seconds&gt;</code><br>
        Converts the non-negative finite value exactly to whole milliseconds and sends <code>mci</code>.</li>
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
        Rate limit for the voltage, current, and power group derived from <code>nrg</code>. <code>0</code> disables rate limiting.</li>
    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> keeps voltage, current, and power readings derived from <code>nrg</code> passive while not charging. <code>1</code> processes real incoming idle values. After a charging-to-idle transition, one valid device-supplied <code>nrg</code> may bypass the rate limit. If none arrives within 30 seconds, the module performs at most one controlled reconnect for that idle episode. No unverified polling command is sent and no zero value is invented. <code>energyTotal</code> and <code>energySincePlugIn</code> update whenever their fields arrive and are not gated by this attribute.</li>
    <li><code>disable &lt;0|1&gt;</code><br>
        Disables the module and closes the connection when set to <code>1</code>.</li>
    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Exact JSON is logged only with both <code>rawJsonLog=1</code> and <code>verbose=5</code>. This can expose sensitive authentication, network, device, and operational data. DevIo/HttpUtils core logs may still contain endpoint details at high verbosity.</li>
    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Selects authentication hashing. <code>auto</code> accepts announced PBKDF2 or bcrypt; a missing hash selects PBKDF2 only for the evidenced predecessor <code>devicetype=wattpilot</code>, protocol-2 profile. Changing the attribute invalidates the current session and schedules one fresh login when possible.</li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt cost for newly derived authentication hashes. Changing it invalidates the current session.</li>
    <li><code>debug &lt;0|1&gt;</code><br>
        Retained attribute without separate runtime handling in the current implementation.</li>
    <li><code>defaultAmp &lt;6-32&gt;</code><br>
        Retained attribute without separate runtime handling in the current implementation.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Lifecycle state: <code>disabled</code>, <code>passwordMissing</code>, <code>credentialError</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connectionFailed</code>, <code>authFailed</code>, <code>authTimeout</code>, <code>initializationTimeout</code>, <code>authSequenceInvalid</code>, <code>authConfigMissing</code>, <code>authChallengeInvalid</code>, <code>authHashUnsupported</code>, <code>authHashFailed</code>, <code>authHashStoreFailed</code>, or <code>authNonceFailed</code>.</li>
    <li><code>firmwareVersion</code><br>Firmware/version string reported by the device <code>hello</code> message.</li>
    <li><code>authHashMode</code><br>Effective authentication mode: <code>pbkdf2</code> or <code>bcrypt</code>.</li>
    <li><code>carState</code><br><code>unknown</code>, <code>idle</code>, <code>charging</code>, <code>waitingForCar</code>, <code>complete</code>, <code>error</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>forceState</code><br><code>neutral</code>, <code>off</code>, <code>on</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>chargingCurrent</code><br>Configured/requested charging current; interpreted as amperes.</li>
    <li><code>chargingMode</code><br><code>default</code>, <code>eco</code>, <code>nextTrip</code>, or <code>unknown:&lt;raw-value&gt;</code>.</li>
    <li><code>chargingAllowed</code><br>Boolean protocol field <code>alw</code>, exposed as <code>0</code> or <code>1</code>. A pinned Wattpilot-specific source describes it as the current charging permission; the Flex capture confirms only the boolean field and value shape.</li>
    <li><code>chargingDecisionCode</code>, <code>chargingDecisionInternalCode</code><br>Unmodified integer values from <code>modelStatus</code> and <code>msi</code>.</li>
    <li><code>chargingDecision</code>, <code>chargingDecisionInternal</code><br>Compatibility text mappings for the two raw codes. Unknown values are exposed as <code>unknown:&lt;code&gt;</code>. The mapping is derived from the pinned official go-e <code>modelStatus</code> enum and Wattpilot-specific third-party evidence for <code>msi</code>; it is not an official Fronius Flex specification. The pinned third-party source calls <code>msi</code> an internal decision variant, but the exact relationship, evaluation order, precedence, and any role of <code>cpDisabledRequest</code> are not confirmed for Wattpilot Flex. In particular, the module does not claim that <code>modelStatus</code> is necessarily the final/effective decision or that <code>msi</code> is necessarily a pre-CP decision. If the values differ, treat them as two device-supplied diagnostic values; do not infer a causal chain from the module documentation.</li>
    <li><code>errorCode</code><br>Raw integer value from <code>err</code>; no error enum is assumed.</li>
    <li><code>maximumCurrentLimit</code>, <code>temperatureCurrentLimit</code>, <code>minimumChargingCurrent</code><br>Raw integer values from <code>ama</code>, <code>amt</code>, and <code>mca</code>. Their current-limit interpretation and ampere unit come from pinned third-party Wattpilot evidence and are not independently proven by the sanitized Flex capture.</li>
    <li><code>pvSurplusStartPower</code><br>Non-negative finite numeric value from <code>fst</code>, exposed in watts. Pinned official go-e API metadata and pinned Wattpilot-specific evidence describe it as the PV-surplus start power and as writable; the observed Wattpilot Flex 43.4 value is <code>1400</code>. This evidence supports the compatibility mapping but is not an official Fronius Flex API specification.</li>
    <li><code>pvSurplusEnabled</code>, <code>zeroFeedInEnabled</code>, <code>chargingPauseAllowed</code><br>Boolean fields <code>fup</code>, <code>fzf</code>, and <code>fap</code>, exposed as <code>0</code> or <code>1</code>.</li>
    <li><code>pvControlPreference</code><br><code>preferFromGrid</code>, <code>default</code>, <code>preferToGrid</code>, or <code>unknown:&lt;raw-value&gt;</code> from <code>frm</code>.</li>
    <li><code>phaseSwitchMode</code><br><code>auto</code>, <code>force1</code>, <code>force3</code>, or <code>unknown:&lt;raw-value&gt;</code> from <code>psm</code>.</li>
    <li><code>threePhaseSwitchPower</code><br>Non-negative finite numeric value from <code>spl3</code>, exposed in watts.</li>
    <li><code>phaseSwitchDelay</code>, <code>minimumPhaseSwitchInterval</code>, <code>minimumChargeTime</code>, <code>minimumChargingPauseDuration</code>, <code>minimumChargingInterval</code><br>Non-negative finite values from <code>mpwst</code>, <code>mptwt</code>, <code>fmt</code>, <code>mcpd</code>, and <code>mci</code>, converted from protocol milliseconds to public seconds.</li>
    <li><code>pvBatteryStateOfCharge</code><br>Stationary PV-battery state of charge from <code>fbuf_akkuSOC</code>, accepted only as a finite percentage from <code>0</code> through <code>100</code>.</li>
    <li><code>pvBatteryPower</code><br>Unmodified signed finite value from <code>fbuf_pAkku</code>, exposed in watts. The module does not assign an unverified charge/discharge direction to the sign.</li>
    <li><code>pvBatteryModeCode</code><br>Unmodified non-negative integer code from <code>fbuf_akkuMode</code>. No text enum is invented. These stationary-battery readings have no public setters in version 2.0.6; candidate writable fields such as <code>fam</code> remain excluded until verified.</li>
    <li>The 24 operational status and configuration readings above update immediately and are not gated by <code>interval</code> or <code>update_while_idle</code>. Missing, <code>null</code>, or type-invalid fields leave existing readings unchanged.</li>
  </ul>
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
    <li><code>nextTripTime</code><br>Protocol value rendered as <code>HH:MM</code>; interpreted as seconds after midnight.</li>
    <li><code>energyTotal</code><br>Protocol <code>eto</code> divided by 1000 and formatted with two decimals. The Wh-to-kWh interpretation is implementation evidence, not proven by the sanitized Flex capture.</li>
    <li><code>energySincePlugIn</code><br>Protocol <code>wh</code> formatted with two decimals; interpreted as Wh.</li>
    <li>The two energy readings update independently of <code>interval</code> and <code>update_while_idle</code>. Those controls apply only to the <code>nrg</code>-derived voltage, current, and power group.</li>
    <li><code>voltageL1</code>, <code>voltageL2</code>, <code>voltageL3</code><br>Values from <code>nrg[0..2]</code>, interpreted as volts.</li>
    <li><code>currentL1</code>, <code>currentL2</code>, <code>currentL3</code><br>Values from <code>nrg[4..6]</code>, interpreted as amperes.</li>
    <li><code>powerL1</code>, <code>powerL2</code>, <code>powerL3</code><br>Values from <code>nrg[7..9]</code>, interpreted as watts.</li>
    <li><code>power</code><br>Value from <code>nrg[11]</code>, interpreted as total watts.</li>
    <li><code>lastCommandRequestId</code>, <code>lastCommandStatus</code>, <code>lastCommandError</code><br>
        Correlation and result of the most recent secured command. Status values are <code>pending</code>, <code>success</code>, <code>failed</code>, or <code>timeout</code>.</li>
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
  <!-- BEGIN 2.0 migration names -->
  <table class="block wide">
    <tr><th>Typ</th><th>1.x-Name</th><th>2.0-Name</th></tr>
    <tr><td>Reading</td><td><code>state</code></td><td><code>state</code></td></tr>
    <tr><td>Reading</td><td><code>version</code></td><td><code>firmwareVersion</code></td></tr>
    <tr><td>Reading</td><td><code>authHashMode</code></td><td><code>authHashMode</code></td></tr>
    <tr><td>Reading</td><td><code>CarState</code></td><td><code>carState</code></td></tr>
    <tr><td>Reading</td><td><code>Laden_starten</code></td><td><code>forceState</code></td></tr>
    <tr><td>Reading</td><td><code>Strom</code></td><td><code>chargingCurrent</code></td></tr>
    <tr><td>Reading</td><td><code>Modus</code></td><td><code>chargingMode</code></td></tr>
    <tr><td>Reading</td><td><code>Zeit_NextTrip</code></td><td><code>nextTripTime</code></td></tr>
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
    Das Passwort wird separat mit <code>set &lt;name&gt; password &lt;secret&gt;</code> gesetzt.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; password &lt;secret&gt;</code><br>
        Speichert das Passwort unter stabilen FUUID-basierten Schlüsseln und startet einen kontrollierten Reconnect. Rename schreibt Credentials nicht um. Passwortänderung und Löschung verwenden Zwei-Schlüssel-Transaktionen mit Rollback. Speicherfehler bleiben von einem fehlenden Passwort unterscheidbar.</li>
    <li><code>set &lt;name&gt; chargingCurrent &lt;6-32&gt;</code><br>
        Sendet den Protokollschlüssel <code>amp</code>. Akzeptiert werden nur ganze Werte von 6 bis 32.</li>
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
    <li><code>set &lt;name&gt; phaseSwitchMode &lt;auto|force1|force3&gt;</code><br>
        Sendet <code>psm=0</code>, <code>psm=1</code> oder <code>psm=2</code>.</li>
    <li><code>set &lt;name&gt; threePhaseSwitchPower &lt;Watt&gt;</code><br>
        Sendet einen nicht negativen, endlichen Zahlenwert über <code>spl3</code>. Die öffentliche Einheit ist Watt.</li>
    <li><code>set &lt;name&gt; phaseSwitchDelay &lt;Sekunden&gt;</code><br>
        Rechnet den nicht negativen, endlichen Wert exakt in ganze Millisekunden um und sendet <code>mpwst</code>.</li>
    <li><code>set &lt;name&gt; minimumPhaseSwitchInterval &lt;Sekunden&gt;</code><br>
        Rechnet den nicht negativen, endlichen Wert exakt in ganze Millisekunden um und sendet <code>mptwt</code>.</li>
    <li><code>set &lt;name&gt; minimumChargeTime &lt;Sekunden&gt;</code><br>
        Rechnet den nicht negativen, endlichen Wert exakt in ganze Millisekunden um und sendet <code>fmt</code>.</li>
    <li><code>set &lt;name&gt; chargingPauseAllowed &lt;0|1&gt;</code><br>
        Sendet das boolesche JSON-Protokollfeld <code>fap</code>.</li>
    <li><code>set &lt;name&gt; minimumChargingPauseDuration &lt;Sekunden&gt;</code><br>
        Rechnet den nicht negativen, endlichen Wert exakt in ganze Millisekunden um und sendet <code>mcpd</code>.</li>
    <li><code>set &lt;name&gt; minimumChargingInterval &lt;Sekunden&gt;</code><br>
        Rechnet den nicht negativen, endlichen Wert exakt in ganze Millisekunden um und sendet <code>mci</code>.</li>
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
        Rate-Limit für die aus <code>nrg</code> abgeleitete Spannungs-, Strom- und Leistungsgruppe. <code>0</code> deaktiviert die Begrenzung.</li>
    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> belässt die aus <code>nrg</code> abgeleiteten Spannungs-, Strom- und Leistungsreadings im nicht ladenden Zustand passiv. <code>1</code> verarbeitet echte eingehende Idle-Werte. Nach einem Wechsel von Charging zu Idle darf ein gültiges, vom Gerät geliefertes <code>nrg</code> das Rate-Limit einmalig umgehen. Fehlt es 30 Sekunden lang, führt das Modul für diese Idle-Episode höchstens einen kontrollierten Reconnect aus. Es wird kein unbelegtes Polling-Kommando gesendet und kein Nullwert erfunden. <code>energyTotal</code> und <code>energySincePlugIn</code> werden bei eingehenden Feldern unabhängig von diesem Attribut aktualisiert.</li>
    <li><code>disable &lt;0|1&gt;</code><br>
        Deaktiviert das Modul und trennt bei <code>1</code> die Verbindung.</li>
    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Exaktes JSON wird nur mit <code>rawJsonLog=1</code> und <code>verbose=5</code> protokolliert. Dabei können sensible Authentifizierungs-, Netzwerk-, Geräte- und Betriebsdaten sichtbar werden. DevIo-/HttpUtils-Core-Logs können bei hohem Verbose weiterhin Endpoint-Details enthalten.</li>
    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Wählt das Authentifizierungsverfahren. <code>auto</code> akzeptiert angekündigtes PBKDF2 oder bcrypt; ein fehlender Hash wählt nur beim belegten Vorgängerprofil <code>devicetype=wattpilot</code>, Protokoll 2, PBKDF2. Eine Änderung verwirft die aktuelle Sitzung und plant nach Möglichkeit genau eine frische Anmeldung.</li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt-Kostenfaktor für neu abgeleitete Authentifizierungs-Hashes. Eine Änderung verwirft die aktuelle Sitzung.</li>
    <li><code>debug &lt;0|1&gt;</code><br>
        Beibehaltenes Attribut ohne eigene Runtime-Behandlung im aktuellen Stand.</li>
    <li><code>defaultAmp &lt;6-32&gt;</code><br>
        Beibehaltenes Attribut ohne eigene Runtime-Behandlung im aktuellen Stand.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Lifecycle-Zustand: <code>disabled</code>, <code>passwordMissing</code>, <code>credentialError</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connectionFailed</code>, <code>authFailed</code>, <code>authTimeout</code>, <code>initializationTimeout</code>, <code>authSequenceInvalid</code>, <code>authConfigMissing</code>, <code>authChallengeInvalid</code>, <code>authHashUnsupported</code>, <code>authHashFailed</code>, <code>authHashStoreFailed</code> oder <code>authNonceFailed</code>.</li>
    <li><code>firmwareVersion</code><br>Firmware-/Versionsstring aus der <code>hello</code>-Nachricht des Geräts.</li>
    <li><code>authHashMode</code><br>Tatsächlich verwendetes Verfahren: <code>pbkdf2</code> oder <code>bcrypt</code>.</li>
    <li><code>carState</code><br><code>unknown</code>, <code>idle</code>, <code>charging</code>, <code>waitingForCar</code>, <code>complete</code>, <code>error</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>forceState</code><br><code>neutral</code>, <code>off</code>, <code>on</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>chargingCurrent</code><br>Konfigurierter/angeforderter Ladestrom; als Ampere interpretiert.</li>
    <li><code>chargingMode</code><br><code>default</code>, <code>eco</code>, <code>nextTrip</code> oder <code>unknown:&lt;Rohwert&gt;</code>.</li>
    <li><code>chargingAllowed</code><br>Boolesches Protokollfeld <code>alw</code>, ausgegeben als <code>0</code> oder <code>1</code>. Eine gepinnte Wattpilot-spezifische Quelle beschreibt es als aktuelle Ladefreigabe; der Flex-Mitschnitt bestätigt nur Feld, Typ und Wertform.</li>
    <li><code>chargingDecisionCode</code>, <code>chargingDecisionInternalCode</code><br>Unveränderte Ganzzahlwerte aus <code>modelStatus</code> und <code>msi</code>.</li>
    <li><code>chargingDecision</code>, <code>chargingDecisionInternal</code><br>Kompatibilitäts-Klartextwerte für die beiden Rohcodes. Unbekannte Werte erscheinen als <code>unknown:&lt;Code&gt;</code>. Die Zuordnung stammt aus der gepinnten offiziellen go-e-Enum für <code>modelStatus</code> und Wattpilot-spezifischer Drittquellenevidenz für <code>msi</code>; sie ist keine offizielle Fronius-Flex-Spezifikation. Die gepinnte Drittquelle bezeichnet <code>msi</code> als interne Entscheidungsvariante; die genaue Beziehung, Auswertungsreihenfolge, Priorität und eine mögliche Rolle von <code>cpDisabledRequest</code> sind für Wattpilot Flex jedoch nicht bestätigt. Insbesondere behauptet das Modul weder, dass <code>modelStatus</code> zwingend die abschließende/wirksame Entscheidung ist, noch dass <code>msi</code> zwingend eine Entscheidung vor der CP-Ebene darstellt. Weichen die Werte voneinander ab, sind sie als zwei vom Gerät gelieferte Diagnosewerte zu behandeln; aus der Moduldokumentation darf keine Kausalkette abgeleitet werden.</li>
    <li><code>errorCode</code><br>Unveränderter Ganzzahlwert aus <code>err</code>; es wird keine Fehler-Enum angenommen.</li>
    <li><code>maximumCurrentLimit</code>, <code>temperatureCurrentLimit</code>, <code>minimumChargingCurrent</code><br>Unveränderte Ganzzahlwerte aus <code>ama</code>, <code>amt</code> und <code>mca</code>. Die Interpretation als Stromgrenzen in Ampere stammt aus gepinnter Wattpilot-Drittquellenevidenz und ist durch den bereinigten Flex-Mitschnitt nicht unabhängig bewiesen.</li>
    <li><code>pvSurplusStartPower</code><br>Nicht negativer, endlicher Zahlenwert aus <code>fst</code>, ausgegeben in Watt. Gepinnte offizielle go-e-API-Metadaten und gepinnte Wattpilot-spezifische Evidenz beschreiben ihn als Startleistung für PV-Überschussladen und als schreibbar; beim beobachteten Wattpilot Flex 43.4 betrug der Wert <code>1400</code>. Diese Evidenz trägt die Kompatibilitätszuordnung, ist aber keine offizielle Fronius-Flex-API-Spezifikation.</li>
    <li><code>pvSurplusEnabled</code>, <code>zeroFeedInEnabled</code>, <code>chargingPauseAllowed</code><br>Boolesche Felder <code>fup</code>, <code>fzf</code> und <code>fap</code>, ausgegeben als <code>0</code> oder <code>1</code>.</li>
    <li><code>pvControlPreference</code><br><code>preferFromGrid</code>, <code>default</code>, <code>preferToGrid</code> oder <code>unknown:&lt;Rohwert&gt;</code> aus <code>frm</code>.</li>
    <li><code>phaseSwitchMode</code><br><code>auto</code>, <code>force1</code>, <code>force3</code> oder <code>unknown:&lt;Rohwert&gt;</code> aus <code>psm</code>.</li>
    <li><code>threePhaseSwitchPower</code><br>Nicht negativer, endlicher Zahlenwert aus <code>spl3</code>, ausgegeben in Watt.</li>
    <li><code>phaseSwitchDelay</code>, <code>minimumPhaseSwitchInterval</code>, <code>minimumChargeTime</code>, <code>minimumChargingPauseDuration</code>, <code>minimumChargingInterval</code><br>Nicht negative, endliche Werte aus <code>mpwst</code>, <code>mptwt</code>, <code>fmt</code>, <code>mcpd</code> und <code>mci</code>, von Protokoll-Millisekunden in öffentliche Sekunden umgerechnet.</li>
    <li><code>pvBatteryStateOfCharge</code><br>Ladezustand des stationären PV-Speichers aus <code>fbuf_akkuSOC</code>, nur als endlicher Prozentwert von <code>0</code> bis <code>100</code> akzeptiert.</li>
    <li><code>pvBatteryPower</code><br>Unveränderter vorzeichenbehafteter endlicher Wert aus <code>fbuf_pAkku</code>, ausgegeben in Watt. Das Modul weist dem Vorzeichen keine unbestätigte Lade-/Entladerichtung zu.</li>
    <li><code>pvBatteryModeCode</code><br>Unveränderter nicht negativer Ganzzahlcode aus <code>fbuf_akkuMode</code>. Es wird keine Klartext-Enum erfunden. Für diese stationären Speicherreadings gibt es in Version 2.0.6 keine öffentlichen Setter; Kandidaten wie <code>fam</code> bleiben bis zur Verifikation ausgeschlossen.</li>
    <li>Die 24 operativen Status- und Konfigurationsreadings werden sofort aktualisiert und unterliegen weder <code>interval</code> noch <code>update_while_idle</code>. Fehlende, <code>null</code>- oder typfalsche Felder lassen bestehende Readings unverändert.</li>
  </ul>
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
    <li><code>nextTripTime</code><br>Protokollwert als <code>HH:MM</code>; als Sekunden nach Mitternacht interpretiert.</li>
    <li><code>energyTotal</code><br>Protokollwert <code>eto</code> geteilt durch 1000 und mit zwei Nachkommastellen formatiert. Die Interpretation Wh nach kWh ist Implementierungswissen und durch den bereinigten Flex-Mitschnitt nicht bewiesen.</li>
    <li><code>energySincePlugIn</code><br>Protokollwert <code>wh</code> mit zwei Nachkommastellen; als Wh interpretiert.</li>
    <li>Die beiden Energie-Readings werden unabhängig von <code>interval</code> und <code>update_while_idle</code> aktualisiert. Diese Steuerungen gelten nur für die aus <code>nrg</code> abgeleitete Spannungs-, Strom- und Leistungsgruppe.</li>
    <li><code>voltageL1</code>, <code>voltageL2</code>, <code>voltageL3</code><br>Werte aus <code>nrg[0..2]</code>, als Volt interpretiert.</li>
    <li><code>currentL1</code>, <code>currentL2</code>, <code>currentL3</code><br>Werte aus <code>nrg[4..6]</code>, als Ampere interpretiert.</li>
    <li><code>powerL1</code>, <code>powerL2</code>, <code>powerL3</code><br>Werte aus <code>nrg[7..9]</code>, als Watt interpretiert.</li>
    <li><code>power</code><br>Wert aus <code>nrg[11]</code>, als Gesamtleistung in Watt interpretiert.</li>
    <li><code>lastCommandRequestId</code>, <code>lastCommandStatus</code>, <code>lastCommandError</code><br>
        Korrelation und Ergebnis des letzten gesicherten Befehls. Statuswerte sind <code>pending</code>, <code>success</code>, <code>failed</code> oder <code>timeout</code>.</li>
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
  "version": "v2.0.6",
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
