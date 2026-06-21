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
use DevIo;
use FHEM::Meta;
use JSON;
use Digest::SHA qw(sha256_hex);
use Crypt::PBKDF2;

my $WATTPILOT_VERSION = '1.3.0';

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
    
    # Attribut-Liste:
    # interval: Schieberegler von 0 bis 300, Schrittweite 5 (Sekunden)
    # update_while_idle: Boolean (0/1) um Updates auch im Leerlauf zu erzwingen
    # defaultAmp: Standard-Stromstärke (kann als Slider dargestellt werden, z.B. 6-32A)
    $hash->{AttrList} = "debug:1,0 interval:slider,0,5,300 update_while_idle:0,1 defaultAmp:slider,6,1,32 disable:0,1 rawJsonLog:0,1 authHash:auto,pbkdf2,bcrypt " .
	$readingFnAttributes;

    return FHEM::Meta::InitMod(__FILE__, $hash);
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
	
	
    # DevIo WebSocket URL Format: ws:host:port/path
    $hash->{DeviceName} = "ws:$ip:80/ws";
    $hash->{SERIAL} = $serial;
    
	my $password = Wattpilot_GetPassword($hash);
	
    $hash->{STATE} = "Initialized";
    
    # WebSocket spezifische Header
    $hash->{header}{'User-Agent'} = 'FHEM';
    
    $modules{Wattpilot}{defptr}{$name} = $hash;
    
    # Starte Verbindungs-Timer (verzögerter Start) falls password verfügbar
	if (defined($password) && $password ne "") {
		readingsSingleUpdate($hash, "state", "connecting", 1);
		InternalTimer(gettimeofday()+2, "Wattpilot_Connect", $hash, 0);
	} else {
		readingsSingleUpdate($hash, "state", "password missing", 1);
	}
    return undef;
}

sub Wattpilot_Undefine($$) {
    my ($hash, $name) = @_;

    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    
    delete $modules{Wattpilot}{defptr}{$name};
    return undef;
}

sub Wattpilot_Delete($) {
    my ($hash) = @_;

    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    Wattpilot_DeleteStoredSecrets($hash);
    return undef;
}

sub Wattpilot_Rename($$) {
    my ($new_name, $old_name) = @_;
    my $hash = $defs{$new_name};
    return undef if !defined $hash;

    delete $modules{Wattpilot}{defptr}{$old_name};
    $modules{Wattpilot}{defptr}{$new_name} = $hash;
    Wattpilot_MigrateLegacySecrets($hash, $old_name);
    return undef;
}

sub Wattpilot_Connect($) {
    my ($hash) = @_;
    
    return if(DevIo_IsOpen($hash));
    return if(Wattpilot_IsDisabled($hash->{NAME}));
    
    Log3 $hash, 3, "Wattpilot ($hash->{NAME}) - Opening WebSocket connection";
    
    # WebSocket in DevIo benötigt einen Callback für den asynchronen Verbindungsaufbau
    DevIo_OpenDev($hash, 0, undef, sub {
        my ($hash, $error) = @_;
        if($error) {
            Log3 $hash, 1, "Wattpilot ($hash->{NAME}) - WebSocket connection failed";
            return;
        }
        Wattpilot_DoInit($hash);
    });
}

sub Wattpilot_DoInit($) {
    my ($hash) = @_;
    # Hier könnten Initialisierungsbefehle gesendet werden, falls nötig
    return undef;
}

sub Wattpilot_Read($) {
    my ($hash) = @_;
    my $buf = DevIo_SimpleRead($hash);
    
    return "" if(!defined($buf));
    
    if($hash->{buffer}) {
        $buf = $hash->{buffer} . $buf;
        $hash->{buffer} = "";
    }

    # Behandle mehrere verkettete JSON-Nachrichten (z.B. json1}{json2)
    # Der Wattpilot sendet manchmal mehrere Pakete ohne Trennzeichen zusammen.
    $buf =~ s/}\s*{/}\n{/g;
    
    my @messages = split(/\n/, $buf);
    
    foreach my $msg (@messages) {
        # Prüfe, ob die Nachricht wie ein vollständiges JSON-Objekt aussieht
        if ($msg =~ m/^{.*}$/) {
             Wattpilot_Parse($hash, $msg);
        } else {
             # Unvollständige Nachricht? Im Buffer für den nächsten Read speichern.
             # Hinweis: Einfaches Buffering. Sollte für die normale JSON-Struktur ausreichen.
             $hash->{buffer} = $msg;
        }
    }
}

sub Wattpilot_Parse($$) {
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
	
    Wattpilot_LogRawJson($hash, "IN", $msg);
    
    my $json = eval { decode_json($msg) };
    if($@) {
        Log3 $name, 1, "Wattpilot ($name) - JSON decoding failed; payload suppressed";
        return;
    }
    
    my $type = $json->{type} // "";
    my %known_type = map { $_ => 1 } qw(hello authRequired authSuccess authError fullStatus deltaStatus);
    Log3 $name, 4, "Wattpilot ($name) - Received JSON message type=" . ($known_type{$type} ? $type : "unknown");
    
    if ($type eq 'hello') {
        $hash->{SERIAL} = $json->{serial} if (!$hash->{SERIAL}); # Seriennummer übernehmen falls fehlt
        $hash->{VERSION} = $json->{version};
        readingsSingleUpdate($hash, "version", $json->{version}, 1);
        Log3 $name, 4, "Wattpilot ($name) - Hello received";
    } elsif ($type eq 'authRequired') {
        Log3 $name, 4, "Wattpilot ($name) - Auth Required";
        Wattpilot_SendAuth($hash, $json);
    } elsif ($type eq 'authSuccess') {
        Log3 $name, 2, "Wattpilot ($name) - Authentication Successful";
        readingsSingleUpdate($hash, "state", "connected", 1);
    } elsif ($type eq 'authError') {
        Log3 $name, 1, "Wattpilot ($name) - Authentication failed";
        readingsSingleUpdate($hash, "state", "auth_failed", 1);
        DevIo_CloseDev($hash);
    } elsif ($type eq 'fullStatus' || $type eq 'deltaStatus') {
        Wattpilot_UpdateReadings($hash, $json->{status});
    }
}

sub Wattpilot_UpdateReadings($$) {
    my ($hash, $status) = @_;
    my $name = $hash->{NAME};
    
    # Rate-Limiting Logik:
    # Einige Werte (wie 'nrg' - Spannung/Strom) aktualisieren sehr häufig (hochfrequent).
    # Andere (wie 'amp', 'car', 'frc') sind niederfrequent und kritisch für die UI.
    # Das Intervall wird NUR auf die hochfrequenten "Spam"-Werte angewendet.
    
    my $interval = AttrVal($name, "interval", 0);
    my $now = gettimeofday();
    my $last_update = $hash->{LAST_UPDATE} // 0;
    
    # Unterdrücke Spam-Werte, wenn Intervall noch nicht abgelaufen
    my $suppress_spammy = ($interval > 0 && ($now - $last_update < $interval));
    
    # Aktualisiere Zeitstempel nur, wenn wir diesmal updaten
    if (!$suppress_spammy) {
        $hash->{LAST_UPDATE} = $now;
    }
    
    readingsBeginUpdate($hash);
    
    # --- KRITISCHE / NIEDERFREQUENTE UPDATES (Immer aktualisieren) ---
    
    # Fahrzeug Status (Car State)
    if (defined $status->{car}) {
        my %CarStateMap = (0 => 'Unknown', 1 => 'Idle', 2 => 'Charging', 3 => 'WaitCar', 4 => 'Complete', 5 => 'Error');
        my $state = $CarStateMap{int($status->{car})} // "Unknown";
        readingsBulkUpdate($hash, "CarState", $state);
        
        # Speichere internen Status für Logik (Charging vs Not Charging)
        $hash->{helper}{car_state} = int($status->{car});
    }
    
    # Prüfe ob geladen wird (Status 2)
    my $is_charging = ($hash->{helper}{car_state} // 0) == 2;
    
    # Laden Starten/Stoppen (frc Status)
    if (defined $status->{frc}) {
        my $frc_val = $status->{frc};
        my $state = "Unknown";
        if ($frc_val == 0) { $state = "Start"; }
        elsif ($frc_val == 1) { $state = "Stop"; }
        else { $state = $frc_val; }
        readingsBulkUpdate($hash, "Laden_starten", $state);
    }
    
    # Nächste Fahrt Zeit (ftt)
    if (defined $status->{ftt}) {
        # Sekunden ab Mitternacht in hh:mm umrechnen
        my $secs = $status->{ftt};
        my $h = int($secs / 3600);
        my $m = int(($secs % 3600) / 60);
        readingsBulkUpdate($hash, "Zeit_NextTrip", sprintf("%02d:%02d", $h, $m));
    }
    
    # Stromstärke (amp) - Sollte immer sofort aktualisiert werden
    if (defined $status->{amp}) {
        readingsBulkUpdate($hash, "Strom", $status->{amp});
    }
	
	if (defined $status->{lmo}) {
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
    
    my $process_nrg = 0;
    if (!$suppress_spammy) {
        if ($is_charging || $update_while_idle) {
             $process_nrg = 1;
        }
    }
    
    if ($process_nrg) {
        
        # Energie Gesamt (eto)
        if (defined $status->{eto}) {
             # Rundung auf 2 Nachkommastellen, Umrechnung Wh -> kWh wenn nötig (Hier Annahme: Rohwert durch 1000)
             readingsBulkUpdate($hash, "EnergyTotal", sprintf("%.2f", $status->{eto} / 1000));
        }

        # Energie seit Anstecken (wh)
        if (defined $status->{wh}) {
             readingsBulkUpdate($hash, "Energie_seit_Anstecken", sprintf("%.2f", $status->{wh}));
        }
        
        # Energie Details (nrg Array)
        if (defined $status->{nrg}) {
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
    my $password = Wattpilot_GetPassword($hash);
    my $serial   = $hash->{SERIAL};

    if (!$password || !$serial) {
        Log3 $name, 1, "Wattpilot ($name) - Missing Password or Serial for authentication";
        return;
    }

    my $mode = eval { Wattpilot_GetAuthHashMode($hash, $json) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Failed to determine authentication hash mode";
        return;
    }
    $hash->{helper}{authHashMode} = $mode;

    my $password_hash = eval {
        Wattpilot_DerivePasswordHash($hash, $password, $serial);
    };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - Password hash derivation failed for mode=$mode";
        readingsSingleUpdate($hash, "state", "auth_hash_failed", 1);
        return;
    }

    Wattpilot_SetStoredPasswordHash($hash, $password_hash);

    my $token1 = $json->{token1};
    my $token2 = $json->{token2};

    my $random_bytes = '';
    for (my $i = 0; $i < 16; $i++) {
        $random_bytes .= chr(int(rand(256)));
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

    my $msg = encode_json($auth_response);
    Log3 $name, 3, "Wattpilot ($name) - Sending Auth Response using mode=$mode";
    Wattpilot_LogRawJson($hash, "OUT", $msg);
    DevIo_SimpleWrite($hash, $msg, 0);
	
	readingsSingleUpdate($hash, "authHashMode", $mode, 1);
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
    my $mode = $hash->{helper}{authHashMode} // "pbkdf2";

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
	} elsif ($cmd eq 'Password') {
		return "Usage: set $name Password <secret>" if (!defined($a[2]) || $a[2] eq "");

		my $password = $a[2];
		my $key = eval { Wattpilot_SecretKey($hash, "password") };
		return "failed to determine stable credential key" if $@;

		my $err = setKeyValue($key, $password);
		return "failed to store password: $err" if defined($err);

		my $hashkey = Wattpilot_SecretKey($hash, "passwordhash");
		my $hash_err = setKeyValue($hashkey, undef);
		return "password stored, but failed to clear password hash: $hash_err" if defined($hash_err);
		
	
		readingsSingleUpdate($hash, "state", "password stored", 1);
		
		RemoveInternalTimer($hash);
		DevIo_CloseDev($hash);
		InternalTimer(gettimeofday()+1, "Wattpilot_Connect", $hash, 0);
		
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
    
    my $stored_hash = Wattpilot_GetPasswordHash($hash);
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
    Wattpilot_LogRawJson($hash, "OUT", $final_msg);
    DevIo_SimpleWrite($hash, $final_msg, 0);
}

sub Wattpilot_Get($@) {
    my ($hash, @a) = @_;
    return undef;
}

sub Wattpilot_Ready($) {
    my ($hash) = @_;
    if($hash->{STATE} eq "disconnected") {
        return DevIo_OpenDev($hash, 1, undef, sub {
             my ($hash, $error) = @_;
             return if($error);
             Wattpilot_DoInit($hash);
         });
    }
    return 0;
}

sub Wattpilot_Attr(@) {
    my ($cmd, $name, $attrName, $attrVal) = @_;
    my $hash = $defs{$name};
    
    # $cmd kann "set" oder "del" sein
    # $name ist der Gerätename, $attrName das Attribut, $attrVal der Wert
    
    if($attrName eq "disable") {
        if($cmd eq "set" && $attrVal eq "1") {
             RemoveInternalTimer($hash);
             DevIo_CloseDev($hash);
             readingsSingleUpdate($hash, "state", "disabled", 1);
		} elsif($cmd eq "del" || $attrVal eq "0") {
			 my $password = Wattpilot_GetPassword($hash);
			 if (defined($password) && $password ne "") {
				 readingsSingleUpdate($hash, "state", "disconnected", 1);
				 InternalTimer(gettimeofday()+1, "Wattpilot_Connect", $hash, 0);
			 } else {
				 readingsSingleUpdate($hash, "state", "password missing", 1);
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
    
    return undef;
}

sub Wattpilot_IsDisabled($) {
    my ($name) = @_;
    return AttrVal($name, "disable", 0);
}


sub Wattpilot_GetAuthHashMode($$) {
    my ($hash, $json) = @_;
    my $name = $hash->{NAME};

    my $attr_mode   = AttrVal($name, "authHash", "auto");
    my $device_mode = lc($json->{hash} // "");

    return $attr_mode if ($attr_mode ne "auto");

    return "bcrypt" if ($device_mode eq "bcrypt");
    return "pbkdf2";
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

sub Wattpilot_DeleteStoredSecrets {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my %legacy_names = ($name => 1, %{ $hash->{helper}{credentialLegacyNames} // {} });
    for my $suffix (qw(password passwordhash)) {
        my @keys = (Wattpilot_SecretKey($hash, $suffix));
        push @keys, map { Wattpilot_LegacySecretKey($_, $suffix) } keys %legacy_names;
        for my $key (@keys) {
            my $err = setKeyValue($key, undef);
            Log3 $name, 1, "Wattpilot ($name) - failed to delete stored $suffix"
              if defined $err;
        }
    }
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

sub Wattpilot_GetStoredSecret($$) {
    my ($hash, $suffix) = @_;
    my $name = $hash->{NAME};
    my $key = eval { Wattpilot_SecretKey($hash, $suffix) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - stable credential key is unavailable";
        return undef;
    }

    my ($err, $value) = getKeyValue($key);
    if (defined $err) {
        Log3 $name, 1, "Wattpilot ($name) - could not read stored $suffix";
        return undef;
    }
    return $value if defined $value;

    return Wattpilot_MigrateLegacySecret($hash, $name, $suffix);
}

sub Wattpilot_MigrateLegacySecret($$$) {
    my ($hash, $legacy_name, $suffix) = @_;
    my $name = $hash->{NAME};
    my $legacy_key = Wattpilot_LegacySecretKey($legacy_name, $suffix);
    my ($read_err, $legacy_value) = getKeyValue($legacy_key);
    if (defined $read_err) {
        Log3 $name, 1, "Wattpilot ($name) - could not read legacy $suffix during credential migration";
        return undef;
    }
    return undef if !defined $legacy_value;
    $hash->{helper}{credentialLegacyNames}{$legacy_name} = 1;

    my $key = eval { Wattpilot_SecretKey($hash, $suffix) };
    if ($@) {
        Log3 $name, 1, "Wattpilot ($name) - stable credential key is unavailable; legacy $suffix retained";
        return $legacy_value;
    }
    my $write_err = setKeyValue($key, $legacy_value);
    if (defined $write_err) {
        Log3 $name, 1, "Wattpilot ($name) - credential migration failed to store $suffix; legacy value retained";
        return $legacy_value;
    }

    my $delete_err = setKeyValue($legacy_key, undef);
    Log3 $name, 1, "Wattpilot ($name) - credential migration stored $suffix but could not remove legacy key"
      if defined $delete_err;
    delete $hash->{helper}{credentialLegacyNames}{$legacy_name} if !defined $delete_err;
    Log3 $name, 3, "Wattpilot ($name) - migrated legacy $suffix to stable credential storage";
    return $legacy_value;
}

sub Wattpilot_MigrateLegacySecrets($$) {
    my ($hash, $legacy_name) = @_;
    for my $suffix (qw(password passwordhash)) {
        my $key = eval { Wattpilot_SecretKey($hash, $suffix) };
        next if $@;
        my ($err, $value) = getKeyValue($key);
        if (defined $err) {
            Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - could not inspect stable $suffix during rename";
            next;
        }
        if (!defined $value) {
            Wattpilot_MigrateLegacySecret($hash, $legacy_name, $suffix);
        } else {
            my $legacy_key = Wattpilot_LegacySecretKey($legacy_name, $suffix);
            my ($legacy_err, $legacy_value) = getKeyValue($legacy_key);
            if (defined $legacy_err) {
                Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - could not inspect legacy $suffix during rename";
            } elsif (defined $legacy_value) {
                my $delete_err = setKeyValue($legacy_key, undef);
                Log3 $hash->{NAME}, 1, "Wattpilot ($hash->{NAME}) - stable $suffix exists but legacy key could not be removed"
                  if defined $delete_err;
            }
        }
    }
}

sub Wattpilot_LogRawJson($$$) {
    my ($hash, $direction, $payload) = @_;
    my $name = $hash->{NAME};
    return if AttrVal($name, "rawJsonLog", 0) ne "1";
    return if AttrVal($name, "verbose", 3) < 5;
    Log3 $name, 5, "Wattpilot ($name) - RAW JSON $direction: $payload";
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
        Stores the password persistently under a stable FUUID-based key and starts a reconnect. The password is not stored in the device definition. Existing name-based credentials are migrated without deleting the old value before the new value is stored successfully. Undefine, rename, reload, <code>rereadcfg</code>, and disable preserve credentials; deleting the device removes them.</li>

    <li><code>set &lt;name&gt; Laden_starten &lt;Start|Stop&gt;</code><br>
        Manually starts or stops charging (corresponds to parameter <code>frc</code>).</li>

    <li><code>set &lt;name&gt; Strom &lt;6-32&gt;</code><br>
        Sets the charging current in ampere.</li>

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
        If set to <code>1</code>, high-frequency values are also updated while not charging. Useful for diagnostics.</li>

    <li><code>defaultAmp &lt;value&gt;</code><br>
        Default value for the current setting slider in the frontend.</li>

    <li><code>disable &lt;0|1&gt;</code><br>
        Disables the module completely. If set to <code>1</code>, the connection is closed.</li>

    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Default: <code>0</code>. Exact inbound and outbound JSON is logged only when this attribute is <code>1</code> and <code>verbose</code> is also <code>5</code>. This includes authentication and <code>securedMsg</code> frames. Enabling it emits a warning because logs can contain sensitive authentication, network, device, and operational data. Never share this output without sanitizing it.</li>

    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Selects the password hashing method for authentication.<br>
        <ul>
          <li><b>auto</b>: Use the method announced by the Wattpilot device</li>
          <li><b>pbkdf2</b>: Force legacy PBKDF2 authentication</li>
          <li><b>bcrypt</b>: Force bcrypt authentication (used by newer Wattpilot Flex devices)</li>
        </ul>
    </li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Current connection/authentication state, e.g. <code>connecting</code>, <code>connected</code>, <code>password missing</code>, <code>auth_failed</code>.</li>

    <li><code>version</code><br>
        Firmware / protocol version reported by the Wattpilot.</li>

    <li><code>authHashMode</code><br>
        Effective authentication hash mode currently used (<code>pbkdf2</code> or <code>bcrypt</code>).</li>

    <li><code>CarState</code><br>
        Vehicle charging state, for example <code>Idle</code>, <code>Charging</code>, <code>Complete</code>.</li>

    <li><code>Laden_starten</code><br>
        Charging enable state derived from <code>frc</code>.</li>

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
        Speichert das Passwort persistent unter einem stabilen FUUID-basierten Schlüssel und startet einen Reconnect. Das Passwort wird nicht in der Device-Definition gespeichert. Bestehende namensbasierte Zugangsdaten werden migriert, ohne den alten Wert vor erfolgreicher Speicherung des neuen Werts zu löschen. Undefine, Rename, Reload, <code>rereadcfg</code> und Disable erhalten die Zugangsdaten; nur das Löschen des Geräts entfernt sie.</li>

    <li><code>set &lt;name&gt; Laden_starten &lt;Start|Stop&gt;</code><br>
        Startet oder stoppt die Ladung manuell (entspricht dem Parameter <code>frc</code>).</li>

    <li><code>set &lt;name&gt; Strom &lt;6-32&gt;</code><br>
        Setzt den Ladestrom in Ampere.</li>

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
        Wenn auf <code>1</code> gesetzt, werden hochfrequente Messwerte auch im Leerlauf aktualisiert. Nützlich für Diagnosezwecke.</li>

    <li><code>defaultAmp &lt;wert&gt;</code><br>
        Standardwert für den Strom-Slider im Frontend.</li>

    <li><code>disable &lt;0|1&gt;</code><br>
        Deaktiviert das Modul vollständig. Bei <code>1</code> wird die Verbindung getrennt.</li>

    <li><code>rawJsonLog &lt;0|1&gt;</code><br>
        Standard: <code>0</code>. Exakte ein- und ausgehende JSON-Nachrichten werden nur protokolliert, wenn dieses Attribut <code>1</code> und gleichzeitig <code>verbose</code> auf <code>5</code> gesetzt ist. Dies umfasst Authentifizierungs- und <code>securedMsg</code>-Frames. Beim Aktivieren erscheint eine Warnung, da Logs sensible Authentifizierungs-, Netzwerk-, Geräte- und Betriebsdaten enthalten können. Diese Ausgabe niemals unbereinigt weitergeben.</li>

    <li><code>authHash &lt;auto|pbkdf2|bcrypt&gt;</code><br>
        Wählt das Verfahren zur Passwort-Hash-Bildung für die Authentifizierung.<br>
        <ul>
          <li><b>auto</b>: Das vom Gerät angekündigte Verfahren wird verwendet</li>
          <li><b>pbkdf2</b>: Erzwingt das ältere PBKDF2-Verfahren</li>
          <li><b>bcrypt</b>: Erzwingt bcrypt (für neuere Wattpilot-Flex-Geräte)</li>
        </ul>
    </li>
  </ul>
  <br>

  <a name="Wattpilot-readings"></a>
  <b>Readings</b>
  <ul>
    <li><code>state</code><br>
        Aktueller Verbindungs-/Authentifizierungsstatus, z.B. <code>connecting</code>, <code>connected</code>, <code>password missing</code> oder <code>auth_failed</code>.</li>

    <li><code>version</code><br>
        Vom Wattpilot gemeldete Firmware-/Protokollversion.</li>

    <li><code>authHashMode</code><br>
        Tatsächlich verwendetes Authentifizierungsverfahren (<code>pbkdf2</code> oder <code>bcrypt</code>).</li>

    <li><code>CarState</code><br>
        Fahrzeug-/Ladezustand, z.B. <code>Idle</code>, <code>Charging</code> oder <code>Complete</code>.</li>

    <li><code>Laden_starten</code><br>
        Ladefreigabe-Zustand aus <code>frc</code>.</li>

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
  "version": "v1.3.0",
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
        "Crypt::PBKDF2": "0"
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
