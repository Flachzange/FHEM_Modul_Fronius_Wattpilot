#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


module_path = Path('72_Wattpilot.pm')
module = module_path.read_text(encoding='utf-8')

module = replace_once(
    module,
    "my $WATTPILOT_VERSION = '1.3.0';",
    "my $WATTPILOT_VERSION = '1.4.0';\nmy $WATTPILOT_REQUEST_TIMEOUT = 30;\nmy $WATTPILOT_MAX_PENDING_REQUESTS = 32;",
    'module version/constants',
)

module = replace_once(
    module,
    "    RemoveInternalTimer($hash);\n    DevIo_CloseDev($hash);\n    \n    delete $modules{Wattpilot}{defptr}{$name};",
    "    Wattpilot_ClearCommandState($hash);\n    RemoveInternalTimer($hash);\n    DevIo_CloseDev($hash);\n    \n    delete $modules{Wattpilot}{defptr}{$name};",
    'undefine command cleanup',
)

module = replace_once(
    module,
    "    RemoveInternalTimer($hash);\n    DevIo_CloseDev($hash);\n    my $error = Wattpilot_DeleteStoredSecrets($hash);",
    "    Wattpilot_ClearCommandState($hash);\n    RemoveInternalTimer($hash);\n    DevIo_CloseDev($hash);\n    my $error = Wattpilot_DeleteStoredSecrets($hash);",
    'delete command cleanup',
)

module = replace_once(
    module,
    "sub Wattpilot_Connect($) {\n    my ($hash) = @_;\n    \n    return if(DevIo_IsOpen($hash));",
    "sub Wattpilot_Connect($) {\n    my ($hash) = @_;\n    \n    return if(DevIo_IsOpen($hash));\n    Wattpilot_ClearCommandState($hash);",
    'connect clears command state',
)

module = replace_once(
    module,
    "    my $type = $json->{type} // \"\";\n    my %known_type = map { $_ => 1 } qw(hello authRequired authSuccess authError fullStatus deltaStatus);",
    "    my $type = $json->{type} // \"\";\n    my %known_type = map { $_ => 1 } qw(hello authRequired authSuccess authError fullStatus deltaStatus response);",
    'known response type',
)

module = replace_once(
    module,
    "    } elsif ($type eq 'authRequired') {\n        Log3 $name, 4, \"Wattpilot ($name) - Auth Required\";\n        Wattpilot_SendAuth($hash, $json);\n    } elsif ($type eq 'authSuccess') {\n        Log3 $name, 2, \"Wattpilot ($name) - Authentication Successful\";\n        readingsSingleUpdate($hash, \"state\", \"connected\", 1);\n    } elsif ($type eq 'authError') {\n        Log3 $name, 1, \"Wattpilot ($name) - Authentication failed\";\n        readingsSingleUpdate($hash, \"state\", \"auth_failed\", 1);\n        DevIo_CloseDev($hash);\n    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {\n        Wattpilot_UpdateReadings($hash, $json->{status});\n    }",
    "    } elsif ($type eq 'authRequired') {\n        Log3 $name, 4, \"Wattpilot ($name) - Auth Required\";\n        Wattpilot_ClearCommandState($hash);\n        Wattpilot_SendAuth($hash, $json);\n    } elsif ($type eq 'authSuccess') {\n        Log3 $name, 2, \"Wattpilot ($name) - Authentication Successful\";\n        $hash->{helper}{authenticated} = 1;\n        readingsSingleUpdate($hash, \"state\", \"connected\", 1);\n    } elsif ($type eq 'authError') {\n        Log3 $name, 1, \"Wattpilot ($name) - Authentication failed\";\n        Wattpilot_ClearCommandState($hash);\n        readingsSingleUpdate($hash, \"state\", \"auth_failed\", 1);\n        DevIo_CloseDev($hash);\n    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {\n        Wattpilot_UpdateReadings($hash, $json->{status});\n    } elsif ($type eq 'response') {\n        Wattpilot_HandleResponse($hash, $json);\n    }",
    'parse auth/response flow',
)

module = replace_once(
    module,
    "sub Wattpilot_UpdateReadings($$) {\n    my ($hash, $status) = @_;\n    my $name = $hash->{NAME};",
    "sub Wattpilot_UpdateReadings($$) {\n    my ($hash, $status) = @_;\n    my $name = $hash->{NAME};\n    return if ref($status) ne 'HASH';",
    'status validation',
)

module = replace_once(
    module,
    "    # Laden Starten/Stoppen (frc Status)\n    if (defined $status->{frc}) {\n        my $frc_val = $status->{frc};\n        my $state = \"Unknown\";\n        if ($frc_val == 0) { $state = \"Start\"; }\n        elsif ($frc_val == 1) { $state = \"Stop\"; }\n        else { $state = $frc_val; }\n        readingsBulkUpdate($hash, \"Laden_starten\", $state);\n    }",
    "    # Force state (frc): compatibility labels Start/Stop plus explicit Neutral.\n    if (defined $status->{frc}) {\n        my $frc_val = $status->{frc};\n        my %frc_map = (0 => 'Neutral', 1 => 'Stop', 2 => 'Start');\n        my $state = (defined($frc_val) && !ref($frc_val) && $frc_val =~ /^-?\\d+$/\n            && exists $frc_map{int($frc_val)})\n          ? $frc_map{int($frc_val)}\n          : 'Unknown(' . $frc_val . ')';\n        readingsBulkUpdate($hash, \"Laden_starten\", $state);\n    }",
    'frc reading mapping',
)

old_set_start = """sub Wattpilot_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $cmd = $a[1];
    my $val = $a[2];

    return "Device is disabled" if(Wattpilot_IsDisabled($name));
    
    if($cmd eq 'Laden_starten') {
        # Befehl 'frc': Force State. 0=Start, 1=Stop.
        return "Usage: set $name Laden_starten <Start|Stop>" if (!defined $val || $val !~ /^(Start|Stop)$/);
        my $frc_val = ($val eq 'Start') ? 0 : 1;
        Wattpilot_SendSecure($hash, "frc", int($frc_val));
    } elsif ($cmd eq 'Strom') {
        # früher amp
        return "Usage: set $name Strom <6-32>" if (!defined $val || $val !~ /^\d+$/);
        Wattpilot_SendSecure($hash, "amp", int($val));
    } elsif ($cmd eq 'Modus') {
        # früher mode
        return "Usage: set $name Modus <Default|Eco|NextTrip>" if (!defined $val);
        my %mode_map = ( 'Default' => 3, 'Eco' => 4, 'NextTrip' => 5 );
        return "Unknown mode $val" if (!exists $mode_map{$val});
        Wattpilot_SendSecure($hash, "lmo", $mode_map{$val});
    } elsif ($cmd eq 'Zeit_NextTrip') {
        # 'ftt' Befehl für NextTrip Zeit, Format hh:mm
        # API erwartet Sekunden ab Mitternacht
        return "Usage: set $name Zeit_NextTrip <hh:mm>" if (!defined $val || $val !~ /^([0-1]?[0-9]|2[0-3]):([0-5][0-9])$/);
        my ($h, $m) = split(':', $val);
        my $seconds = ($h * 3600) + ($m * 60);
        Wattpilot_SendSecure($hash, "ftt", int($seconds));
"""
new_set_start = """sub Wattpilot_Set($@) {
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
        return "Usage: set $name Strom <6-32>" if (!defined $val || $val !~ /^(?:[6-9]|[12]\\d|3[0-2])$/);
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
"""
module = replace_once(module, old_set_start, new_set_start, 'set validation/semantics')

module = replace_once(
    module,
    "\t\treadingsSingleUpdate($hash, \"state\", \"password stored\", 1);\n\t\t\n\t\tRemoveInternalTimer($hash);",
    "\t\treadingsSingleUpdate($hash, \"state\", \"password stored\", 1);\n\t\tWattpilot_ClearCommandState($hash);\n\t\t\n\t\tRemoveInternalTimer($hash);",
    'password clears command state',
)

old_send = """sub Wattpilot_SendSecure($$$) {
    my ($hash, $key, $val) = @_;
    my $name = $hash->{NAME};
    
    my $stored_hash_result = Wattpilot_GetPasswordHash($hash);
    if ($stored_hash_result->{status} eq "error") {
        Log3 $name, 1, "Wattpilot ($name) - Cannot send command because credential storage is unavailable";
        readingsSingleUpdate($hash, "state", "credential error", 1);
        return;
    }
    my $stored_hash = $stored_hash_result->{status} eq "value" ? $stored_hash_result->{value} : undef;
    if (!$stored_hash) {
        Log3 $name, 1, "Wattpilot ($name) - Cannot send command, missing stored password hash.";
        return;
    }
    
    # Msg ID Zähler
    $hash->{msg_id} = 0 if (!defined $hash->{msg_id});
    $hash->{msg_id}++;
    my $requestId = $hash->{msg_id};

    my $payload = {
        type => "setValue",
        requestId => $requestId,
        key => $key,
        value => $val
    };
    
    # JSON Encoding des Payloads für die Signatur
    my $payload_str = encode_json($payload);
    
    # Berechne HMAC SHA256 mit hashed_password als Key
    my $hmac = Digest::SHA::hmac_sha256_hex($payload_str, $stored_hash);
    
    my $secure_msg = {
        type => "securedMsg",
        data => $payload_str,
        requestId => "${requestId}sm",
        hmac => $hmac
    };
    
    my $final_msg = encode_json($secure_msg);
    Log3 $name, 3, "Wattpilot ($name) - Sending secured command key=$key requestId=$requestId";
    Wattpilot_WriteJson($hash, $final_msg);
}
"""
new_send = """sub Wattpilot_SendSecure($$$) {
    my ($hash, $key, $val) = @_;
    my $name = $hash->{NAME};

    return "Device is disabled" if Wattpilot_IsDisabled($name);
    return "Wattpilot is disconnected" if !DevIo_IsOpen($hash);
    return "Wattpilot is not authenticated" if !$hash->{helper}{authenticated}
        || ($hash->{STATE} // '') ne 'connected';

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

    my $payload = {
        type => "setValue",
        requestId => $requestId,
        key => $key,
        value => $val
    };
    my $payload_str = encode_json($payload);
    my $hmac = Digest::SHA::hmac_sha256_hex($payload_str, $stored_hash);
    my $secure_msg = {
        type => "securedMsg",
        data => $payload_str,
        requestId => "${requestId}sm",
        hmac => $hmac
    };

    my $final_msg = encode_json($secure_msg);
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
    return $normalized =~ /^\\d+$/ ? int($normalized) : undef;
}

sub Wattpilot_ClearCommandState($) {
    my ($hash) = @_;
    RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
    delete $hash->{helper}{pendingRequests};
    delete $hash->{helper}{authenticated};
}

sub Wattpilot_ScheduleRequestTimeout($) {
    my ($hash) = @_;
    RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
    my $pending = $hash->{helper}{pendingRequests} // {};
    return if !keys %$pending;
    my ($next) = sort { $a <=> $b }
        map { $pending->{$_}{sentAt} + $WATTPILOT_REQUEST_TIMEOUT } keys %$pending;
    InternalTimer($next, 'Wattpilot_RequestTimeout', $hash, 0);
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
    my ($hash) = @_;
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
"""
module = replace_once(module, old_send, new_send, 'secure command/response bookkeeping')

module = replace_once(
    module,
    "sub Wattpilot_Ready($) {\n    my ($hash) = @_;\n    if($hash->{STATE} eq \"disconnected\") {\n        return Wattpilot_OpenDev($hash, 1, sub {",
    "sub Wattpilot_Ready($) {\n    my ($hash) = @_;\n    if($hash->{STATE} eq \"disconnected\") {\n        Wattpilot_ClearCommandState($hash);\n        return Wattpilot_OpenDev($hash, 1, sub {",
    'ready clears command state',
)

module = replace_once(
    module,
    "        if($cmd eq \"set\" && $attrVal eq \"1\") {\n             RemoveInternalTimer($hash);",
    "        if($cmd eq \"set\" && $attrVal eq \"1\") {\n             Wattpilot_ClearCommandState($hash);\n             RemoveInternalTimer($hash);",
    'disable clears command state',
)

module = module.replace('"version": "v1.3.0"', '"version": "v1.4.0"')
if module.count('"version": "v1.4.0"') != 1:
    raise SystemExit('META version replacement failed')

module = replace_once(
    module,
    "        Manually starts or stops charging (corresponds to parameter <code>frc</code>).</li>",
    "        Manually starts or stops charging (corresponds to parameter <code>frc</code>). Start sends <code>2</code>, Stop sends <code>1</code>; the reading keeps the compatible labels <code>Start</code>/<code>Stop</code> and adds <code>Neutral</code> for value <code>0</code>.</li>",
    'English commandref frc',
)
module = replace_once(
    module,
    "        Sets the charging current in ampere.</li>",
    "        Sets the charging current in ampere. Values outside the public range 6–32 are rejected before any message is sent.</li>",
    'English commandref amp',
)
module = replace_once(
    module,
    "    <li><code>Laden_starten</code><br>\n        Charging enable state derived from <code>frc</code>.</li>",
    "    <li><code>Laden_starten</code><br>\n        Force-state reading derived from <code>frc</code>: <code>Neutral</code>, <code>Stop</code>, <code>Start</code>, or an explicit <code>Unknown(value)</code>.</li>\n\n    <li><code>lastCommandStatus</code>, <code>lastCommandRequestId</code>, <code>lastCommandError</code><br>\n        Result of the most recent secured command: pending, success, failed, or timeout. Device error payloads remain suppressed in normal logging.</li>",
    'English command readings',
)
module = replace_once(
    module,
    "        Startet oder stoppt den Ladevorgang manuell (entspricht dem Parameter <code>frc</code>).</li>",
    "        Startet oder stoppt den Ladevorgang manuell (entspricht dem Parameter <code>frc</code>). Start sendet <code>2</code>, Stop sendet <code>1</code>; das Reading behält die kompatiblen Werte <code>Start</code>/<code>Stop</code> und ergänzt <code>Neutral</code> für Wert <code>0</code>.</li>",
    'German commandref frc',
)
module = replace_once(
    module,
    "        Setzt den Ladestrom in Ampere.</li>",
    "        Setzt den Ladestrom in Ampere. Werte außerhalb des öffentlichen Bereichs 6–32 werden vor dem Senden abgewiesen.</li>",
    'German commandref amp',
)
module = replace_once(
    module,
    "    <li><code>Laden_starten</code><br>\n        Ladefreigabe-Zustand aus <code>frc</code>.</li>",
    "    <li><code>Laden_starten</code><br>\n        Force-State aus <code>frc</code>: <code>Neutral</code>, <code>Stop</code>, <code>Start</code> oder ein explizites <code>Unknown(value)</code>.</li>\n\n    <li><code>lastCommandStatus</code>, <code>lastCommandRequestId</code>, <code>lastCommandError</code><br>\n        Ergebnis des letzten gesicherten Befehls: pending, success, failed oder timeout. Geräte-Fehlerpayloads bleiben im normalen Logging unterdrückt.</li>",
    'German command readings',
)

module_path.write_text(module, encoding='utf-8')

stub_path = Path('t/lib/DevIo.pm')
stub = stub_path.read_text(encoding='utf-8')
stub = replace_once(
    stub,
    "our $FHEM_SOURCE_REVISION = '5354e001b55c323f457bd907434e46f284d9582c';",
    "our $FHEM_SOURCE_REVISION = '5354e001b55c323f457bd907434e46f284d9582c';\nour $FHEM_TIMER_SOURCE_REVISION = '72a81ea2b3836953fd52afbbd3f1ced034e3baeb';\nour $NOW;",
    'timer source revision',
)
stub = replace_once(stub, "    @IGNORED_RENAME_REPLIES = ();\n}", "    @IGNORED_RENAME_REPLIES = ();\n    $NOW = undef;\n}", 'reset NOW')
stub = replace_once(
    stub,
    "sub RemoveInternalTimer {\n    my ($argument) = @_;\n    push @REMOVED_TIMERS, $argument;\n    @ACTIVE_TIMERS = grep { $_->[2] != $argument } @ACTIVE_TIMERS;\n    return;\n}\nsub gettimeofday { return time }\nsub readingsSingleUpdate {",
    "sub RemoveInternalTimer {\n    my ($argument, $function) = @_;\n    push @REMOVED_TIMERS, [$argument, $function];\n    @ACTIVE_TIMERS = grep {\n        my ($timer_function, $timer_argument) = ($_->[1], $_->[2]);\n        !(defined($timer_argument) && $timer_argument == $argument\n          && (!defined($function) || $timer_function eq $function));\n    } @ACTIVE_TIMERS;\n    return;\n}\nsub run_due_timers {\n    my ($now) = @_;\n    $NOW = $now;\n    my @due = grep { $_->[0] <= $now } @ACTIVE_TIMERS;\n    @ACTIVE_TIMERS = grep { $_->[0] > $now } @ACTIVE_TIMERS;\n    for my $timer (@due) {\n        no strict 'refs';\n        &{\"main::$timer->[1]\"}($timer->[2]);\n        use strict 'refs';\n    }\n}\nsub gettimeofday { return defined($NOW) ? $NOW : time }\nsub readingsSingleUpdate {",
    'timer fidelity',
)
stub = replace_once(
    stub,
    "sub readingsBeginUpdate { return }\nsub readingsBulkUpdate { return }\nsub readingsEndUpdate { return }",
    "sub readingsBeginUpdate { return }\nsub readingsBulkUpdate {\n    push @READING_UPDATES, [@_];\n    my ($hash, $reading, $value) = @_;\n    $hash->{READINGS}{$reading}{VAL} = $value;\n    return;\n}\nsub readingsEndUpdate { return }",
    'bulk reading fidelity',
)
stub_path.write_text(stub, encoding='utf-8')

test_path = Path('t/command_semantics.t')
test_path.write_text(r'''use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs);
my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'testWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000008',
        DeviceName => 'ws:192.0.2.10:80/ws', STATE => 'connected',
        TEST_OPEN => 1, helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer, decode_json($outer->{data}));
}

my $hash = fresh_device();
for my $case ([0, 'Neutral'], [1, 'Stop'], [2, 'Start'], [7, 'Unknown(7)']) {
    main::Wattpilot_UpdateReadings($hash, { frc => $case->[0] });
    is($hash->{READINGS}{Laden_starten}{VAL}, $case->[1], "frc=$case->[0] maps explicitly");
}

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'testWallbox', 'Laden_starten', 'Start'), undef,
    'Start command is accepted while connected and authenticated');
my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
is($inner->{key}, 'frc', 'Start writes frc');
is($inner->{value}, 2, 'Start writes frc=2');
is($outer->{requestId}, '1sm', 'secured wrapper uses correlated request ID');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'pending', 'command is pending until response');

main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { amp => 20, frc => 2 },
}));
is($hash->{READINGS}{Strom}{VAL}, 20, 'successful response updates returned amp status');
is($hash->{READINGS}{Laden_starten}{VAL}, 'Start', 'successful response uses normal frc update path');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success', 'successful response completes request');
ok(!exists $hash->{helper}{pendingRequests}, 'successful response removes pending request');

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'testWallbox', 'Laden_starten', 'Stop'), undef,
    'Stop command is accepted');
(undef, $inner) = inner_payload($DevIo::WRITES[0]);
is($inner->{value}, 1, 'Stop writes frc=1');

for my $accepted (6, 32) {
    $hash = fresh_device();
    is(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', $accepted), undef,
        "Strom boundary $accepted is accepted");
    (undef, $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{value}, $accepted, "Strom sends exact boundary $accepted");
}
for my $rejected (5, 33, '6.5', 'abc') {
    $hash = fresh_device();
    like(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', $rejected), qr/6-32/,
        "Strom value $rejected is rejected");
    is(scalar @DevIo::WRITES, 0, 'rejected Strom value sends no frame');
}

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
like(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16), qr/disconnected/,
    'disconnected command returns actionable error');
is(scalar @DevIo::WRITES, 0, 'disconnected command sends no frame');

$hash = fresh_device();
delete $hash->{helper}{authenticated};
like(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16), qr/not authenticated/,
    'unauthenticated command returns actionable error');
is(scalar @DevIo::WRITES, 0, 'unauthenticated command sends no frame');

$hash = fresh_device();
delete $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'};
like(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16), qr/signing key is missing/,
    'missing signing key returns actionable error');
is(scalar @DevIo::WRITES, 0, 'missing signing key sends no frame');

$hash = fresh_device();
main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => '1sm', success => JSON::false,
    message => 'SYNTHETIC-SECRET-DETAIL',
}));
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed', 'failed response is exposed');
is($hash->{READINGS}{lastCommandError}{VAL}, 'device rejected amp', 'failed response uses concise redacted error');
unlike(join("\n", map { $_->[2] // '' } @DevIo::LOGS), qr/SYNTHETIC-SECRET-DETAIL/,
    'normal logs suppress the device error payload');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { amp => 18, frc => 0 });
main::Wattpilot_Set($hash, 'testWallbox', 'Modus', 'Eco');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 99, success => JSON::true, status => { frc => 2 },
}));
is($hash->{READINGS}{Strom}{VAL}, 18, 'unmatched response does not reset an existing reading');
ok(exists $hash->{helper}{pendingRequests}{1}, 'unmatched response does not consume another request');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true, status => { frc => 2 },
}));
is($hash->{READINGS}{Strom}{VAL}, 18, 'missing response field leaves existing reading unchanged');
is($hash->{READINGS}{Laden_starten}{VAL}, 'Start', 'present response field updates normally');

$hash = fresh_device();
$DevIo::NOW = 1000;
main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16);
ok(scalar(grep { $_->[1] eq 'Wattpilot_RequestTimeout' } @DevIo::ACTIVE_TIMERS),
    'pending request schedules a timeout timer');
DevIo::run_due_timers(1031);
ok(!exists $hash->{helper}{pendingRequests}, 'timeout removes pending request');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'timeout', 'timeout is exposed through command status');
is($hash->{READINGS}{lastCommandError}{VAL}, 'response timeout', 'timeout exposes concise error');

$hash = fresh_device();
$hash->{helper}{pendingRequests} = {
    map { $_ => { key => 'amp', value => 16, sentAt => 1000 + $_ } } 1 .. 32
};
$DevIo::NOW = 1000;
like(main::Wattpilot_Set($hash, 'testWallbox', 'Strom', 16), qr/Too many/,
    'pending request bookkeeping is bounded');
is(scalar @DevIo::WRITES, 0, 'bounded bookkeeping rejects an additional frame');

done_testing;
''', encoding='utf-8')

readme = Path('README.md').read_text(encoding='utf-8')
readme = readme.replace('Aktuelle Modulversion: **1.3.0**.', 'Aktuelle Modulversion: **1.4.0**.', 1)
readme = replace_once(
    readme,
    'Startet oder stoppt den Ladevorgang manuell.\n',
    'Startet oder stoppt den Ladevorgang manuell. `Start` sendet `frc=2`, `Stop` sendet `frc=1`; das Reading zeigt zusätzlich `Neutral` für `frc=0`. Befehle werden nur bei offener, authentifizierter Verbindung und vorhandenem Signaturschlüssel gesendet.\n',
    'README command semantics',
)
readme = replace_once(
    readme,
    'Legt den Ladestrom in Ampere fest (zwischen 6A und 32A).',
    'Legt den Ladestrom in Ampere fest. Nur ganzzahlige Werte von 6 A bis 32 A werden akzeptiert; ungültige Werte werden vor dem Senden abgewiesen.',
    'README amp validation',
)
Path('README.md').write_text(readme, encoding='utf-8')

readme_en = Path('README_en.md').read_text(encoding='utf-8')
readme_en = readme_en.replace('Current module version: **1.3.0**.', 'Current module version: **1.4.0**.', 1)
readme_en = replace_once(
    readme_en,
    'Starts or stops charging manually.\n',
    'Starts or stops charging manually. `Start` sends `frc=2`, `Stop` sends `frc=1`; the reading also reports `Neutral` for `frc=0`. Commands are sent only while the connection is open, authenticated, and a signing key is available.\n',
    'README_en command semantics',
)
readme_en = replace_once(
    readme_en,
    'Sets the charging current in ampere (between 6A and 32A).',
    'Sets the charging current in ampere. Only integer values from 6 A through 32 A are accepted; invalid values are rejected before sending.',
    'README_en amp validation',
)
Path('README_en.md').write_text(readme_en, encoding='utf-8')

changelog = Path('CHANGELOG.md').read_text(encoding='utf-8')
changelog = replace_once(
    changelog,
    '## [Unreleased]\n',
    '''## [Unreleased]\n\n## [v1.4.0] - 2026-06-22\n\n### Geändert\n\n- `frc` verwendet die korrigierten Werte 0=Neutral, 1=Stop und 2=Start; unbekannte Werte bleiben ausdrücklich unbekannt.\n- Gesicherte Befehle werden nur bei offener und authentifizierter Verbindung sowie vorhandenem Signaturschlüssel gesendet. `Strom` wird vor dem Senden auf 6–32 A begrenzt.\n- `response`-Nachrichten werden über die Request-ID korreliert, erfolgreiche Statuswerte über denselben Reading-Pfad verarbeitet und Fehler beziehungsweise Timeouts redigiert über Command-Readings gemeldet. Pending-Requests sind auf 32 Einträge und 30 Sekunden begrenzt.\n''',
    'changelog v1.4.0',
)
Path('CHANGELOG.md').write_text(changelog, encoding='utf-8')

sources = Path('docs/PROTOCOL-SOURCES.md').read_text(encoding='utf-8')
sources = replace_once(
    sources,
    '- **`amp`:** the Flex 43.4 capture contains `amp=32` and `cll.currentLimitMax=32`. The pinned older Wattpilot-specific source at commit `4712ba3b8409fda55303870c047038b1b221d7ff` states R/W amperes with range 6–16, while Issue #8 targets 6–32 for the current public command. The accepted Flex 43.4 write range remains unverified.\n',
    '- **`amp`:** the Flex 43.4 capture contains `amp=32` and `cll.currentLimitMax=32`. The pinned older Wattpilot-specific source at commit `4712ba3b8409fda55303870c047038b1b221d7ff` states R/W amperes with range 6–16. Version 1.4.0 validates the established public FHEM command to 6–32 A; the exact Flex 43.4 device-side rejection behavior remains unverified.\n- **Secured commands and `response`:** `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff` emits numeric request IDs inside `setValue`, wraps secured writes with an `sm`-suffixed outer ID and HMAC, and correlates incoming `response.requestId`. Successful optional `status` fields are applied as partial updates; failures expose request ID plus a device message. This is pinned third-party Wattpilot evidence, not official Fronius documentation. Version 1.4.0 accepts numeric IDs and their `sm` form, suppresses untrusted device messages in normal diagnostics, and bounds pending state to 32 requests/30 seconds.\n',
    'protocol response evidence',
)
Path('docs/PROTOCOL-SOURCES.md').write_text(sources, encoding='utf-8')

api = Path('docs/WATTPILOT-FLEX-JSON-API.md').read_text(encoding='utf-8')
api = replace_once(
    api,
    '- Evidence: historical compilation only; current 1.x parser does not handle this type and the accepted capture does not contain it.\n- Open questions: complete Flex 43.4 schema, error shape, request-ID type, and whether status is always returned.',
    '- Evidence: pinned Wattpilot-specific third-party implementation at commit `4712ba3b8409fda55303870c047038b1b221d7ff`; not observed in the accepted Flex capture and not official Fronius documentation. Version 1.4.0 correlates numeric request IDs and `sm`-suffixed IDs, treats returned `status` as a partial update, and reports failures without copying the device message into normal logs/readings.\n- Open questions: complete Flex 43.4 schema, device-side timeout, error-code fields, and whether status is always returned.',
    'API response evidence',
)
Path('docs/WATTPILOT-FLEX-JSON-API.md').write_text(api, encoding='utf-8')

print('Issue #8 transformation applied')
