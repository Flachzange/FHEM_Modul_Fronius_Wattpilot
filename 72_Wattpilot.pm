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
# A copy is found in the textfile GPL.txt and important notices to the license
# from the author is found in LICENSE.txt distributed with these scripts.
#
# Author: Dennis Gramespacher
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

my $WATTPILOT_VERSION = '1.6.0';
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
    firmware_version        => 'version',
    auth_hash_mode          => 'authHashMode',
    car_state               => 'CarState',
    force_state             => 'Laden_starten',
    charging_current        => 'Strom',
    charging_mode           => 'Modus',
    next_trip_time          => 'Zeit_NextTrip',
    energy_total            => 'EnergyTotal',
    energy_since_plug_in    => 'Energie_seit_Anstecken',
    voltage_l1              => 'Voltage_L1',
    voltage_l2              => 'Voltage_L2',
    voltage_l3              => 'Voltage_L3',
    current_l1              => 'Current_L1',
    current_l2              => 'Current_L2',
    current_l3              => 'Current_L3',
    power_l1                => 'Power_L1',
    power_l2                => 'Power_L2',
    power_l3                => 'Power_L3',
    power                   => 'power',
    last_command_request_id => 'lastCommandRequestId',
    last_command_status     => 'lastCommandStatus',
    last_command_error      => 'lastCommandError',
);

my %WATTPILOT_COMMAND_NAME = (
    password         => 'Password',
    force_state      => 'Laden_starten',
    charging_current => 'Strom',
    charging_mode    => 'Modus',
    next_trip_time   => 'Zeit_NextTrip',
);

my %WATTPILOT_CAR_STATE = (
    0 => 'Unknown',
    1 => 'Idle',
    2 => 'Charging',
    3 => 'WaitCar',
    4 => 'Complete',
    5 => 'Error',
);

my %WATTPILOT_FORCE_STATE = (
    0 => 'Neutral',
    1 => 'Stop',
    2 => 'Start',
);

my %WATTPILOT_CHARGING_MODE = (
    3 => 'Default',
    4 => 'Eco',
    5 => 'NextTrip',
);

my %WATTPILOT_FORCE_COMMAND_VALUE = (
    Start => 2,
    Stop  => 1,
);

my %WATTPILOT_CHARGING_MODE_VALUE = reverse %WATTPILOT_CHARGING_MODE;

my %WATTPILOT_LIFECYCLE_STATE = (
    initialized            => 'Initialized',
    disabled               => 'disabled',
    credential_error       => 'credential error',
    password_missing       => 'password missing',
    password_stored        => 'password stored',
    disconnected           => 'disconnected',
    connecting             => 'connecting',
    connection_failed      => 'connection failed',
    authenticating         => 'authenticating',
    initializing           => 'initializing',
    connected              => 'connected',
    auth_failed            => 'auth_failed',
    auth_timeout           => 'auth_timeout',
    initialization_timeout => 'initialization_timeout',
    auth_sequence_invalid  => 'auth_sequence_invalid',
    auth_config_missing    => 'auth_config_missing',
    auth_challenge_invalid => 'auth_challenge_invalid',
    auth_hash_unsupported  => 'auth_hash_unsupported',
    auth_hash_failed       => 'auth_hash_failed',
    auth_hash_store_failed => 'auth_hash_store_failed',
    auth_nonce_failed      => 'auth_nonce_failed',
);

eval {
    require Crypt::Bcrypt;
    Crypt::Bcrypt->import(qw(bcrypt));
    1;
};


sub Wattpilot_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = \&Wattpilot_Define;
    $hash->{UndefFn}  = \&Wattpilot_Undefine;
    $hash->{DeleteFn} = \&Wattpilot_Delete;
    $hash->{RenameFn} = \&Wattpilot_Rename;
    $hash->{SetFn}    = \&Wattpilot_Set;
    $hash->{GetFn}    = \&Wattpilot_Get;
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
        chargingModes => { %WATTPILOT_CHARGING_MODE },
        lifecycle      => { %WATTPILOT_LIFECYCLE_STATE },
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

    if(@a < 3) {
        return "Usage: define <name> Wattpilot <IP> [Serial]";
    }

    my $name = $a[0];
    my $ip = $a[2];
    my $serial = $a[3] if (defined $a[3]);

    delete $hash->{helper}{undefined};
    delete $hash->{helper}{deleting};
    delete $hash->{helper}{shuttingDown};
    delete $hash->{helper}{timeoutRetryUsed};
    Wattpilot_NextLifecycleGeneration($hash);

    # DevIo WebSocket URL Format: ws:host:port/path
    $hash->{DeviceName} = "ws:$ip:80/ws";
    $hash->{SERIAL} = $serial;
    # DevIo privacy masks only its initial opening line. devioLoglevel reduces
    # direct DevIo diagnostics, but cannot control transitive HttpUtils logs.
    $hash->{devioLoglevel} = 6;

    $hash->{STATE} = $WATTPILOT_LIFECYCLE_STATE{initialized};

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
            if (delete $hash->{helper}{pendingReconnectAfterOpen}) {
                Wattpilot_ScheduleConnect($hash, 1);
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

sub Wattpilot_IsNumber($) {
    my ($value) = @_;
    return 0 if !Wattpilot_IsScalarString($value);
    return $value =~ /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
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
    my %integer = map { $_ => 1 } qw(car frc ftt amp lmo);
    my %number = map { $_ => 1 } qw(eto wh);
    for my $key (keys %integer) {
        next if !exists($status{$key}) || !defined($status{$key});
        if (!Wattpilot_IsInteger($status{$key})) {
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
    my %known_type = map { $_ => 1 } qw(hello authRequired authSuccess authError fullStatus deltaStatus response);
    Log3 $name, 4, "Wattpilot ($name) - Received JSON message type=" . ($known_type{$type} ? $type : "unknown");

    if ($type eq 'hello') {
        $hash->{helper}{deviceType} = $json->{devicetype}
            if Wattpilot_IsScalarString($json->{devicetype});
        $hash->{helper}{protocol} = int($json->{protocol})
            if Wattpilot_IsInteger($json->{protocol});
        $hash->{SERIAL} = $json->{serial}
            if (!$hash->{SERIAL} && Wattpilot_IsScalarString($json->{serial}) && $json->{serial} =~ /^\d+$/);
        if (Wattpilot_IsScalarString($json->{version})) {
            $hash->{VERSION} = $json->{version};
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
    } else {
        Log3 $name, 3, "Wattpilot ($name) - Ignoring unsupported JSON message type=unknown";
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
            $WATTPILOT_CAR_STATE{$car_value} // $WATTPILOT_CAR_STATE{0});
        $hash->{helper}{car_state} = $car_value;
    }

    if (defined $status->{frc}) {
        my $force_value = int($status->{frc});
        my $force_state = exists($WATTPILOT_FORCE_STATE{$force_value})
            ? $WATTPILOT_FORCE_STATE{$force_value}
            : 'Unknown(' . $status->{frc} . ')';
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
            $WATTPILOT_CHARGING_MODE{$mode_value} // $status->{lmo});
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
    if (Wattpilot_ShouldProcessElectricalReadings(
            $hash, $status, $message_type, $now)) {
        Wattpilot_UpdateEnergyReadings($hash, $status);
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



sub Wattpilot_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $cmd = $a[1] // '';
    my $val = $a[2];

    return "Device is disabled" if(Wattpilot_IsDisabled($name));

    if($cmd eq $WATTPILOT_COMMAND_NAME{force_state}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{force_state} <Start|Stop>"
            if !defined($val) || !exists($WATTPILOT_FORCE_COMMAND_VALUE{$val});
        return Wattpilot_SendSecure(
            $hash, "frc", int($WATTPILOT_FORCE_COMMAND_VALUE{$val}));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{charging_current}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{charging_current} <6-32>"
            if !defined($val) || $val !~ /^(?:[6-9]|[12]\d|3[0-2])$/;
        return Wattpilot_SendSecure($hash, "amp", int($val));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{charging_mode}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{charging_mode} <Default|Eco|NextTrip>"
            if !defined $val;
        return "Unknown mode $val"
            if !exists $WATTPILOT_CHARGING_MODE_VALUE{$val};
        return Wattpilot_SendSecure(
            $hash, "lmo", $WATTPILOT_CHARGING_MODE_VALUE{$val});
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{next_trip_time}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{next_trip_time} <hh:mm>"
            if !defined($val)
            || $val !~ /^([0-1]?[0-9]|2[0-3]):([0-5][0-9])$/;
        my ($h, $m) = split(':', $val);
        my $seconds = ($h * 3600) + ($m * 60);
        return Wattpilot_SendSecure($hash, "ftt", int($seconds));
    } elsif ($cmd eq $WATTPILOT_COMMAND_NAME{password}) {
        return "Usage: set $name $WATTPILOT_COMMAND_NAME{password} <secret>"
            if !defined($a[2]) || $a[2] eq "";

        my $password_err = Wattpilot_StoreNewPassword($hash, $a[2]);
        return $password_err if defined $password_err;

        readingsSingleUpdate(
            $hash, $WATTPILOT_READING_NAME{state},
            $WATTPILOT_LIFECYCLE_STATE{password_stored}, 1);
        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_InvalidateSession($hash);
        Wattpilot_ApplyConfiguredState($hash, 1);
        return undef;
    }

    return "Unknown argument $cmd, choose one of "
        . "$WATTPILOT_COMMAND_NAME{password} "
        . "$WATTPILOT_COMMAND_NAME{force_state}:Start,Stop "
        . "$WATTPILOT_COMMAND_NAME{charging_current}:slider,6,1,32 "
        . "$WATTPILOT_COMMAND_NAME{charging_mode}:Default,Eco,NextTrip "
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

sub Wattpilot_Get($@) {
    my ($hash, @a) = @_;
    return undef;
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
  <li>This module controls a Fronius Wattpilot Wallbox via WebSocket API V2.</li>
  <li>It supports reading status values, setting charging modes, starting/stopping charging, and supports both PBKDF2 and bcrypt based authentication.</li>
  <li>Decoded input is limited to 1 MiB and at most 256 concatenated JSON documents, structurally framed, and type-checked. DevIo owns raw WebSocket-frame buffering; Wattpilot separately bounds logical JSON continuation. Omitted <code>deltaStatus</code> fields remain unchanged.</li>
  <br>

  <a name="Wattpilot-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Wattpilot &lt;IP-Address&gt; [&lt;Serial&gt;]</code>
    <br><br>
    Defines a Wattpilot device.<br>
    <b>&lt;IP-Address&gt;</b>: The local IP address of the Wattpilot (for example 192.0.2.10).<br>
    <b>&lt;Serial&gt;</b>: (Optional) The serial number of the device. If not provided, it will be taken from the <code>hello</code> message during connection setup.<br>
    <br>
    The password is no longer part of the device definition and must be set separately via <code>set &lt;name&gt; Password &lt;secret&gt;</code>.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; Password &lt;secret&gt;</code><br>
        Stores the password and derived authentication value exclusively under stable FUUID-based keys and starts a reconnect. Rename does not rewrite credentials. Password replacement and device deletion snapshot the two stable values first and roll back prior changes after a partial failure; an incomplete rollback is reported explicitly. Credential reads distinguish present, absent, and storage failure. Undefine, rename, reload, <code>rereadcfg</code>, and disable preserve credentials. Released 1.6.x versions are the final releases with name-based credential migration support. Version 2.0 requires a fresh definition and a new password operation; old name-based keys are not read or cleaned up automatically.</li>

    <li><code>set &lt;name&gt; Laden_starten &lt;Start|Stop&gt;</code><br>
        Manually starts or stops charging (corresponds to parameter <code>frc</code>). Start sends <code>2</code>, Stop sends <code>1</code>; the reading keeps the compatible labels <code>Start</code>/<code>Stop</code> and adds <code>Neutral</code> for value <code>0</code>.</li>

    <li><code>set &lt;name&gt; Strom &lt;6-32&gt;</code><br>
        Sets the charging current in ampere. Values outside the public range 6–32 are rejected before any message is sent.</li>

    <li><code>set &lt;name&gt; Modus &lt;Default|Eco|NextTrip&gt;</code><br>
        Changes the charging mode:<br>
        <ul>
          <li><b>Default</b>: Standard charging</li>
          <li><b>Eco</b>: PV surplus charging</li>
          <li><b>NextTrip</b>: Scheduled charging for next trip</li>
        </ul>
    </li>

    <li><code>set &lt;name&gt; Zeit_NextTrip &lt;hh:mm&gt;</code><br>
        Sets the planned departure time for NextTrip mode. Internally this is converted to seconds after midnight.</li>
  </ul>
  <br>

  <a name="Wattpilot-get"></a>
  <b>Get</b>
  <ul>
    <li>Currently no dedicated <code>get</code> commands are implemented.</li>
  </ul>
  <br>

  <a name="Wattpilot-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><code>interval &lt;seconds&gt;</code><br>
        Interval in seconds for updating high-frequency readings such as voltages and phase currents. <code>0</code> means no rate limiting.</li>

    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> keeps high-frequency <code>nrg</code>/power/current readings passive while the car is not charging. <code>1</code> processes real incoming idle values subject to <code>interval</code>. When charging changes to a valid non-charging <code>car</code> state, one authoritative idle <code>nrg</code> received in the same message or within 30 seconds bypasses the rate limit once so real zero values from the device clear stale readings. No protocol polling command is sent: no evidenced Wattpilot WebSocket request for all values or full status is known. If that 30-second window receives no valid <code>nrg</code>, the module closes the session and schedules at most one controlled reconnect for that idle episode. This is a bounded fallback inferred from third-party client behavior that initial status is server-pushed after login; it is not an official Fronius refresh feature. Missing fields, timeouts, disconnects, and failed refreshes never synthesize zero values.</li>

    <li><code>defaultAmp &lt;value&gt;</code><br>
        Default value for the current setting slider in the frontend.</li>

    <li><code>disable &lt;0|1&gt;</code><br>
        Disables the module completely. If set to <code>1</code>, the connection is closed.</li>

    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Default: <code>0</code>. Exact inbound and outbound JSON is logged only when this attribute is <code>1</code> and <code>verbose</code> is also <code>5</code>. This includes authentication and <code>securedMsg</code> frames. A central write path suppresses DevIo's own level-5 payload logging without persistently changing <code>verbose</code>. <code>DevIo_SimpleWrite(..., 2)</code> receives unpacked text; DevIo selects the WebSocket opcode from its connection and <code>$hash-&gt;{binary}</code>. Wattpilot-owned normal logs are redacted. Technical limit: DevIo's internal HttpUtils connection hash does not inherit <code>privacy</code> as <code>hideurl</code> or inherit <code>devioLoglevel</code>, so FHEM core may still log endpoint URLs, DNS/IP results, timeouts, and connection errors at levels 4 or 5; those core logs are outside the module's redaction guarantee. Enabling raw logging emits a warning because logs can contain sensitive authentication, network, device, and operational data. Never share this output without sanitizing it.</li>

    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Selects the password hashing method for authentication.<br>
        <ul>
          <li><b>auto</b>: Accept announced PBKDF2 or bcrypt. A missing hash selects PBKDF2 only for the evidenced legacy <code>devicetype=wattpilot</code>, protocol-2 profile; unknown modes are rejected.</li>
          <li><b>pbkdf2</b>: Force legacy PBKDF2 authentication</li>
          <li><b>bcrypt</b>: Force bcrypt authentication (used by newer Wattpilot Flex devices)</li>
        </ul>
        Changing or deleting this attribute immediately invalidates the current authentication and closes the connection. If the device is enabled and its password is readable, exactly one fresh login is scheduled before secured commands are accepted again; otherwise the state remains disabled, credential error, or password missing as applicable.
    </li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt cost used for newly derived authentication hashes. Changing or deleting it is authentication-relevant and therefore closes the current session and schedules exactly one fresh login when enabled and configured.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Current connection/authentication state, e.g. <code>disabled</code>, <code>password missing</code>, <code>credential error</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connection failed</code>, <code>auth_failed</code>, <code>auth_timeout</code>, or <code>initialization_timeout</code>. <code>connected</code> requires an open DevIo connection, successful authentication, and at least one valid post-authentication status message; <code>authSuccess</code> alone is not enough.</li>

    <li><code>version</code><br>
        Firmware / protocol version reported by the Wattpilot.</li>

    <li><code>authHashMode</code><br>
        Effective authentication hash mode currently used (<code>pbkdf2</code> or <code>bcrypt</code>).</li>

    <li><code>CarState</code><br>
        Vehicle charging state, for example <code>Idle</code>, <code>Charging</code>, <code>Complete</code>.</li>

    <li><code>Laden_starten</code><br>
        Force-state reading derived from <code>frc</code>: <code>Neutral</code>, <code>Stop</code>, <code>Start</code>, or an explicit <code>Unknown(value)</code>.</li>

    <li><code>lastCommandStatus</code>, <code>lastCommandRequestId</code>, <code>lastCommandError</code><br>
        Result of the most recent secured command: pending, success, failed, or timeout. Device error payloads remain suppressed in normal logging.</li>

    <li><code>Strom</code><br>
        Configured charging current in ampere.</li>

    <li><code>Modus</code><br>
        Current charging mode (<code>Default</code>, <code>Eco</code>, <code>NextTrip</code>).</li>

    <li><code>Zeit_NextTrip</code><br>
        Planned departure time in <code>hh:mm</code>.</li>

    <li><code>Energie_seit_Anstecken</code><br>
        Energy charged since the vehicle was plugged in.</li>

    <li><code>EnergyTotal</code><br>
        Total energy counter in kWh.</li>

    <li><code>power</code><br>
        Current total power.</li>

    <li><code>Voltage_L1</code>, <code>Voltage_L2</code>, <code>Voltage_L3</code><br>
        Voltage per phase.</li>

    <li><code>Current_L1</code>, <code>Current_L2</code>, <code>Current_L3</code><br>
        Current per phase.</li>

    <li><code>Power_L1</code>, <code>Power_L2</code>, <code>Power_L3</code><br>
        Power per phase.</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="Wattpilot"></a>
<h3>Wattpilot</h3>
<ul>
  <li>Dieses Modul dient zur Steuerung einer Fronius Wattpilot Wallbox über die WebSocket API V2.</li>
  <li>Es unterstützt das Auslesen von Statuswerten, das Setzen von Lademodi, das Starten/Stoppen der Ladung sowie die Authentifizierung per PBKDF2 und bcrypt.</li>
  <li>Dekodierte Eingaben sind auf 1 MiB und höchstens 256 verkettete JSON-Dokumente begrenzt, werden strukturell getrennt und typgeprüft. DevIo puffert rohe WebSocket-Frames; Wattpilot begrenzt die logische JSON-Fortsetzung separat. Ausgelassene <code>deltaStatus</code>-Felder bleiben unverändert.</li>
  <br>

  <a name="Wattpilot-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Wattpilot &lt;IP-Addresse&gt; [&lt;Seriennummer&gt;]</code>
    <br><br>
    Definiert ein Wattpilot-Device.<br>
    <b>&lt;IP-Addresse&gt;</b>: Die lokale IP-Adresse des Wattpiloten (z.B. 192.0.2.10).<br>
    <b>&lt;Seriennummer&gt;</b>: (Optional) Die Seriennummer des Geräts. Wenn sie nicht angegeben wird, wird sie beim Verbindungsaufbau aus der <code>hello</code>-Nachricht übernommen.<br>
    <br>
    Das Passwort ist nicht mehr Teil des <code>define</code>-Befehls und muss separat mit <code>set &lt;name&gt; Password &lt;secret&gt;</code> gesetzt werden.
  </ul>
  <br>

  <a name="Wattpilot-set"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; Password &lt;secret&gt;</code><br>
        Speichert das Passwort und den abgeleiteten Authentifizierungswert ausschließlich unter stabilen FUUID-basierten Schlüsseln und startet einen Reconnect. Rename schreibt keine Zugangsdaten um. Passwortänderung und Gerätelöschung lesen zuerst Snapshots der beiden stabilen Werte und rollen bereits ausgeführte Änderungen nach einem Teilfehler zurück; ein unvollständiger Rollback wird ausdrücklich gemeldet. Credential-Lesezugriffe unterscheiden vorhanden, nicht vorhanden und Speicherfehler. Undefine, Rename, Reload, <code>rereadcfg</code> und Disable erhalten die Zugangsdaten. Veröffentlichte 1.6.x-Versionen sind die letzten Releases mit Unterstützung für namensbasierte Credential-Migration. Version 2.0 erfordert eine frische Definition und ein erneutes Setzen des Passworts; alte namensbasierte Schlüssel werden weder gelesen noch automatisch bereinigt.</li>

    <li><code>set &lt;name&gt; Laden_starten &lt;Start|Stop&gt;</code><br>
        Startet oder stoppt den Ladevorgang manuell (entspricht dem Parameter <code>frc</code>). Start sendet <code>2</code>, Stop sendet <code>1</code>; das Reading behält die kompatiblen Werte <code>Start</code>/<code>Stop</code> und ergänzt <code>Neutral</code> für Wert <code>0</code>.</li>

    <li><code>set &lt;name&gt; Strom &lt;6-32&gt;</code><br>
        Setzt den Ladestrom in Ampere. Werte außerhalb des öffentlichen Bereichs 6–32 werden vor dem Senden abgewiesen.</li>

    <li><code>set &lt;name&gt; Modus &lt;Default|Eco|NextTrip&gt;</code><br>
        Ändert den Lademodus:<br>
        <ul>
          <li><b>Default</b>: Standard-Laden</li>
          <li><b>Eco</b>: Laden mit PV-Überschuss</li>
          <li><b>NextTrip</b>: Geplantes Laden für die nächste Fahrt</li>
        </ul>
    </li>

    <li><code>set &lt;name&gt; Zeit_NextTrip &lt;hh:mm&gt;</code><br>
        Setzt die geplante Abfahrtszeit für den Modus NextTrip. Intern wird der Wert in Sekunden ab Mitternacht umgerechnet.</li>
  </ul>
  <br>

  <a name="Wattpilot-get"></a>
  <b>Get</b>
  <ul>
    <li>Derzeit sind keine eigenen <code>get</code>-Befehle implementiert.</li>
  </ul>
  <br>

  <a name="Wattpilot-attr"></a>
  <b>Attribute</b>
  <ul>
    <li><code>interval &lt;sekunden&gt;</code><br>
        Intervall in Sekunden für die Aktualisierung hochfrequenter Messwerte wie Spannungen und Phasenströme. <code>0</code> bedeutet keine Begrenzung.</li>

    <li><code>update_while_idle &lt;0|1&gt;</code><br>
        <code>0</code> belässt hochfrequente <code>nrg</code>-, Leistungs- und Strom-Readings im nicht ladenden Zustand passiv. <code>1</code> verarbeitet echte eingehende Idle-Werte unter Berücksichtigung von <code>interval</code>. Beim Wechsel von Laden zu einem gültigen nicht ladenden <code>car</code>-Zustand umgeht ein echtes <code>nrg</code> in derselben Nachricht oder innerhalb von 30 Sekunden einmalig das Rate-Limit, damit vom Gerät gelieferte Nullwerte stale Readings korrigieren. Es wird kein Polling-Kommando gesendet: Es ist kein belegter Wattpilot-WebSocket-Request für alle Werte oder einen Full-Status bekannt. Kommt in diesem 30-Sekunden-Fenster kein gültiges <code>nrg</code>, schließt das Modul die Sitzung und plant höchstens einen kontrollierten Reconnect für diese Idle-Episode. Dieser begrenzte Fallback ist aus Drittclient-Verhalten abgeleitet, wonach nach Login ein initialer Status serverseitig gepusht wird; er ist kein offizielles Fronius-Refresh-Feature. Fehlende Felder, Timeouts, Disconnects und fehlgeschlagene Refreshes erzeugen niemals künstliche Nullwerte.</li>

    <li><code>defaultAmp &lt;wert&gt;</code><br>
        Standardwert für den Strom-Slider im Frontend.</li>

    <li><code>disable &lt;0|1&gt;</code><br>
        Deaktiviert das Modul vollständig. Bei <code>1</code> wird die Verbindung getrennt.</li>

    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Standard: <code>0</code>. Exakte ein- und ausgehende JSON-Nachrichten werden nur protokolliert, wenn dieses Attribut <code>1</code> und gleichzeitig <code>verbose</code> auf <code>5</code> gesetzt ist. Dies umfasst Authentifizierungs- und <code>securedMsg</code>-Frames. Ein zentraler Schreibpfad unterdrückt DevIos eigenes Level-5-Payload-Logging, ohne <code>verbose</code> dauerhaft zu ändern. <code>DevIo_SimpleWrite(..., 2)</code> erhält ungepackten Text; DevIo bestimmt den WebSocket-Opcode anhand seiner Verbindung und von <code>$hash-&gt;{binary}</code>. Wattpilot-eigene normale Logs werden redigiert. Technische Grenze: Der interne HttpUtils-Verbindungshash von DevIo übernimmt weder <code>privacy</code> als <code>hideurl</code> noch <code>devioLoglevel</code>; FHEM-Core kann deshalb Endpoint-URLs, DNS/IP-Ergebnisse, Timeouts und Verbindungsfehler auf Level 4 oder 5 protokollieren, die außerhalb der Redaktionsgarantie des Moduls liegen. Beim Aktivieren erscheint eine Warnung, da Logs sensible Authentifizierungs-, Netzwerk-, Geräte- und Betriebsdaten enthalten können. Diese Ausgabe niemals unbereinigt weitergeben.</li>

    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Wählt das Verfahren zur Passwort-Hash-Bildung für die Authentifizierung.<br>
        <ul>
          <li><b>auto</b>: Akzeptiert angekündigtes PBKDF2 oder bcrypt. Ein fehlender Hash wählt nur beim belegten Legacy-Profil <code>devicetype=wattpilot</code>, Protokoll 2, PBKDF2; unbekannte Verfahren werden abgelehnt.</li>
          <li><b>pbkdf2</b>: Erzwingt das ältere PBKDF2-Verfahren</li>
          <li><b>bcrypt</b>: Erzwingt bcrypt (für neuere Wattpilot-Flex-Geräte)</li>
        </ul>
        Das Ändern oder Löschen dieses Attributs verwirft die aktuelle Authentifizierung sofort und trennt die Verbindung. Ist das Gerät aktiviert und das Passwort lesbar, wird genau eine neue Anmeldung geplant, bevor wieder gesicherte Befehle akzeptiert werden; andernfalls bleibt der passende Zustand disabled, credential error oder password missing bestehen.
    </li>
    <li><code>authHashCost &lt;4-14&gt;</code><br>
        bcrypt-Kostenfaktor für neu abgeleitete Authentifizierungs-Hashes. Ändern oder Löschen ist authentifizierungsrelevant, trennt deshalb die aktuelle Sitzung und plant bei aktiviertem und konfiguriertem Gerät genau eine frische Anmeldung.</li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Aktueller Verbindungs-/Authentifizierungsstatus, z.B. <code>disabled</code>, <code>password missing</code>, <code>credential error</code>, <code>connecting</code>, <code>authenticating</code>, <code>initializing</code>, <code>connected</code>, <code>disconnected</code>, <code>connection failed</code>, <code>auth_failed</code>, <code>auth_timeout</code> oder <code>initialization_timeout</code>. <code>connected</code> setzt eine offene DevIo-Verbindung, erfolgreiche Authentifizierung und mindestens eine gültige Statusnachricht nach der Authentifizierung voraus; <code>authSuccess</code> allein reicht nicht.</li>

    <li><code>version</code><br>
        Vom Wattpilot gemeldete Firmware-/Protokollversion.</li>

    <li><code>authHashMode</code><br>
        Tatsächlich verwendetes Authentifizierungsverfahren (<code>pbkdf2</code> oder <code>bcrypt</code>).</li>

    <li><code>CarState</code><br>
        Fahrzeug-/Ladezustand, z.B. <code>Idle</code>, <code>Charging</code> oder <code>Complete</code>.</li>

    <li><code>Laden_starten</code><br>
        Force-State aus <code>frc</code>: <code>Neutral</code>, <code>Stop</code>, <code>Start</code> oder ein explizites <code>Unknown(value)</code>.</li>

    <li><code>lastCommandStatus</code>, <code>lastCommandRequestId</code>, <code>lastCommandError</code><br>
        Ergebnis des letzten gesicherten Befehls: pending, success, failed oder timeout. Geräte-Fehlerpayloads bleiben im normalen Logging unterdrückt.</li>

    <li><code>Strom</code><br>
        Eingestellter Ladestrom in Ampere.</li>

    <li><code>Modus</code><br>
        Aktueller Lademodus (<code>Default</code>, <code>Eco</code>, <code>NextTrip</code>).</li>

    <li><code>Zeit_NextTrip</code><br>
        Geplante Abfahrtszeit im Format <code>hh:mm</code>.</li>

    <li><code>Energie_seit_Anstecken</code><br>
        Geladene Energie in Wh seit dem Anstecken des Fahrzeugs.</li>

    <li><code>EnergyTotal</code><br>
        Gesamtenergiezähler in kWh.</li>

    <li><code>power</code><br>
        Aktuelle Gesamtleistung.</li>

    <li><code>Voltage_L1</code>, <code>Voltage_L2</code>, <code>Voltage_L3</code><br>
        Spannung pro Phase.</li>

    <li><code>Current_L1</code>, <code>Current_L2</code>, <code>Current_L3</code><br>
        Strom pro Phase.</li>

    <li><code>Power_L1</code>, <code>Power_L2</code>, <code>Power_L3</code><br>
        Leistung pro Phase.</li>
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
  "version": "v1.6.0",
  "release_status": "testing",
  "author": [
    "Dennis Gramespacher <>"
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
