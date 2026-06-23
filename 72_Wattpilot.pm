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
    
	my $password_result = Wattpilot_GetStoredSecret($hash, "password", { include_owned_current => 1 });
	my $password_hash_result = Wattpilot_GetStoredSecret($hash, "passwordhash", { include_owned_current => 1 });
	
    $hash->{STATE} = "Initialized";
    
    # WebSocket spezifische Header
    $hash->{header}{'User-Agent'} = 'FHEM';
    
    $modules{Wattpilot}{defptr}{$name} = $hash;
    
    # Starte Verbindungs-Timer (verzögerter Start) falls password verfügbar
	if ($password_result->{status} eq "error") {
		readingsSingleUpdate($hash, "state", "credential error", 1);
	} elsif ($password_result->{status} eq "value" && $password_result->{value} ne "") {
		Log3 $name, 1,
		  "Wattpilot ($name) - optional password hash migration or cleanup deferred"
		  if $password_hash_result->{status} eq "error";
        readingsSingleUpdate($hash, "state", "disconnected", 1);
		Wattpilot_ScheduleConnect($hash, 2);
	} else {
		readingsSingleUpdate($hash, "state", "password missing", 1);
	}
    return undef;
}

sub Wattpilot_Undefine($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{undefined} = 1;
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
    delete $hash->{helper}{openInFlight};
    DevIo_CloseDev($hash);
    RemoveInternalTimer($hash);
    
    delete $modules{Wattpilot}{defptr}{$name};
    return undef;
}

sub Wattpilot_Delete($$) {
    my ($hash, $name) = @_;

    $hash->{helper}{deleting} = 1;
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
    delete $hash->{helper}{openInFlight};
    DevIo_CloseDev($hash);
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
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    DevIo_CloseDev($hash) if DevIo_IsOpen($hash);

    if (Wattpilot_IsDisabled($name)) {
        readingsSingleUpdate($hash, "state", "disabled", 1);
        return;
    }

    my $password_result = Wattpilot_GetStoredSecret(
        $hash, "password", { migrate => 0, include_owned_current => 1 });
    if ($password_result->{status} eq "error") {
        readingsSingleUpdate($hash, "state", "credential error", 1);
    } elsif ($password_result->{status} eq "value" && $password_result->{value} ne "") {
        readingsSingleUpdate($hash, "state", "disconnected", 1);
        Wattpilot_ScheduleConnect($hash, 2);
    } else {
        readingsSingleUpdate($hash, "state", "password missing", 1);
    }
}

sub Wattpilot_Shutdown($) {
    my ($hash) = @_;
    $hash->{helper}{shuttingDown} = 1;
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
    delete $hash->{helper}{openInFlight};
    DevIo_CloseDev($hash);
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    RemoveInternalTimer($hash);
    return undef;
}

sub Wattpilot_Rename($$) {
    my ($new_name, $old_name) = @_;
    my $hash = $defs{$new_name};
    return undef if !defined $hash;

    my $was_active = Wattpilot_IsRuntimeActive($hash);
    Wattpilot_NextLifecycleGeneration($hash);
    Wattpilot_CancelAllTimers($hash);
    Wattpilot_ClearConnectionState($hash);
    if ($hash->{helper}{openInFlight}) {
        $hash->{helper}{pendingReconnectAfterOpen} = 1 if $was_active;
    }
    DevIo_CloseDev($hash);

    delete $modules{Wattpilot}{defptr}{$old_name};
    $modules{Wattpilot}{defptr}{$new_name} = $hash;
    my $migration_error = Wattpilot_MigrateLegacySecrets($hash, $old_name);
    readingsSingleUpdate($hash, "state", "credential error", 1) if defined $migration_error;
    if (!defined($migration_error) && $was_active) {
        readingsSingleUpdate($hash, "state", "disconnected", 1);
        Wattpilot_ScheduleConnect($hash, 1);
    }
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
    readingsSingleUpdate($hash, "state", "connecting", 1);
    my $generation = Wattpilot_CurrentLifecycleGeneration($hash);
    my $open_ctx = {
        generation => $generation,
        name => $hash->{NAME},
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
            DevIo_CloseDev($hash) if !$error && DevIo_IsOpen($hash);
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
            readingsSingleUpdate($hash, "state", "connection failed", 1);
            Wattpilot_ScheduleConnect($hash, 60);
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
    readingsSingleUpdate($hash, "state", "authenticating", 1);
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
        ? 'initialization_timeout'
        : 'auth_timeout';
    Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - $state";
    readingsSingleUpdate($hash, "state", $state, 1);

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

sub Wattpilot_ValidateStatus($$) {
    my ($hash, $status) = @_;
    return 0 if ref($status) ne 'HASH';

    my %integer = map { $_ => 1 } qw(car frc ftt amp lmo);
    my %number = map { $_ => 1 } qw(eto wh);
    for my $key (keys %integer) {
        next if !exists($status->{$key}) || !defined($status->{$key});
        if (!Wattpilot_IsInteger($status->{$key})) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status->{$key};
        }
    }
    for my $key (keys %number) {
        next if !exists($status->{$key}) || !defined($status->{$key});
        if (!Wattpilot_IsNumber($status->{$key})) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=$key";
            delete $status->{$key};
        }
    }
    if (exists($status->{nrg}) && defined($status->{nrg})) {
        my $valid = ref($status->{nrg}) eq 'ARRAY'
            && @{$status->{nrg}} >= 12
            && !grep { !defined($_) || !Wattpilot_IsNumber($_) } @{$status->{nrg}}[0..11];
        if (!$valid) {
            Log3 $hash->{NAME}, 2,
                "Wattpilot ($hash->{NAME}) - Ignoring invalid status field key=nrg";
            delete $status->{nrg};
        }
    }
    return 1;
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
            readingsSingleUpdate($hash, "version", $json->{version}, 1);
        }
        Log3 $name, 4, "Wattpilot ($name) - Hello received";
    } elsif ($type eq 'authRequired') {
        Log3 $name, 4, "Wattpilot ($name) - Auth Required";
        Wattpilot_ClearCommandState($hash);
        Wattpilot_SendAuth($hash, $json);
    } elsif ($type eq 'authSuccess') {
        if (!$hash->{helper}{authPending}) {
            Log3 $name, 1, "Wattpilot ($name) - Authentication success arrived outside an active challenge";
            Wattpilot_AbortAuthentication($hash, "auth_sequence_invalid");
            return 0;
        }
        Log3 $name, 2, "Wattpilot ($name) - Authentication Successful";
        $hash->{helper}{authenticated} = 1;
        delete $hash->{helper}{authPending};
        delete $hash->{helper}{authHashMode};
        Wattpilot_CancelTimer($hash, 'lifecycle_timeout');
        readingsSingleUpdate($hash, "state", "initializing", 1);
        Wattpilot_ScheduleTimer(
            $hash, 'lifecycle_timeout', $WATTPILOT_INITIALIZATION_TIMEOUT,
            'Wattpilot_LifecycleTimeout', { phase => 'initialization' });
    } elsif ($type eq 'authError') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication failed";
        Wattpilot_AbortAuthentication($hash, "auth_failed");
    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {
        if (ref($json->{status}) ne 'HASH') {
            Log3 $name, 2, "Wattpilot ($name) - Ignoring status message with missing or invalid status";
            return 0;
        }
        my %status = %{$json->{status}};
        Wattpilot_ValidateStatus($hash, \%status);
        Wattpilot_UpdateReadings($hash, \%status);
        Wattpilot_MarkInitialized($hash)
            if $hash->{helper}{authenticated}
            && ($hash->{STATE} // '') eq 'initializing';
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
            my %status = %{$json->{status}};
            Wattpilot_ValidateStatus($hash, \%status);
            $json = { %$json, status => \%status };
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
    readingsSingleUpdate($hash, "state", "connected", 1);
}

sub Wattpilot_NrgReadingsNeedIdleRefresh($) {
    my ($hash) = @_;
    for my $reading (qw(power Current_L1 Current_L2 Current_L3 Power_L1 Power_L2 Power_L3)) {
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
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    Wattpilot_ScheduleConnect($hash, 1);
}

sub Wattpilot_UpdateReadings($$) {
    my ($hash, $status) = @_;
    my $name = $hash->{NAME};
    return if ref($status) ne 'HASH';
    my %validated_status = %$status;
    $status = \%validated_status;
    Wattpilot_ValidateStatus($hash, $status);
    my $previous_car_state = $hash->{helper}{car_state};
    my $has_valid_nrg = ref($status->{nrg}) eq 'ARRAY' && @{$status->{nrg}} >= 12;
    
    # Rate-Limiting Logik:
    # Einige Werte (wie 'nrg' - Spannung/Strom) aktualisieren sehr häufig (hochfrequent).
    # Andere (wie 'amp', 'car', 'frc') sind niederfrequent und kritisch für die UI.
    # Das Intervall wird NUR auf die hochfrequenten "Spam"-Werte angewendet.
    
    my $interval = AttrVal($name, "interval", 0);
    my $now = gettimeofday();
    my $last_update = $hash->{LAST_UPDATE} // 0;
    
    # Unterdrücke Spam-Werte, wenn Intervall noch nicht abgelaufen
    my $suppress_spammy = ($interval > 0 && ($now - $last_update < $interval));
    
    readingsBeginUpdate($hash);
    
    # --- KRITISCHE / NIEDERFREQUENTE UPDATES (Immer aktualisieren) ---
    
    # Fahrzeug Status (Car State)
    if (defined $status->{car} && Wattpilot_IsInteger($status->{car})) {
        my %CarStateMap = (0 => 'Unknown', 1 => 'Idle', 2 => 'Charging', 3 => 'WaitCar', 4 => 'Complete', 5 => 'Error');
        my $state = $CarStateMap{int($status->{car})} // "Unknown";
        readingsBulkUpdate($hash, "CarState", $state);
        
        # Speichere internen Status für Logik (Charging vs Not Charging)
        $hash->{helper}{car_state} = int($status->{car});
    }
    
    # Prüfe ob geladen wird (Status 2)
    my $is_charging = ($hash->{helper}{car_state} // 0) == 2;
    my $car_transitioned_to_idle =
        defined($previous_car_state)
        && $previous_car_state == 2
        && defined($hash->{helper}{car_state})
        && $hash->{helper}{car_state} != 2;
    if ($is_charging) {
        $hash->{helper}{idleRefreshAttempted} = 0;
        Wattpilot_StopIdleRefresh($hash);
    } elsif ($car_transitioned_to_idle) {
        Wattpilot_StartIdleRefreshWindow($hash);
    }
    
    # Force state (frc): compatibility labels Start/Stop plus explicit Neutral.
    if (defined $status->{frc} && Wattpilot_IsInteger($status->{frc})) {
        my $frc_val = $status->{frc};
        my %frc_map = (0 => 'Neutral', 1 => 'Stop', 2 => 'Start');
        my $state = (defined($frc_val) && !ref($frc_val) && $frc_val =~ /^-?\d+$/
            && exists $frc_map{int($frc_val)})
          ? $frc_map{int($frc_val)}
          : 'Unknown(' . $frc_val . ')';
        readingsBulkUpdate($hash, "Laden_starten", $state);
    }
    
    # Nächste Fahrt Zeit (ftt)
    if (defined $status->{ftt} && Wattpilot_IsInteger($status->{ftt})) {
        # Sekunden ab Mitternacht in hh:mm umrechnen
        my $secs = $status->{ftt};
        my $h = int($secs / 3600);
        my $m = int(($secs % 3600) / 60);
        readingsBulkUpdate($hash, "Zeit_NextTrip", sprintf("%02d:%02d", $h, $m));
    }
    
    # Stromstärke (amp) - Sollte immer sofort aktualisiert werden
    if (defined $status->{amp} && Wattpilot_IsInteger($status->{amp})) {
        readingsBulkUpdate($hash, "Strom", $status->{amp});
    }
	
	if (defined $status->{lmo} && Wattpilot_IsInteger($status->{lmo})) {
    my %mode_rev = (
        3 => 'Default',
        4 => 'Eco',
        5 => 'NextTrip',
    );

    my $mode_num  = $status->{lmo};
    my $mode_text = $mode_rev{$mode_num} // $mode_num;

    readingsBulkUpdate($hash, "Modus", $mode_text);
	}
    
    # --- RATENLIMITIERTE UPDATES (Hochfrequent) ---
    # Nur wenn NICHT unterdrückt UND (Ladung aktiv ODER update_while_idle gesetzt)
    
    my $update_while_idle = AttrVal($name, "update_while_idle", 0);
    my $idle_bypass = ($hash->{helper}{idleRefreshPending}
        || $hash->{helper}{idleRefreshAwaitingReconnectNrg}) && $has_valid_nrg ? 1 : 0;
    
    my $process_nrg = 0;
    if ($idle_bypass) {
        $process_nrg = 1;
        Wattpilot_StopIdleRefresh($hash);
    } elsif (!$suppress_spammy) {
        if ($is_charging || $update_while_idle) {
             $process_nrg = 1;
        }
    }
    delete $hash->{helper}{idleRefreshAwaitingReconnectNrg}
        if $hash->{helper}{idleRefreshAwaitingReconnectNrg} && !$has_valid_nrg;
    $hash->{LAST_UPDATE} = $now if $process_nrg;
    
    if ($process_nrg) {
        
        # Energie Gesamt (eto)
        if (defined $status->{eto} && Wattpilot_IsNumber($status->{eto})) {
             # Rundung auf 2 Nachkommastellen, Umrechnung Wh -> kWh wenn nötig (Hier Annahme: Rohwert durch 1000)
             readingsBulkUpdate($hash, "EnergyTotal", sprintf("%.2f", $status->{eto} / 1000));
        }

        # Energie seit Anstecken (wh)
        if (defined $status->{wh} && Wattpilot_IsNumber($status->{wh})) {
             readingsBulkUpdate($hash, "Energie_seit_Anstecken", sprintf("%.2f", $status->{wh}));
        }
        
        # Energie Details (nrg Array)
        if (ref($status->{nrg}) eq 'ARRAY') {
            my @nrg = @{$status->{nrg}};
            if (@nrg > 11) {
                readingsBulkUpdate($hash, "Voltage_L1", sprintf("%.2f", $nrg[0]));
                readingsBulkUpdate($hash, "Voltage_L2", sprintf("%.2f", $nrg[1]));
                readingsBulkUpdate($hash, "Voltage_L3", sprintf("%.2f", $nrg[2]));
                readingsBulkUpdate($hash, "Current_L1", sprintf("%.2f", $nrg[4]));
                readingsBulkUpdate($hash, "Current_L2", sprintf("%.2f", $nrg[5]));
                readingsBulkUpdate($hash, "Current_L3", sprintf("%.2f", $nrg[6]));
                readingsBulkUpdate($hash, "Power_L1", sprintf("%.2f", $nrg[7]));
                readingsBulkUpdate($hash, "Power_L2", sprintf("%.2f", $nrg[8]));
                readingsBulkUpdate($hash, "Power_L3", sprintf("%.2f", $nrg[9]));
                readingsBulkUpdate($hash, "power", sprintf("%.2f", $nrg[11])); # Gesamtleistung
            }
        }
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
        Wattpilot_AbortAuthentication($hash, "credential error");
        return;
    }
    my $password = $password_result->{status} eq "value" ? $password_result->{value} : undef;
    if (!$password || !defined($serial) || $serial !~ /^\d+$/) {
        Log3 $name, 1, "Wattpilot ($name) - Missing Password or Serial for authentication";
        Wattpilot_AbortAuthentication($hash, "auth_config_missing");
        return;
    }

    if (!Wattpilot_IsScalarString($json->{token1}) || $json->{token1} eq ''
        || !Wattpilot_IsScalarString($json->{token2}) || $json->{token2} eq '') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication challenge has invalid tokens";
        Wattpilot_AbortAuthentication($hash, "auth_challenge_invalid");
        return;
    }

    my $mode = eval { Wattpilot_GetAuthHashMode($hash, $json) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Authentication hash mode is unsupported";
        Wattpilot_AbortAuthentication($hash, "auth_hash_unsupported");
        return;
    }
    $hash->{helper}{authHashMode} = $mode;

    my $password_hash = eval {
        Wattpilot_DerivePasswordHash($hash, $password, $serial);
    };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Password hash derivation failed for mode=$mode";
        Wattpilot_AbortAuthentication($hash, "auth_hash_failed");
        return;
    }

    if (!Wattpilot_SetStoredPasswordHash($hash, $password_hash)) {
        Wattpilot_AbortAuthentication($hash, "auth_hash_store_failed");
        return;
    }

    my $token1 = $json->{token1};
    my $token2 = $json->{token2};

    my $random_bytes = eval { Wattpilot_SecureRandomBytes(16) };
    if ($@ || !defined($random_bytes) || length($random_bytes) != 16) {
        Log3 $name, 1, "Wattpilot ($name) - Secure authentication nonce generation failed";
        Wattpilot_AbortAuthentication($hash, "auth_nonce_failed");
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
	readingsSingleUpdate($hash, "authHashMode", $mode, 1);
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
    
    if($cmd eq 'Laden_starten') {
        return "Usage: set $name Laden_starten <Start|Stop>" if (!defined $val || $val !~ /^(Start|Stop)$/);
        my $frc_val = ($val eq 'Start') ? 2 : 1;
        return Wattpilot_SendSecure($hash, "frc", int($frc_val));
    } elsif ($cmd eq 'Strom') {
        return "Usage: set $name Strom <6-32>" if (!defined $val || $val !~ /^(?:[6-9]|[12]\d|3[0-2])$/);
        return Wattpilot_SendSecure($hash, "amp", int($val));
    } elsif ($cmd eq 'Modus') {
        return "Usage: set $name Modus <Default|Eco|NextTrip>" if (!defined $val);
        my %mode_map = ( 'Default' => 3, 'Eco' => 4, 'NextTrip' => 5 );
        return "Unknown mode $val" if (!exists $mode_map{$val});
        return Wattpilot_SendSecure($hash, "lmo", $mode_map{$val});
    } elsif ($cmd eq 'Zeit_NextTrip') {
        return "Usage: set $name Zeit_NextTrip <hh:mm>" if (!defined $val || $val !~ /^([0-1]?[0-9]|2[0-3]):([0-5][0-9])$/);
        my ($h, $m) = split(':', $val);
        my $seconds = ($h * 3600) + ($m * 60);
        return Wattpilot_SendSecure($hash, "ftt", int($seconds));
	} elsif ($cmd eq 'Password') {
		return "Usage: set $name Password <secret>" if (!defined($a[2]) || $a[2] eq "");

		my $password_err = Wattpilot_StoreNewPassword($hash, $a[2]);
		return $password_err if defined $password_err;
		
	
		readingsSingleUpdate($hash, "state", "password stored", 1);
        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_NextLifecycleGeneration($hash);
        Wattpilot_CancelAllTimers($hash);
		Wattpilot_ClearConnectionState($hash);
        delete $hash->{helper}{openInFlight};
		DevIo_CloseDev($hash);
        readingsSingleUpdate($hash, "state", "disconnected", 1);
		Wattpilot_ScheduleConnect($hash, 1);
		
		return undef;
	} 
	else {
        return "Unknown argument $cmd, choose one of Password Laden_starten:Start,Stop Strom:slider,6,1,32 Modus:Default,Eco,NextTrip Zeit_NextTrip";
    }
    
    return undef;
}

sub Wattpilot_SendSecure($$$) {
    my ($hash, $key, $val) = @_;
    my $name = $hash->{NAME};

    return "Device is disabled" if Wattpilot_IsDisabled($name);
    return "Wattpilot is disconnected" if !DevIo_IsOpen($hash);
    return "Wattpilot is not authenticated" if !$hash->{helper}{authenticated}
        || (($hash->{STATE} // '') ne 'connected'
            && (($hash->{READINGS}{state}{VAL} // '') ne 'connected'));

    my $stored_hash_result = Wattpilot_GetPasswordHash($hash);
    if ($stored_hash_result->{status} eq "error") {
        Log3 $name, 1, "Wattpilot ($name) - Cannot send command because credential storage is unavailable";
        readingsSingleUpdate($hash, "state", "credential error", 1);
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
    readingsBulkUpdate($hash, 'lastCommandRequestId', $request_id);
    readingsBulkUpdate($hash, 'lastCommandStatus', $status);
    readingsBulkUpdate($hash, 'lastCommandError', $error);
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
    readingsSingleUpdate($hash, "state", $state, 1);
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
        Wattpilot_UpdateReadings($hash, $json->{status}) if ref($json->{status}) eq 'HASH';
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
    return 0 if ($hash->{STATE} // '') ne "disconnected"
        && ($hash->{STATE} // '') ne "connection failed";
    Wattpilot_ClearConnectionState($hash);
    return 0 if defined($hash->{helper}{timers}{connect});
    return Wattpilot_StartOpen($hash, 1) ? 1 : 0;
}

sub Wattpilot_Attr(@) {
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};
    
    # $cmd kann "set" oder "del" sein
    # $name ist der Gerätename, $attrName das Attribut, $attrVal der Wert
    
    if($attrName eq "disable") {
        if($cmd eq "set" && $attrVal eq "1") {
             Wattpilot_NextLifecycleGeneration($hash);
             Wattpilot_CancelAllTimers($hash);
             RemoveInternalTimer($hash, 'Wattpilot_Connect');
             RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
             Wattpilot_ClearConnectionState($hash);
             delete $hash->{helper}{openInFlight};
             DevIo_CloseDev($hash);
             readingsSingleUpdate($hash, "state", "disabled", 1);
		} elsif($cmd eq "del" || $attrVal eq "0") {
             delete $hash->{helper}{timeoutRetryUsed};
             Wattpilot_NextLifecycleGeneration($hash);
             Wattpilot_CancelAllTimers($hash);
             Wattpilot_ClearConnectionState($hash);
             delete $hash->{helper}{openInFlight};
			 my $password_result = Wattpilot_GetPassword($hash);
			 if ($password_result->{status} eq "error") {
				 readingsSingleUpdate($hash, "state", "credential error", 1);
			 } elsif ($password_result->{status} eq "value" && $password_result->{value} ne "") {
				 readingsSingleUpdate($hash, "state", "disconnected", 1);
				 Wattpilot_ScheduleConnect($hash, 1, 0);
			 } else {
				 readingsSingleUpdate($hash, "state", "password missing", 1);
			 }
		}
    }

    if (($attrName eq "authHash" || $attrName eq "authHashCost") && ($cmd eq "set" || $cmd eq "del")) {
        delete $hash->{helper}{timeoutRetryUsed};
        Wattpilot_NextLifecycleGeneration($hash);
        Wattpilot_CancelAllTimers($hash);
        RemoveInternalTimer($hash, 'Wattpilot_Connect');
        RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
        Wattpilot_ClearConnectionState($hash);
        my $had_open_in_flight = $hash->{helper}{openInFlight};
        $hash->{helper}{pendingReconnectAfterOpen} = 1 if $had_open_in_flight;
        DevIo_CloseDev($hash);
        my $hash_error = Wattpilot_InvalidateStoredPasswordHash($hash);

        if (defined $hash_error) {
            readingsSingleUpdate($hash, "state", "credential error", 1);
            delete $hash->{helper}{pendingReconnectAfterOpen};
        } elsif (Wattpilot_IsDisabled($name)) {
            readingsSingleUpdate($hash, "state", "disabled", 1);
            delete $hash->{helper}{pendingReconnectAfterOpen};
        } else {
            my $password_result = Wattpilot_GetPassword($hash);
            if ($password_result->{status} eq "error") {
                readingsSingleUpdate($hash, "state", "credential error", 1);
                delete $hash->{helper}{pendingReconnectAfterOpen};
            } elsif ($password_result->{status} eq "value" && $password_result->{value} ne "") {
                readingsSingleUpdate($hash, "state", "disconnected", 1);
                Wattpilot_ScheduleConnect($hash, 1);
            } else {
                readingsSingleUpdate($hash, "state", "password missing", 1);
                delete $hash->{helper}{pendingReconnectAfterOpen};
            }
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
    return Wattpilot_GetStoredSecret($hash, "password", { include_owned_current => 1 });
}

sub Wattpilot_GetPasswordHash {
    my ($hash) = @_;
    return Wattpilot_GetStoredSecret($hash, "passwordhash", { include_owned_current => 1 });
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

    my @metadata_keys;
    my @legacy_keys;
    for my $suffix (qw(password passwordhash)) {
        my ($pending_error, $pending_names) = Wattpilot_ReadPendingLegacyNames($hash, $suffix);
        return "Wattpilot credential deletion failed before changes were made" if defined $pending_error;
        my %legacy_names = ($name => 1, map { $_ => 1 } @$pending_names);
        my ($ownership_error, $owned_keys) = Wattpilot_GetOwnedLegacyResourceKeys(
            $hash, $suffix, [sort keys %legacy_names]);
        return "Wattpilot credential deletion failed before changes were made" if defined $ownership_error;
        push @legacy_keys, @$owned_keys;
        push @metadata_keys, Wattpilot_PendingLegacyKey($hash, $suffix);
    }
    my (%snapshot, %seen);
    my @keys = (map { Wattpilot_SecretKey($hash, $_) } qw(password passwordhash));
    push @keys, @legacy_keys, @metadata_keys;
    @keys = grep { !$seen{$_}++ } @keys;

    for my $key (@keys) {
        my ($err, $value) = getKeyValue($key);
        if (defined $err) {
            Log3 $name, 1, "Wattpilot ($name) - failed to snapshot credentials before deletion";
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
            Log3 $name, 1, "Wattpilot ($name) - credential deletion failed; rollback " .
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
    my %legacy_password_names = ($name => 1);
    my %legacy_hash_names = ($name => 1);
    my ($password_pending_error, $password_pending) = Wattpilot_ReadPendingLegacyNames($hash, "password");
    my ($hash_pending_error, $hash_pending) = Wattpilot_ReadPendingLegacyNames($hash, "passwordhash");
    if (defined($password_pending_error) || defined($hash_pending_error)) {
        Log3 $name, 1, "Wattpilot ($name) - could not inspect pending credential metadata before password update";
        return "failed to inspect existing credentials; password unchanged";
    }
    $legacy_password_names{$_} = 1 for @$password_pending;
    $legacy_hash_names{$_} = 1 for @$hash_pending;

    my $stable_password = eval { Wattpilot_SecretKey($hash, "password") };
    return "failed to determine stable credential key" if $@;
    my $stable_hash = Wattpilot_SecretKey($hash, "passwordhash");
    my ($password_owner_error, $legacy_password_resources) = Wattpilot_GetOwnedLegacyResourceKeys(
        $hash, "password", [sort keys %legacy_password_names]);
    my ($hash_owner_error, $legacy_hash_resources) = Wattpilot_GetOwnedLegacyResourceKeys(
        $hash, "passwordhash", [sort keys %legacy_hash_names]);
    if (defined($password_owner_error) || defined($hash_owner_error)) {
        return "failed to verify legacy credential ownership; password unchanged";
    }
    my @legacy_passwords = grep { $_ !~ /_owner$/ } @$legacy_password_resources;
    my @legacy_password_owners = grep { $_ =~ /_owner$/ } @$legacy_password_resources;
    my @legacy_hashes = grep { $_ !~ /_owner$/ } @$legacy_hash_resources;
    my @legacy_hash_owners = grep { $_ =~ /_owner$/ } @$legacy_hash_resources;
    my @pending_keys = map { Wattpilot_PendingLegacyKey($hash, $_) } qw(password passwordhash);
    my @all_keys = ($stable_password, $stable_hash, @legacy_passwords, @legacy_password_owners,
                    @legacy_hashes, @legacy_hash_owners, @pending_keys);
    my (%old_value, %seen);

    for my $key (grep { !$seen{$_}++ } @all_keys) {
        my ($err, $value) = getKeyValue($key);
        if (defined $err) {
            Log3 $name, 1, "Wattpilot ($name) - could not inspect credential storage before password update";
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

    for my $key ($stable_hash, @legacy_hashes, @legacy_hash_owners) {
        next if !defined $old_value{$key};
        my $err = setKeyValue($key, undef);
        if (defined $err) {
            my $rollback_error = $rollback->();
            Log3 $name, 1, "Wattpilot ($name) - failed to invalidate password hashes; password unchanged";
            return "failed to invalidate stored password hashes; password unchanged$rollback_error";
        }
        push @changed, $key;
    }

    my $store_err = setKeyValue($stable_password, $new_password);
    if (defined $store_err) {
        my $rollback_error = $rollback->();
        Log3 $name, 1, "Wattpilot ($name) - failed to store new password";
        return "failed to store new password; previous credentials restored$rollback_error";
    }
    push @changed, $stable_password;

    for my $key (@legacy_passwords, @legacy_password_owners) {
        next if !defined $old_value{$key};
        my $err = setKeyValue($key, undef);
        if (defined $err) {
            my $rollback_error = $rollback->();
            Log3 $name, 1, "Wattpilot ($name) - failed to remove legacy password; password update rolled back";
            return "failed to remove legacy password; previous credentials restored$rollback_error";
        }
        push @changed, $key;
    }

    for my $key (@pending_keys) {
        next if !defined $old_value{$key};
        my $err = setKeyValue($key, undef);
        if (defined $err) {
            my $rollback_error = $rollback->();
            Log3 $name, 1, "Wattpilot ($name) - failed to clear pending credential metadata; password update rolled back";
            return "failed to clear pending credential metadata; previous credentials restored$rollback_error";
        }
        push @changed, $key;
    }
    return undef;
}

sub Wattpilot_SecretKey($$) {
    my ($hash, $suffix) = @_;
    my $fuuid = $hash->{FUUID};
    die "Wattpilot credential storage requires FUUID" if !defined($fuuid) || $fuuid eq "";
    return "Wattpilot_" . $fuuid . "_" . $suffix;
}

sub Wattpilot_LegacySecretKey($$) {
    my ($name, $suffix) = @_;
    return "Wattpilot_" . $name . "_" . $suffix;
}

sub Wattpilot_LegacyOwnerKey($$) {
    my ($name, $suffix) = @_;
    return Wattpilot_LegacySecretKey($name, $suffix) . "_owner";
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

sub Wattpilot_ReadOwnedLegacySecret($$$$) {
    my ($hash, $legacy_name, $suffix, $allow_claim) = @_;
    my $name = $hash->{NAME};
    my $fuuid = $hash->{FUUID};
    my $owner_key = Wattpilot_LegacyOwnerKey($legacy_name, $suffix);
    my ($owner_error, $owner) = getKeyValue($owner_key);
    if (defined $owner_error) {
        Log3 $name, 1, "Wattpilot ($name) - could not verify legacy credential ownership";
        return Wattpilot_CredentialError("legacy ownership read failed");
    }
    if (defined $owner && $owner ne $fuuid) {
        Log3 $name, 1, "Wattpilot ($name) - legacy credential belongs to a different device; resource preserved";
        return Wattpilot_CredentialError("legacy ownership conflict");
    }
    if (!defined $owner && !$allow_claim) {
        Log3 $name, 1, "Wattpilot ($name) - legacy credential ownership is unverifiable; resource preserved";
        return Wattpilot_CredentialError("legacy ownership unverifiable");
    }

    if (!defined $owner) {
        my ($pending_error, $pending_names) =
          Wattpilot_ReadPendingLegacyNames($hash, $suffix);
        return Wattpilot_CredentialError($pending_error)
          if defined $pending_error;
        my %pending = map { $_ => 1 } @$pending_names;
        if (!$pending{$legacy_name}) {
            Log3 $name, 1,
              "Wattpilot ($name) - legacy ownership claim is not authorized by persistent pending metadata";
            return Wattpilot_CredentialError("legacy ownership claim not authorized");
        }
        my $claim_error = setKeyValue($owner_key, $fuuid);
        if (defined $claim_error) {
            Log3 $name, 1, "Wattpilot ($name) - could not persist legacy credential ownership";
            return Wattpilot_CredentialError("legacy ownership write failed");
        }
        $owner = $fuuid;
    }

    my $legacy_key = Wattpilot_LegacySecretKey($legacy_name, $suffix);
    my ($read_error, $value) = getKeyValue($legacy_key);
    if (defined $read_error) {
        Log3 $name, 1, "Wattpilot ($name) - could not read owned legacy credential";
        return Wattpilot_CredentialError("legacy credential read failed");
    }
    if (!defined $value) {
        my $owner_cleanup_error = setKeyValue($owner_key, undef);
        if (defined $owner_cleanup_error) {
            Log3 $name, 1, "Wattpilot ($name) - could not remove stale legacy ownership metadata";
            return Wattpilot_CredentialError("legacy ownership cleanup failed");
        }
        return Wattpilot_CredentialAbsent();
    }
    return Wattpilot_CredentialValue($value);
}

sub Wattpilot_GetOwnedLegacyResourceKeys($$$) {
    my ($hash, $suffix, $legacy_names) = @_;
    my @keys;
    my %seen;
    my ($pending_error, $pending_names) =
      Wattpilot_ReadPendingLegacyNames($hash, $suffix);
    return ($pending_error, []) if defined $pending_error;
    my %pending = map { $_ => 1 } @$pending_names;

    for my $legacy_name (@$legacy_names) {
        next if $seen{$legacy_name}++;
        my $owner_key = Wattpilot_LegacyOwnerKey($legacy_name, $suffix);
        my ($owner_error, $owner) = getKeyValue($owner_key);
        if (defined $owner_error) {
            Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - could not verify legacy credential ownership";
            return ("legacy ownership read failed", []);
        }
        if (!defined($owner) && $pending{$legacy_name}) {
            # The persistent FUUID pending locator is sufficient proof for
            # transactional enumeration. Do not create an owner marker before
            # the caller has completed its snapshot.
            $owner = $hash->{FUUID};
        }
        if (!defined($owner) || $owner ne $hash->{FUUID}) {
            Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - unowned or foreign legacy credential preserved";
            next;
        }
        push @keys, Wattpilot_LegacySecretKey($legacy_name, $suffix), $owner_key;
    }
    return (undef, \@keys);
}

sub Wattpilot_PendingLegacyKey($$) {
    my ($hash, $suffix) = @_;
    return Wattpilot_SecretKey($hash, "pending_legacy_${suffix}_names");
}

sub Wattpilot_ReadPendingLegacyNames($$) {
    my ($hash, $suffix) = @_;
    my $name = $hash->{NAME};
    my $key = eval { Wattpilot_PendingLegacyKey($hash, $suffix) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - pending credential metadata key is unavailable";
        return ("metadata key unavailable", []);
    }
    my ($error, $encoded) = getKeyValue($key);
    if (defined $error) {
        Log3 $name, 1, "Wattpilot ($name) - could not read pending credential metadata";
        return ("metadata read failed", []);
    }
    return (undef, []) if !defined($encoded) || $encoded eq "";
    my $names = eval { decode_json($encoded) };
    if ($@ || ref($names) ne "ARRAY" || grep { !defined($_) || ref($_) || $_ eq "" } @$names) {
        Log3 $name, 1, "Wattpilot ($name) - pending credential metadata is invalid";
        return ("metadata invalid", []);
    }
    my %seen;
    return (undef, [grep { !$seen{$_}++ } @$names]);
}

sub Wattpilot_WritePendingLegacyNames($$$) {
    my ($hash, $suffix, $names) = @_;
    my %seen;
    my @names = sort grep { defined($_) && $_ ne "" && !$seen{$_}++ } @$names;
    my $key = eval { Wattpilot_PendingLegacyKey($hash, $suffix) };
    return "metadata key unavailable" if $@;
    my $value = @names ? encode_json(\@names) : undef;
    my $error = setKeyValue($key, $value);
    if (defined $error) {
        Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - could not update pending credential metadata";
        return "metadata write failed";
    }
    return undef;
}

sub Wattpilot_AddPendingLegacyName($$$) {
    my ($hash, $suffix, $legacy_name) = @_;
    my ($error, $names) = Wattpilot_ReadPendingLegacyNames($hash, $suffix);
    return $error if defined $error;
    push @$names, $legacy_name;
    return Wattpilot_WritePendingLegacyNames($hash, $suffix, $names);
}

sub Wattpilot_RemovePendingLegacyName($$$) {
    my ($hash, $suffix, $legacy_name) = @_;
    my ($error, $names) = Wattpilot_ReadPendingLegacyNames($hash, $suffix);
    return $error if defined $error;
    return Wattpilot_WritePendingLegacyNames($hash, $suffix, [grep { $_ ne $legacy_name } @$names]);
}

sub Wattpilot_GetStoredSecret {
    my ($hash, $suffix, $options) = @_;
    $options //= {};
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
    my ($pending_error, $pending_names) = Wattpilot_ReadPendingLegacyNames($hash, $suffix);
    return Wattpilot_CredentialError($pending_error) if defined $pending_error;

    if (defined $value) {
        if (!exists($options->{migrate}) || $options->{migrate}) {
            Wattpilot_CleanupPendingLegacySecrets($hash, $suffix, $pending_names);
        }
        return Wattpilot_CredentialValue($value);
    }

    for my $legacy_name (sort @$pending_names) {
        my $legacy_result = Wattpilot_ReadOwnedLegacySecret($hash, $legacy_name, $suffix, 1);
        return $legacy_result if $legacy_result->{status} eq "error";
        if ($legacy_result->{status} eq "absent") {
            Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix);
            next;
        }
        return $legacy_result if exists($options->{migrate}) && !$options->{migrate};
        return Wattpilot_MigrateLegacySecret($hash, $legacy_name, $suffix, $legacy_result->{value}, 1);
    }

    if ($options->{include_owned_current}) {
        my $legacy_result =
          Wattpilot_ReadCurrentOwnedLegacySecret($hash, $name, $suffix);
        return $legacy_result if $legacy_result->{status} eq "error";
        if ($legacy_result->{status} eq "value") {
            return $legacy_result
              if exists($options->{migrate}) && !$options->{migrate};
            my $pending_error =
              Wattpilot_AddPendingLegacyName($hash, $suffix, $name);
            if (defined $pending_error) {
                Log3 $name, 1,
                  "Wattpilot ($name) - could not persist current-name legacy recovery metadata";
                return Wattpilot_CredentialError($pending_error);
            }
            return Wattpilot_MigrateLegacySecret(
                $hash, $name, $suffix, $legacy_result->{value}, 1);
        }
    }
    return Wattpilot_CredentialAbsent();
}

sub Wattpilot_ReadCurrentOwnedLegacySecret($$$) {
    my ($hash, $legacy_name, $suffix) = @_;
    my $name = $hash->{NAME};
    my $owner_key = Wattpilot_LegacyOwnerKey($legacy_name, $suffix);
    my ($owner_error, $owner) = getKeyValue($owner_key);
    if (defined $owner_error) {
        Log3 $name, 1,
          "Wattpilot ($name) - could not inspect current-name legacy ownership";
        return Wattpilot_CredentialError("legacy ownership read failed");
    }
    return Wattpilot_CredentialAbsent() if !defined $owner;
    if ($owner ne $hash->{FUUID}) {
        Log3 $name, 1,
          "Wattpilot ($name) - current-name legacy credential belongs to a different device";
        return Wattpilot_CredentialError("legacy ownership conflict");
    }
    return Wattpilot_ReadOwnedLegacySecret(
        $hash, $legacy_name, $suffix, 0);
}

sub Wattpilot_CleanupLegacyLocator {
    my ($hash, $legacy_name, $suffix, $skip_pending) = @_;
    my $owner_key = Wattpilot_LegacyOwnerKey($legacy_name, $suffix);
    my $owner_error = setKeyValue($owner_key, undef);
    return "legacy cleanup failed" if defined $owner_error;
    return undef if $skip_pending;
    my $pending_error = Wattpilot_RemovePendingLegacyName($hash, $suffix, $legacy_name);
    if (defined $pending_error) {
        my $restore_error = setKeyValue($owner_key, $hash->{FUUID});
        Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - legacy cleanup metadata rollback failed"
          if defined $restore_error;
        return "legacy cleanup failed";
    }
    return undef;
}

sub Wattpilot_MigrateLegacySecret {
    my ($hash, $legacy_name, $suffix, $legacy_value, $pending_was_stored) = @_;
    my $name = $hash->{NAME};
    my $legacy_key = Wattpilot_LegacySecretKey($legacy_name, $suffix);
    my $key = eval { Wattpilot_SecretKey($hash, $suffix) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - stable credential key is unavailable; legacy $suffix retained";
        return Wattpilot_CredentialError("stable credential key unavailable");
    }
    my $write_err = setKeyValue($key, $legacy_value);
    if (defined $write_err) {
        Wattpilot_AddPendingLegacyName($hash, $suffix, $legacy_name) if !$pending_was_stored;
        Log3 $name, 1, "Wattpilot ($name) - credential migration failed to store $suffix; legacy value retained";
        return Wattpilot_CredentialError("stable credential write failed");
    }

    my $delete_err = setKeyValue($legacy_key, undef);
    if (defined $delete_err) {
        Wattpilot_AddPendingLegacyName($hash, $suffix, $legacy_name);
        Log3 $name, 1, "Wattpilot ($name) - credential migration stored $suffix but could not remove legacy key";
    } else {
        Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix, !$pending_was_stored);
    }
    Log3 $name, 3, "Wattpilot ($name) - migrated legacy $suffix to stable credential storage";
    return Wattpilot_CredentialValue($legacy_value);
}

sub Wattpilot_CleanupPendingLegacySecrets($$$) {
    my ($hash, $suffix, $pending_names) = @_;
    for my $legacy_name (sort @$pending_names) {
        my $legacy_result = Wattpilot_ReadOwnedLegacySecret($hash, $legacy_name, $suffix, 1);
        next if $legacy_result->{status} eq "error";
        if ($legacy_result->{status} eq "absent") {
            Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix);
            next;
        }
        my $delete_error = setKeyValue(Wattpilot_LegacySecretKey($legacy_name, $suffix), undef);
        if (defined $delete_error) {
            Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - stable credential exists but owned legacy cleanup is pending";
            next;
        }
        Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix);
    }
}

sub Wattpilot_MigrateLegacySecrets($$) {
    my ($hash, $legacy_name) = @_;
    my @errors;
    for my $suffix (qw(password passwordhash)) {
        my $pending_error = Wattpilot_AddPendingLegacyName($hash, $suffix, $legacy_name);
        if (defined $pending_error) {
            push @errors, $suffix;
            next;
        }
        my $legacy_result = Wattpilot_ReadOwnedLegacySecret($hash, $legacy_name, $suffix, 1);
        if ($legacy_result->{status} eq "error") {
            push @errors, $suffix;
            next;
        }
        if ($legacy_result->{status} eq "absent") {
            my $cleanup_error =
              Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix);
            push @errors, $suffix if defined $cleanup_error;
            next;
        }

        my $stable_key = eval { Wattpilot_SecretKey($hash, $suffix) };
        if ($@) {
            push @errors, $suffix;
            next;
        }
        my ($stable_error, $stable_value) = getKeyValue($stable_key);
        if (defined $stable_error) {
            Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - could not inspect stable credential during rename";
            push @errors, $suffix;
            next;
        }
        if (!defined $stable_value) {
            my $migration_result = Wattpilot_MigrateLegacySecret(
                $hash, $legacy_name, $suffix, $legacy_result->{value}, 1);
            push @errors, $suffix if $migration_result->{status} eq "error";
        } else {
            my $delete_error = setKeyValue(Wattpilot_LegacySecretKey($legacy_name, $suffix), undef);
            if (defined $delete_error) {
                push @errors, $suffix;
            } else {
                my $cleanup_error =
                  Wattpilot_CleanupLegacyLocator($hash, $legacy_name, $suffix);
                push @errors, $suffix if defined $cleanup_error;
            }
        }
    }
    return @errors ? "Wattpilot rename credential migration requires retry" : undef;
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
        Stores the password persistently under stable FUUID-based keys and starts a reconnect. Define starts the connection whenever the password is readable; migration or cleanup of the optional password hash is best effort and authentication subsequently stores a fresh FUUID-based hash. Rename recovery does not depend on the callback reply discarded by FHEM. A former name is migrated or cleaned up only after a FUUID-based pending locator has been persisted; only that locator may recreate a missing owner marker for the same FUUID. The current device name alone never authorizes ownership. Unowned pre-FUUID values are preserved and may require <code>set Password</code> again. If pending metadata cannot be stored, rename fails closed without reading, claiming, or moving the legacy value. Foreign or unverifiable resources remain untouched. A readable stable credential remains usable when cleanup of such resources is not possible; cleanup conflicts are logged. Credential reads distinguish present, absent, and failed storage access. Undefine, rename, reload, <code>rereadcfg</code>, and disable preserve credentials. Delete snapshots all owned values and metadata first and restores already deleted values after a partial failure. After an Undef/Delete failure it also restores the retained device runtime without duplicate connections or timers; any snapshot, delete, or rollback error prevents FHEM from finalizing the delete.</li>

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
        Speichert das Passwort persistent unter stabilen FUUID-basierten Schlüsseln und startet einen Reconnect. Define startet die Verbindung bei lesbarem Passwort; Migration oder Bereinigung des optionalen Passwort-Hashes erfolgt best effort, anschließend speichert die Authentifizierung einen neuen FUUID-basierten Hash. Rename-Recovery hängt nicht von der durch FHEM verworfenen Callback-Rückgabe ab. Ein früherer Name wird erst migriert oder bereinigt, nachdem ein FUUID-basierter Pending-Verweis persistent gespeichert wurde; nur dieser Verweis darf einen fehlenden Owner-Marker für dieselbe FUUID wiederherstellen. Der aktuelle Gerätename allein begründet niemals Eigentum. Namensbasierte Altwerte ohne Eigentumsnachweis bleiben erhalten und können ein erneutes <code>set Password</code> erfordern. Kann der Pending-Verweis nicht gespeichert werden, liest, beansprucht oder verschiebt Rename den Legacy-Wert nicht. Fremde oder nicht verifizierbare Ressourcen bleiben unangetastet. Ein lesbarer stabiler Zugangswert bleibt trotz nicht möglicher Legacy-Bereinigung nutzbar; der Konflikt wird protokolliert. Credential-Lesezugriffe unterscheiden vorhanden, nicht vorhanden und Speicherfehler. Undefine, Rename, Reload, <code>rereadcfg</code> und Disable erhalten die Zugangsdaten. Delete liest zuerst Snapshots aller eigenen Werte und Metadaten und stellt bei einem Teilfehler bereits gelöschte Werte wieder her. Nach einem Undef/Delete-Fehler stellt es außerdem den Runtime-Zustand des behaltenen Geräts ohne doppelte Verbindung oder Timer wieder her; jeder Snapshot-, Lösch- oder Rollbackfehler verhindert das endgültige Löschen durch FHEM.</li>

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
