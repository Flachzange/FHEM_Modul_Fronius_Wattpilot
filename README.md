# FHEM Modul: 72_Wattpilot.pm - Benutzerhandbuch

Dieses Dokument beschreibt die Installation und Einrichtung des Fronius Wattpilot Moduls für FHEM. Das Modul ermöglicht die Steuerung der Wallbox über das lokale Netzwerk via WebSocket.

Aktuelle Modulversion: **2.1.7**. Dennis Gramespacher bleibt ursprünglicher Autor. Die Neuentwicklung der Version 2.x stammt von Flachzange und entstand mit KI-Unterstützung durch OpenAI ChatGPT; technische Entscheidungen und Release-Verantwortung liegen bei Flachzange. Weitere Angaben stehen in [`AUTHORS.md`](AUTHORS.md). Die Änderungshistorie wird ausschließlich in [`CHANGELOG.md`](CHANGELOG.md) gepflegt. Protokollquellen und Belastbarkeitsgrenzen stehen in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md).

## Unterschiede zum ursprünglichen Modul

Version 2.x ist eine grundlegende Überarbeitung und keine bloße Erweiterung des ursprünglichen Moduls.

| Bereich | Ursprünglicher Modulstand | Aktuelle Version 2.x |
| :--- | :--- | :--- |
| Definition und Passwort | Passwort als Bestandteil der FHEM-Definition | Definition ohne Passwort; Speicherung über `set <Name> password <secret>` unter stabilen FUUID-basierten Schlüsseln |
| Geräte und Authentifizierung | Vorgänger-Wattpilot mit PBKDF2 | Legacy-Profil bleibt erhalten; Wattpilot Flex wird ausschließlich über bcrypt authentifiziert |
| FHEM-Schnittstelle | Wenige deutsch benannte Readings und Setter | Einheitliche öffentliche Namen, 73 Readings, bestätigte Konfigurationsreadings und gruppierte Setter |
| Protokollverarbeitung | Grundlegende Verarbeitung von `hello`, Authentifizierung und Status | Strikte JSON-Typprüfung, partielle Statusmeldungen, robuste Nachrichtenfortsetzung, gesicherte Befehle und Antwortkorrelation |
| Laufzeitverhalten | Einfaches Intervall und Idle-Filter | Kontrollierter Lifecycle für Reload, Rename, `modify`, Disable, Reconnect und Delete sowie getrennte Telemetrie-Caches mit gemeinsamem Veröffentlichungstakt |
| Qualitätssicherung | Ursprünglicher Funktionsumfang | Umfangreiche Regressionstests, gepinnte FHEM-Core-Integration, Dokumentations- und reproduzierbare Releaseprüfungen |

Version 2.x ist nicht direkt kompatibel zu bestehenden Definitionen des ursprünglichen Moduls. Es gibt keine Aliase, automatische Reading-Bereinigung oder Migration von Automatisierungen und Datenbankabfragen. Für den Umstieg sollte ein neues FHEM-Device definiert und die abhängige Konfiguration gezielt angepasst werden.

## Unterstützte Gerätegenerationen

| Merkmal | Legacy-Wattpilot | Wattpilot Flex |
| :--- | :--- | :--- |
| Belegter Gerätebereich | Wattpilot Home 11/22 J 2.0 und Wattpilot Go 11/22 J 2.0 als ursprünglicher Gerätebereich | Real getestet mit Wattpilot Flex Home 22 C6, Firmware 43.4 |
| Authentifizierung | PBKDF2; beim belegten Legacy-Profil `devicetype=wattpilot` und `hello.protocol=2` darf `authRequired.hash` fehlen | Ausschließlich bcrypt; `Crypt::Bcrypt` ist für Wattpilot Flex zwingend erforderlich |
| `authHash=auto` | Wählt beim belegten Legacy-Profil ohne Hash-Angabe PBKDF2 | Erwartet und übernimmt bcrypt; PBKDF2 ist kein unterstütztes Flex-Profil |
| Erweiterte Felder | Grundlegende Lade-, Energie- und elektrische Werte sind durch Regressionstests abgedeckt | Zusätzliche Konfigurations-, Diagnose- und stationäre PV-Speicherfelder sind für Flex 43.4 dokumentiert beziehungsweise real getestet |
| Prüfstatus | Automatisierter Kompatibilitätstest auf Basis gepinnter Wattpilot-Implementierung; kein aktueller Realgerätetest | Mehrere reale FHEM-, Authentifizierungs-, Reading- und Settertests auf einem Flex 43.4; andere Flex-Modelle und Firmwarestände sind nicht vollständig verifiziert |

Das Modul behauptet keine allgemeine Kompatibilität mit beliebigen go-eChargern. Felder, die ein Gerät nicht sendet, erzeugen beziehungsweise verändern keine Readings. Bei nicht real getesteten Kombinationen bleibt die Geräteunterstützung auf den dokumentierten Kompatibilitätsvertrag begrenzt.

## 1. Voraussetzungen (System & Perl Module)

Damit das Modul funktioniert, müssen auf dem FHEM-Server einige Perl-Zusatzmodule installiert sein.

### Für alle Geräte benötigte Perl-Pakete

* `JSON`
* `Crypt::PBKDF2`
* `Crypt::URandom`
* `Digest::SHA`
* `MIME::Base64`

`Crypt::PBKDF2` wird beim Laden des Moduls eingebunden und ist daher auch dann erforderlich, wenn ein Wattpilot Flex später bcrypt auswählt.

### Zusätzlich und zwingend für Wattpilot Flex

* `Crypt::Bcrypt`

`Crypt::Bcrypt` ist für Wattpilot Flex zwingend erforderlich, weil Flex ausschließlich bcrypt verwendet. Der belegte Legacy-Wattpilot verwendet dagegen PBKDF2.

### Installation der Pakete (Debian/Raspbian/Ubuntu)

Führen Sie folgende Befehle im Terminal aus:

```bash
sudo apt-get update
sudo apt-get install libjson-perl libdigest-sha-perl libmime-base64-perl
```

Für die zusätzlichen Kryptografie-Module nutzen Sie am besten cpanminus:

```bash
sudo apt-get install cpanminus
sudo cpanm Crypt::PBKDF2 Crypt::URandom
```

Für Wattpilot Flex zusätzlich und zwingend:

```bash
sudo cpanm Crypt::Bcrypt
```

## 2. Installation des Moduls

1. Laden Sie die Datei `72_Wattpilot.pm` herunter.
2. Kopieren Sie die Datei in das FHEM-Installationsverzeichnis, genauer in den Ordner `FHEM`.
    * Standardpfad (Linux): `/opt/fhem/FHEM/`
    * Beispielbefehl: `cp 72_Wattpilot.pm /opt/fhem/FHEM/`
3. Setzen Sie die korrekten Berechtigungen (optional, aber empfohlen):

    ```bash
    sudo chown fhem:dialout /opt/fhem/FHEM/72_Wattpilot.pm
    sudo chmod 644 /opt/fhem/FHEM/72_Wattpilot.pm
    ```

4. Starten Sie FHEM neu (`shutdown restart` in FHEM eingeben) oder laden Sie das Modul neu mit `reload 72_Wattpilot`.

## 3. Einrichtung in FHEM (Definition)

Um die Wallbox in FHEM einzubinden, legen Sie ein neues "Device" an.

### Syntax

```text
define <Name> Wattpilot <IP-Adresse> [Seriennummer]
```

* **<Name>**: Ein Name für das Gerät in FHEM (z.B. `wallbox` oder `meinWattpilot`).
* **<IP-Adresse>**: Die lokale IP-Adresse des Wattpilot im Netzwerk (z.B. `192.0.2.10`, reserviert für Dokumentation).
* **[Seriennummer]** (Optional): Eine ausschließlich aus Ziffern bestehende Seriennummer. Normalerweise bleibt sie weg und wird aus der `hello`-Nachricht des Geräts übernommen.

### Wofür wird die Seriennummer benötigt?

Die Seriennummer ist kein zusätzlicher FHEM-Gerätename, sondern ein kryptografischer Eingabewert: Sowohl PBKDF2 als auch bcrypt leiten den gerätespezifischen Passwort-Hash unter Einbeziehung der Seriennummer ab. Das gilt für Legacy-Wattpilot und Wattpilot Flex.

Im Normalfall sendet der Wattpilot seine Seriennummer vor der Authentifizierung in der `hello`-Nachricht, sodass sie nicht in der Definition stehen muss. Eine explizite Angabe fixiert den verwendeten Wert und ist nur sinnvoll, wenn die automatische Übernahme nicht funktioniert. Eine falsche Seriennummer führt zu einer fehlerhaften Hash-Ableitung und damit zu einer fehlgeschlagenen Anmeldung. Fehlt sowohl in der Definition als auch in `hello` eine gültige numerische Seriennummer, endet die Anmeldung mit `authConfigMissing`.

Das Passwort wird separat mit `set <Name> password <secret>` gesetzt und nicht in der Definition gespeichert.

**Versionsanzeige:** Das Internal `VERSION` zeigt die Modulversion. Die vom Wattpilot gemeldete Firmware steht separat im Reading `firmwareVersion`.

### Beispiel

Geben Sie dies in die FHEM Kommandozeile ein:

```text
define testWallbox Wattpilot 192.0.2.10
set testWallbox password nur-ein-dokumentationswert
```

## 4. Funktionen & Befehle (Steuerung)

Nach der Definition muss zuerst das Passwort gesetzt werden:

```text
set wallbox password <DeinPasswort>
```

Das Passwort wird ausschließlich unter stabilen FUUID-basierten Schlüsseln gespeichert. Rename, Reload, `rereadcfg`, Disable und normales Undefine erhalten diese Werte. Nur das tatsächliche Löschen des FHEM-Geräts entfernt die beiden eigenen stabilen Credential-Schlüssel. Passwortänderung und Löschung arbeiten transaktional und melden auch einen unvollständigen Rollback ausdrücklich.

Sobald `state` den Wert `connected` hat, stehen folgende Befehle zur Verfügung:

### Ladestrom setzen

```text
set wallbox chargingCurrent 16
```

Akzeptiert werden ausschließlich ganze Werte ab 6 A. Sobald das Gerät einen nutzbaren Wert in `configMaximumCurrentLimit` bestätigt hat, gilt dieser als dynamische Obergrenze bis maximal 32 A; FHEMWEB passt den Slider entsprechend an. Vor der ersten Bestätigung sowie bei einem fehlenden oder unbrauchbaren Reading bleibt aus Kompatibilitätsgründen der Bereich 6 bis 32 A aktiv. Intern wird `amp` gesendet. Das Reading `configChargingCurrent` wird erst durch eine Geräteantwort aktualisiert.

### Force-State setzen

```text
set wallbox forceState neutral
set wallbox forceState off
set wallbox forceState on
```

Die Abbildung lautet `neutral -> frc=0`, `off -> frc=1`, `on -> frc=2`.

### Lademodus setzen

```text
set wallbox chargingMode default
set wallbox chargingMode eco
set wallbox chargingMode nextTrip
```

Die Abbildung lautet `default -> lmo=3`, `eco -> lmo=4`, `nextTrip -> lmo=5`.

### PV-Überschuss-Startleistung setzen

```text
set wallbox pvSurplusStartPower 1400
```

Der nicht negative, endliche Zahlenwert wird in Watt über `fst` gesendet; das bestätigte Reading wird mit genau zwei Nachkommastellen ausgegeben. Das Modul setzt keine unbelegte Obergrenze. Ein Gerätefehler wird über `lastCommandStatus` und `lastCommandError` gemeldet; das Reading wird erst durch einen vom Gerät bestätigten Statuswert aktualisiert. Lesen, Schreiben, Geräte-Rückmeldung und Wiederherstellung des Ausgangswerts wurden mit FHEM und einem Wattpilot Flex mit Firmware 43.4 erfolgreich geprüft.

### PV- und Netzregelung

```text
set wallbox pvSurplusEnabled 1
set wallbox zeroFeedInEnabled 0
set wallbox pvControlPreference preferFromGrid
```

Die Befehle schreiben `fup`, `fzf` und `frm`. `pvControlPreference` akzeptiert `preferFromGrid`, `default` und `preferToGrid`, entsprechend den Protokollwerten `0`, `1` und `2`.

### Phasenumschaltung

```text
set wallbox phaseSwitch mode auto
set wallbox phaseSwitch threePhasePower 5200
set wallbox phaseSwitch delay 120
set wallbox phaseSwitch minInterval 600
```

Der gruppierte Befehl `phaseSwitch` schreibt `psm` mit `auto=0`, `force1=1` oder `force3=2`, rechnet `delay` für `mpwst` und `minInterval` für `mptwt` um und schreibt `threePhasePower` über `spl3`. Die beiden Zeitwerte werden öffentlich in Sekunden angegeben und als exakte ganze Millisekunden übertragen. Die Leistungsschwelle wird in Watt angegeben; das bestätigte Reading wird mit genau zwei Nachkommastellen ausgegeben.

### Lade- und Pausenverhalten

```text
set wallbox minimumCharging duration 300
set wallbox chargingPauseAllowed 1
set wallbox minimumCharging pauseDuration 120
set wallbox minimumCharging interval 0
```

Der gruppierte Befehl `minimumCharging` rechnet die öffentlichen Sekunden exakt in ganze Millisekunden um und schreibt `duration` über `fmt`, `pauseDuration` über `mcpd` und `interval` über `mci`. `chargingPauseAllowed` bleibt ein separater Befehl und schreibt das boolesche Feld `fap`. Die Einstellung `minimumCharging interval` folgt dem gepinnten API-Alias für `mci`; die aktuelle Fronius-Flex-Bedienungsanleitung nennt die Fahrzeugeinstellung „Forced charging interval“ beziehungsweise Zwangsladeintervall.

Diese zusätzlichen Setter verwenden den bestehenden gesicherten `setValue`-Pfad. Es wird kein Reading optimistisch geändert; nur eine Geräteantwort oder ein späterer Status bestätigt den Wert. Die Feldzuordnungen beruhen auf der im Projekt dokumentierten Kombination aus aktueller Fronius-Bedienungsdokumentation, gepinnten API-Quellen und der bereinigten Flex-43.4-Beobachtung. Die hier beschriebenen erweiterten Energie- und Phasenparameter wurden mit einem Wattpilot Flex Home 22 C6, Firmware 43.4, einzeln geändert, per Geräte-Rückmeldung bestätigt und auf den Ausgangswert zurückgesetzt.

### PV-Speicher-Diagnose

Die Felder `fbuf_akkuSOC` und `fbuf_pAkku` werden nur mit `diagnosticReadings=1` als rohe Readings `diag_fbuf_akkuSOC` und `diag_fbuf_pAkku` veröffentlicht. Sie gehören zum gemeinsamen Diagnose-Owner; numerische Werte werden ohne Skalierung auf genau zwei Nachkommastellen gerundet, ohne eine Einheit oder Vorzeichenbedeutung zu behaupten. `diag_fbuf_pAkku` und `diag_pvopt_averagePAkku` stammen aus zwei verschiedenen Protokollfeldern; ihre genaue Abgrenzung, Aggregation und Vorzeichenkonvention ist weiterhin nicht belegt. `pvBatteryModeCode` aus `fbuf_akkuMode` bleibt dagegen ein normaler diskreter Status und wird sofort nur bei tatsächlicher Änderung veröffentlicht. Für diese Werte gibt es bewusst keine Setter und keine erfundene Modus-Enum.

Das Modul bildet außerdem die gleichzeitig in App und `fullStatus` beobachteten PV-Speichereinstellungen ab: `fam` als `configPvBatteryChargeAboveSoC`, `pdte` als `configPvBatteryDischargeEnabled`, `pdt` als `configPvBatteryDischargeUntilSoC`, `pdle` als `configPvBatteryDischargeTimeLimitEnabled`, `pdls` als `configPvBatteryDischargeStartTime` und `pdlo` als `configPvBatteryDischargeStopTime`. Die beiden Zeitwerte werden aus ganzen Sekunden seit Mitternacht als `HH:MM` dargestellt. Die Zuordnung ist für Wattpilot Flex Home 22 C6 mit Firmware 43.4 durch die exakt übereinstimmenden App-Werte und den zeitgleichen Status belegt.

Für diese Einstellungen steht ein gruppierter Top-Level-Setter bereit:

```text
set wallbox pvBattery chargeAboveSoC 60
set wallbox pvBattery dischargeEnabled 1
set wallbox pvBattery dischargeUntilSoC 57
set wallbox pvBattery dischargeTimeLimitEnabled 1
set wallbox pvBattery dischargeStartTime 07:00
set wallbox pvBattery dischargeStopTime 20:00
```

`chargeAboveSoC` und `dischargeUntilSoC` akzeptieren ganze Werte von `0` bis `100`. Die beiden Schalter akzeptieren `0` oder `1` und werden als JSON-Boolean gesendet. `dischargeStartTime` akzeptiert `00:00` bis `23:59`; `dischargeStopTime` zusätzlich `24:00`. Intern werden die Zeiten als Sekunden seit Mitternacht über `pdls` beziehungsweise `pdlo` übertragen. Es wird kein Reading optimistisch geändert; nur eine Geräteantwort oder ein späterer Status bestätigt den Wert. Alle sechs Setter wurden auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 einzeln geändert, durch den geräteseitigen Status/Readback bestätigt und auf ihre Ausgangswerte zurückgesetzt. Bewusste Geräteablehnung, Persistenz über einen Neustart und weitere Firmware-/Modellstände sind nicht verifiziert.

### Verbindung kontrolliert neu aufbauen

```text
set wallbox reconnect
```

Der Befehl trennt die lokale WebSocket-Sitzung, verwirft sitzungsgebundene Timer, Authentifizierungs- und Teil-JSON-Zustände und startet genau einen neuen Verbindungs-/Anmeldezyklus. Vorhandene Betriebsreadings und Konfiguration bleiben erhalten. Ausstehende gesicherte Befehle werden mit `lastCommandStatus=failed` und `lastCommandError=reconnect requested` beendet. Dasselbe terminale Diagnoseprinzip gilt bei Sitzungsverlust, Deaktivierung, Credential-Änderung, Authentifizierungsabbruch und Lifecycle-Timeout; Undefine und Shutdown räumen intern auf, ohne neue Reading-Events zu erzeugen. In der FHEMWEB-Set-Liste wird `reconnect:noArg` verwendet, damit kein unnötiges Wertefeld erscheint. Dies ist ausdrücklich **kein** belegter `fullStatus`-Request; ein nach der Anmeldung eingehender Initialstatus wird weiterhin vom Gerät gesendet.

### Next-Trip-Zeit setzen

```text
set wallbox nextTripTime 07:30
```

Das Format muss exakt `HH:MM` sein. Eine einstellige Stunde wie `7:30` wird abgewiesen. Intern wird der Wert als Sekunden nach Mitternacht über `ftt` gesendet.

## 5. Konfiguration (Attribute)

Sie können das Verhalten des Moduls über "Attribute" anpassen.

### `interval` (in Sekunden)

Legt fest, wie oft Intervallreadings veröffentlicht werden: `energyTotal`, `energySincePlugIn`, `deviceRebootCount`, `uptime`, die aus `nrg` abgeleiteten Spannungs-, Strom- und Leistungsreadings sowie aktivierte `diag_...`-Readings.

* Standard: `0` (kein Rate-Limit).
* Empfehlung: `10` oder `60`.
* Energie, elektrische `nrg`-Telemetrie, Gerätegesundheit, `uptime` und optionale Diagnosen besitzen getrennte Latest-Value-Caches und Dirty-Felder, verwenden aber einen gemeinsamen Intervalltakt. Ein Tick veröffentlicht alle zulässigen geänderten Gruppen in derselben FHEM-Reading-Transaktion und mit demselben Zeitstempel. Keine Gruppe kann eine andere blockieren oder deren Reading-Zeitstempel mit alten Cachewerten erneuern.
* Innerhalb des Intervalls wird je Gruppe nur der neueste gültige Stand gepuffert. Energie wird nur dirty, wenn sich der formatierte öffentliche Wert tatsächlich ändert; identische `eto`-/`wh`-Werte erneuern weder Zeitstempel noch Events. Fehlende, `null`-, typfalsche oder unvollständige Werte werden nicht dirty und verschieben den gemeinsamen Takt nicht.
* Alle 24 `config...`-Readings bleiben nach gültiger Gerätebestätigung sofort. Identitätsreadings, `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `pvBatteryModeCode`, die vier Ladeentscheidungsreadings und `errorCode` werden sofort, aber nur bei tatsächlicher Wertänderung veröffentlicht.
* `fullStatus`, partielles `fullStatus`, `deltaStatus` und zugeordnete Response-`status` verwenden dieselbe Policy. Der erste gültige authentifizierte `fullStatus`- oder `deltaStatus`-Input beendet die Initialisierung; `partial=true` beschreibt nur die Unvollständigkeit des Snapshots. `interval=0` deaktiviert die Rate-Limits. Wird ein positiver Wert auf `0` geändert oder das Attribut gelöscht, werden bereits gepufferte, aktuell zulässige Dirty-Gruppen sofort gemeinsam veröffentlicht.
* `deltaStatus` liefert nur die vom Gerät mitgesendeten Felder und dient damit als geräteseitige Änderungsfilterung. Daraus wird keine offiziell definierte Aktualisierungsfrequenz einzelner Flex-Felder abgeleitet; eine öffentliche Fronius-Spezifikation dafür ist nicht belegt.

### `update_while_idle` (0 oder 1)

Steuert die elektrische `nrg`-Telemetrie, `uptime` und aktivierte `diag_...`-Readings, wenn das Auto **nicht** lädt.

* `0` (Standard): Die gegateten Owner bleiben im Idle-Zustand passiv, **außer** für den begrenzten einmaligen Charging-zu-Idle-Refresh von `nrg`.
* `1`: Echte eingehende Idle-Werte von `nrg`, `uptime` und aktivierten Diagnosen werden zusätzlich im gemeinsamen Telemetrietakt verarbeitet.
* Bei beiden Attributwerten darf beim Wechsel von `car=2` zu einem gültigen nicht ladenden Zustand ein echtes `nrg` in derselben Nachricht oder innerhalb von 30 Sekunden den Takt einmalig umgehen, damit ausschließlich vom Gerät gelieferte Werte veraltete Readings korrigieren. Eine Änderung des Attributs während dieser Episode erzeugt weder einen zweiten Timer noch bricht sie den bestehenden Refresh ab.
* Es gibt keinen belegten expliziten Wattpilot-WebSocket-Status-Request; das Modul sendet deshalb kein `getAllValues` und erfindet kein Polling-Kommando. Fehlt im 30-Sekunden-Fenster ein gültiges `nrg`, wird höchstens ein kontrollierter Reconnect für diese Idle-Episode geplant. Danach bleiben bei `0` weitere gewöhnliche Idle-Werte passiv.
* Fehlende Werte werden niemals als null interpretiert. Echte Nullwerte werden nur verarbeitet, wenn das Gerät sie gültig liefert.
* Das Attribut steuert Energie nicht. `energyTotal` und `energySincePlugIn` werden nur bei einem tatsächlich geänderten formatierten Wert für den gemeinsamen Takt vorgemerkt; identische Statuswerte bleiben ohne Timestamp- oder Event-Update. Das Repository behauptet nicht, in welchem Zustand oder mit welcher Frequenz der Wattpilot `eto`/`wh` sendet. Diskrete Status-/Diagnosewerte bleiben sofort-bei-Änderung aktiv. `pvBatteryModeCode` ist ein solcher diskreter Statuswert und gehört nicht zum Batterie-Rate-Limit.

### `diagnosticReadings` (0 oder 1)

Steuert die vierzehn optionalen Rohreadings zur Felderkundung, deren Namen mit `diag_` beginnen.

* `0` (Standard): Diagnosefelder werden weder ausgewertet noch gepuffert. Vorhandene `diag_...`-Readings werden sofort gelöscht und ihr Cache-/Dirty-Zustand verworfen. Das Löschen des Attributs wirkt genauso.
* `1`: Gültige skalare Werte der vierzehn ausgewählten Protokollfelder werden über den normalen `interval`-Mechanismus veröffentlicht. Sie sind beim Laden oder mit `update_while_idle=1` zulässig.
* Nach dem Präfix `diag_` bleibt die Protokollschreibweise exakt erhalten. JSON-Zahlen werden ohne Skalierung oder Umrechnung auf genau zwei Nachkommastellen gerundet; Strings bleiben unverändert und JSON-Booleans erscheinen als `0` oder `1`. Daraus werden weiterhin keine Einheit, Bedeutung oder Vorzeichenkonvention abgeleitet. Fehlende Felder, `null`, Objekte, Arrays und ungültige Werte lassen das bisherige Reading unverändert.

### `disable` (0 oder 1)

Deaktiviert das Modul komplett.

* `0` (Standard): Modul ist aktiv und verbindet sich.
* `1`: Modul wird deaktiviert, die Verbindung getrennt und keine neuen Verbindungsversuche unternommen. Nützlich bei Wartungsarbeiten.

### `verbose` (0 bis 5)

Steuert die Ausführlichkeit der Log-Einträge im FHEM Logfile.

* `1`: Nur Fehler.
* `2`: Wichtige Ereignisse (z.B. Login erfolgreich).
* `3`: Protokolliert gesendete Befehle.
* `4`: Protokolliert empfangene Daten vom Wattpilot.
* `5`: Debugging. Vollständige JSON-Nachrichten bleiben ohne `rawJsonLog=1` unterdrückt.

### `rawJsonLog` (0 oder 1)

Standard ist `0`. Vollständige ein- und ausgehende JSON-Nachrichten werden ausschließlich protokolliert, wenn gleichzeitig `rawJsonLog=1` und `verbose=5` gesetzt sind. Das umfasst Authentifizierungs- und `securedMsg`-Frames. Beim Aktivieren wird eine Sicherheitswarnung ausgegeben: Diese Rohdaten können Authentifizierungs-, Netzwerk-, Geräte- und Betriebsdaten enthalten. Nur kurzzeitig zur gezielten Diagnose aktivieren und Rohdaten niemals unbereinigt weitergeben.

Das Modul verwendet für ausgehende JSON-Nachrichten einen zentralen Schreibpfad. Dieser unterdrückt den DevIo-eigenen Level-5-Payload-Logeintrag nur während des synchronen Schreibaufrufs, ohne das FHEM-Attribut `verbose` dauerhaft oder global zu verändern. `DevIo_SimpleWrite(..., 2)` erhält dabei ungepackten Text; den WebSocket-Opcode bestimmt DevIo anhand seiner Verbindung und von `$hash->{binary}`. Ein vollständiger Klartext-Logeintrag aus dem Wattpilot-Modul entsteht ausschließlich über den oben beschriebenen Raw-Modus.

Technische Grenze: In der geprüften FHEM-Revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b` maskiert DevIo `privacy=1` nur die initiale Öffnungszeile. Für WebSockets erzeugt `DevIo_OpenDev` intern einen neuen HttpUtils-Hash ohne `hideurl` und ohne übernommenes `devioLoglevel`; HttpUtils kann URL, DNS/IP, Timeout- und Verbindungsfehler auf Level 4 oder 5 protokollieren. Wattpilot bewahrt die korrekte DevIo-Bedeutung von Initialverbindung (`reopen=0`) und Reconnect (`reopen=1`) und redigiert seine eigenen Meldungen. Ein normales EOF bleibt im DevIo-ReadyFn-Pfad; ein WebSocket-Close-Frame, bei dem `DevIo_DecodeWS` den ReadyFn-/`NEXT_OPEN`-Eigentümer entfernt, erhält genau einen modulverwalteten Reconnect. Ohne tatsächlich geöffneten Transport beginnt keine Authentifizierung. Die transitiven Core-Logs kann das Modul über die öffentliche DevIo-Schnittstelle dennoch nicht zuverlässig verhindern. Eine belastbare Vollunterdrückung erfordert eine FHEM-Core-Erweiterung, die `privacy` an HttpUtils als `hideurl` und ein geeignetes Log-/Fehler-Redaktionsverhalten weiterreicht. Bis dahin dürfen Logs bei hohem `verbose` nicht als endpointfrei betrachtet werden und müssen entsprechend geschützt und vor Weitergabe bereinigt werden.

`DevIo_DecodeWS` puffert auf dieser Revision unvollständige rohe WebSocket-Frames selbst in `.WSBUF`, wertet das `FIN`-Bit aber nicht als logische Nachrichtenbegrenzung aus. Wattpilot führt deshalb keinen zweiten Rohframe-Puffer, sondern nur einen separaten, auf insgesamt 1 MiB begrenzten JSON-Fortsetzungspuffer. Es verarbeitet mehrere vollständige, direkt verkettete JSON-Werte strukturell, wartet bei einem syntaktisch unvollständigen Top-Level-Objekt auf die nächste decodierte Nutzlast und lehnt fehlerhafte oder übergroße Folgen atomar ab. Statusnachrichten benötigen ein Objekt; bekannte skalare Felder und die ersten zwölf `nrg`-Elemente werden vor der Verwendung typgeprüft. Ausgelassene `deltaStatus`-Felder bleiben unverändert.

### `authHash` (auto, pbkdf2, bcrypt)

Wählt das Verfahren für die gerätespezifische Passwort-Hash-Ableitung.

* `auto` (Standard und Empfehlung): Verwendet das vom Gerät ausdrücklich angekündigte Verfahren. Nur beim belegten Legacy-Profil `devicetype=wattpilot` mit `hello.protocol=2` darf `authRequired.hash` fehlen; dann wird PBKDF2 gewählt. Wattpilot Flex wird ausschließlich mit bcrypt unterstützt. Ein unbekanntes Verfahren oder eine fehlende Angabe außerhalb des Legacy-Profils wird abgelehnt.
* `pbkdf2`: Erzwingt PBKDF2. Dies ist ausschließlich für das belegte Legacy-Wattpilot-Profil vorgesehen und kein unterstütztes Flex-Verfahren.
* `bcrypt`: Erzwingt bcrypt. Dieses Verfahren ist für Wattpilot Flex zwingend.

Im Normalbetrieb sollte `auto` verwendet werden. Für Wattpilot Flex muss `Crypt::Bcrypt` installiert sein. Eine manuelle Vorgabe ist vor allem für gezielte Diagnose oder ausdrücklich belegte Sonderfälle gedacht.

## 6. Readings (Messwerte)

Das Modul stellt exakt folgende 73 öffentlichen Readings bereit:

| Reading | Beschreibung |
| :--- | :--- |
| `state` | Lifecycle-Zustand: `disabled`, `passwordMissing`, `credentialError`, `connecting`, `authenticating`, `initializing`, `connected`, `disconnected`, `connectionFailed`, `authFailed`, `authTimeout`, `initializationTimeout`, `authSequenceInvalid`, `authConfigMissing`, `authChallengeInvalid`, `authHashUnsupported`, `authHashFailed`, `authHashStoreFailed` oder `authNonceFailed`. |
| `firmwareVersion` | Firmware-/Versionsstring aus der `hello`-Nachricht des Geräts. Identische Reconnect-Werte erneuern das Reading nicht. |
| `deviceType` | Exakter String aus dem Statusfeld `typ`. |
| `deviceModel` | Exakter vom Gerät gemeldeter Modell-/Gruppenstring aus `grp`; keine erfundene Modellzuordnung. |
| `deviceSubType` | Exakter Subtyp-String aus `styp`. |
| `deviceVariant` | Unveränderter nicht negativer Ganzzahlwert aus `var`. |
| `helloProtocol` | Unveränderter Ganzzahlwert aus `hello.protocol`. |
| `statusProtocol` | Unveränderter Ganzzahlwert aus `status.proto`; keine angenommene Beziehung zu `helloProtocol`. |
| `authHashMode` | Tatsächlich verwendetes Verfahren: `pbkdf2` oder `bcrypt`. |
| `carState` | `unknown`, `idle`, `charging`, `waitingForCar`, `complete`, `error` oder `unknown:<Rohwert>`. |
| `configForceState` | `neutral`, `off`, `on` oder `unknown:<Rohwert>`. |
| `configChargingCurrent` | Konfigurierter/angeforderter Ladestrom; als Ampere interpretiert. |
| `configChargingMode` | `default`, `eco`, `nextTrip` oder `unknown:<Rohwert>`. |
| `chargingAllowed` | Boolesches Feld `alw`, ausgegeben als `0` oder `1`. Die Bedeutung als aktuelle Ladefreigabe stammt aus gepinnter Wattpilot-Drittquellenevidenz; der Flex-Mitschnitt bestätigt Feld und Typ. |
| `chargingDecisionCode` | Unveränderter Ganzzahlwert aus `modelStatus`. |
| `chargingDecision` | Klartextzuordnung zu `chargingDecisionCode`; unbekannte Codes erscheinen als `unknown:<Code>`. |
| `chargingDecisionInternalCode` | Unveränderter Ganzzahlwert aus `msi`. |
| `chargingDecisionInternal` | Klartextzuordnung zu `chargingDecisionInternalCode`; unbekannte Codes erscheinen als `unknown:<Code>`. |
| `errorCode` | Unveränderter Ganzzahlwert aus `err`; keine unbestätigte Fehler-Enum. |
| `configMaximumCurrentLimit` | Unveränderter Ganzzahlwert aus `ama`; als maximale Stromgrenze in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `temperatureCurrentLimit` | Unveränderter Ganzzahlwert aus `amt`; als temperaturbedingte Stromgrenze in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `configMinimumChargingCurrent` | Unveränderter Ganzzahlwert aus `mca`; als Mindestladestrom in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `configPvSurplusStartPower` | Nicht negativer, endlicher Zahlenwert aus `fst`, ausgegeben in Watt. Gepinnte go-e-API-Metadaten und Wattpilot-spezifische Evidenz beschreiben ihn als Startleistung für PV-Überschussladen und als schreibbar; Lesen und Schreiben wurden auf einem Flex 43.4 bestätigt. Dies ist keine offizielle Fronius-Flex-WebSocket-Spezifikation. |
| `configPvSurplusEnabled` | Boolesches Feld `fup`, ausgegeben als `0` oder `1`. |
| `configZeroFeedInEnabled` | Boolesches Feld `fzf`, ausgegeben als `0` oder `1`. |
| `configPvControlPreference` | `preferFromGrid`, `default`, `preferToGrid` oder `unknown:<Rohwert>` aus `frm`. |
| `configPhaseSwitchMode` | `auto`, `force1`, `force3` oder `unknown:<Rohwert>` aus `psm`. |
| `configThreePhaseSwitchPower` | Nicht negativer Zahlenwert aus `spl3`, ausgegeben in Watt. |
| `configPhaseSwitchDelay` | `mpwst` von Millisekunden in Sekunden umgerechnet. |
| `configMinimumPhaseSwitchInterval` | `mptwt` von Millisekunden in Sekunden umgerechnet. |
| `configMinimumChargeTime` | `fmt` von Millisekunden in Sekunden umgerechnet. |
| `configChargingPauseAllowed` | Boolesches Feld `fap`, ausgegeben als `0` oder `1`. |
| `configMinimumChargingPauseDuration` | `mcpd` von Millisekunden in Sekunden umgerechnet. |
| `configMinimumChargingInterval` | `mci` von Millisekunden in Sekunden umgerechnet. Der Name folgt dem API-Alias; die Fronius-Flex-Anleitung bezeichnet das Verhalten als Zwangsladeintervall. |
| `diag_fbuf_akkuSOC` | Optionaler Rohskalar aus `fbuf_akkuSOC`; keine Prozentgrenze, Einheit oder Skalierung wird behauptet. |
| `diag_fbuf_pAkku` | Optionaler Rohskalar aus `fbuf_pAkku`; Abgrenzung zu `diag_pvopt_averagePAkku`, Aggregation, Einheit und Vorzeichen bleiben unbestätigt. |
| `pvBatteryModeCode` | Unveränderter nicht negativer Ganzzahlcode aus `fbuf_akkuMode`. Mangels belastbarer Enum wird bewusst kein Klartextmodus erfunden. |
| `deviceRebootCount` | Unveränderter nicht negativer Ganzzahlwert aus `rbc`, im normalen Intervall ohne Idle-Sperre. Die genaue Protokollbedeutung ist unbestätigt. |
| `uptime` | Nicht negativer Wert aus `rbt`, aufgrund der Realgerätbeobachtung als Sekunden interpretiert und als kumulative Stunden und Minuten im Format `H:MM` ausgegeben. Restsekunden werden verworfen; Aktualisierung im normalen Intervall beim Laden oder mit `update_while_idle=1`. |
| `diag_fbuf_pGrid` | Optionaler Rohskalar aus `fbuf_pGrid`; keine Behauptung zu Bedeutung, Einheit oder Vorzeichen. |
| `diag_fbuf_pPv` | Optionaler Rohskalar aus `fbuf_pPv`; keine Behauptung zu Bedeutung oder Einheit. |
| `diag_pvopt_averagePGrid` | Optionaler Rohskalar aus `pvopt_averagePGrid`; Aggregation und Semantik unbekannt. |
| `diag_pvopt_averagePPv` | Optionaler Rohskalar aus `pvopt_averagePPv`; Aggregation und Semantik unbekannt. |
| `diag_pvopt_averagePAkku` | Optionaler Rohskalar aus `pvopt_averagePAkku`; Aggregation, Abgrenzung und Vorzeichen unbekannt. |
| `diag_pvopt_averagePOhmpilot` | Optionaler Rohskalar aus `pvopt_averagePOhmpilot`; Aggregation und Semantik unbekannt. |
| `diag_pvopt_deltaP` | Optionaler Rohskalar aus `pvopt_deltaP`; verglichene Größen und Einheit unbekannt. |
| `diag_pvopt_deltaA` | Optionaler Rohskalar aus `pvopt_deltaA`; verglichene Größen und Einheit unbekannt. |
| `diag_pvopt_specialCase` | Optionaler Rohcode aus `pvopt_specialCase`; keine Enum wird behauptet. |
| `diag_fbuf_pAcTotal` | Optionaler Rohskalar aus `fbuf_pAcTotal`; der aufbewahrte Mitschnitt enthält `null`, Typ und Semantik sind daher unbekannt. |
| `diag_fbuf_ohmpilotState` | Optionaler Rohskalar aus `fbuf_ohmpilotState`; der aufbewahrte Mitschnitt enthält `null`, Typ und Semantik sind daher unbekannt. |
| `diag_fbuf_ohmpilotTemperature` | Optionaler Rohskalar aus `fbuf_ohmpilotTemperature`; der aufbewahrte Mitschnitt enthält `null`, Typ, Einheit und Semantik sind daher unbekannt. |
| `configPvBatteryChargeAboveSoC` | App-Einstellung „Charge above“ aus `fam`, als gültiger Prozentwert von `0` bis `100`; schreibbar über `set <name> pvBattery chargeAboveSoC <0-100>`. |
| `configPvBatteryDischargeEnabled` | App-Schalter „Discharge until“ aus `pdte`, ausgegeben als `0` oder `1`; schreibbar über `set <name> pvBattery dischargeEnabled` mit `0` oder `1`. |
| `configPvBatteryDischargeUntilSoC` | Zugehörige App-Einstellung „State of charge SoC“ aus `pdt`, als gültiger Prozentwert von `0` bis `100`; schreibbar über `set <name> pvBattery dischargeUntilSoC <0-100>`. |
| `configPvBatteryDischargeTimeLimitEnabled` | App-Schalter „Limit discharging time“ aus `pdle`, ausgegeben als `0` oder `1`; schreibbar über `set <name> pvBattery dischargeTimeLimitEnabled` mit `0` oder `1`. |
| `configPvBatteryDischargeStartTime` | App-Startzeit aus `pdls`, von Sekunden seit Mitternacht nach `HH:MM` umgerechnet; schreibbar über `set <name> pvBattery dischargeStartTime <HH:MM>`. |
| `configPvBatteryDischargeStopTime` | App-Stoppzeit aus `pdlo`, von Sekunden seit Mitternacht nach `HH:MM` umgerechnet; schreibbar über `set <name> pvBattery dischargeStopTime` mit `HH:MM` oder `24:00`. |
| `configNextTripTime` | Protokollwert als `HH:MM`; als Sekunden nach Mitternacht interpretiert. |
| `energyTotal` | `eto / 1000`, mit zwei Nachkommastellen. Die Interpretation Wh nach kWh ist Implementierungswissen und durch den bereinigten Flex-Mitschnitt nicht bewiesen. |
| `energySincePlugIn` | `wh`, mit zwei Nachkommastellen; als Wh interpretiert. |
| `voltageL1`, `voltageL2`, `voltageL3` | `nrg[0..2]`, als Volt interpretiert. |
| `currentL1`, `currentL2`, `currentL3` | `nrg[4..6]`, als Ampere interpretiert. |
| `powerL1`, `powerL2`, `powerL3` | `nrg[7..9]`, als Watt interpretiert. |
| `power` | `nrg[11]`, als Gesamtleistung in Watt interpretiert. |
| `lastCommandRequestId` | Korrelations-ID des letzten gesicherten Befehls. |
| `lastCommandStatus` | `pending`, `success`, `failed` oder `timeout`. |
| `lastCommandError` | Kurzer redigierter Fehler- oder Ergebnistext. Sitzungsabbrüche verwenden stabile Gründe wie `connection lost`, `device disabled`, `credentials changed`, `authentication aborted`, `lifecycle timeout`, `reconnect requested`, `definition changed` oder `session replaced`. |

Alle 24 `config...`-Readings werden nach gültiger Gerätebestätigung sofort veröffentlicht. Identitätsreadings und die diskreten Status-/Diagnosewerte `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `pvBatteryModeCode`, `chargingDecisionCode`, `chargingDecision`, `chargingDecisionInternalCode`, `chargingDecisionInternal` und `errorCode` werden ebenfalls sofort, aber nur bei einer tatsächlichen Änderung veröffentlicht; identische Wiederholungen erneuern weder Zeitstempel noch Event. Energie-, elektrische `nrg`-, stationäre Speichertelemetrie, Gerätegesundheitswerte und aktivierte Rohdiagnosen sind durch `interval` begrenzt. Sie behalten getrennte Latest-Value-Caches und Dirty-Felder, werden aber über denselben Takt und dieselbe FHEM-Reading-Transaktion veröffentlicht. Energie wird nur bei einer tatsächlichen Änderung des formatierten öffentlichen Werts dirty. Fehlende, `null`-, typfalsche oder unvollständige Felder lassen Readings unverändert und verschieben den Takt nicht.

Die Klartextwerte verwenden eine Kompatibilitätszuordnung aus der gepinnten offiziellen go-e-Enum für `modelStatus`. Für `msi` wird dieselbe Wertetabelle verwendet, weil die gepinnte Wattpilot-spezifische Quelle das Feld als interne Entscheidungsvariante beschreibt. Dies ist keine offizielle Fronius-Flex-Spezifikation; deshalb bleiben beide Rohcodes erhalten und nicht zugeordnete Werte ausdrücklich sichtbar. Die genaue Beziehung, Auswertungsreihenfolge, Priorität und eine mögliche Rolle von `cpDisabledRequest` sind für Wattpilot Flex nicht bestätigt. Insbesondere behauptet das Modul weder, dass `modelStatus` zwingend die abschließende/wirksame Entscheidung ist, noch dass `msi` zwingend eine Entscheidung vor der CP-Ebene darstellt. Weichen die Werte voneinander ab, sind sie als zwei vom Gerät gelieferte Diagnosewerte zu behandeln; aus dieser Dokumentation darf keine Kausalkette abgeleitet werden.

**Hinweis zu aWATTar:** aWATTar ist ein Anbieter- beziehungsweise Tarifname für dynamische Strompreise und kein technisches Kürzel des Moduls. Die aus der go-e-Enum übernommenen Namen mit `Awattar` bezeichnen preisabhängige Ladeentscheidungen. `Fallback` bezeichnet dabei den Standardausgang eines Entscheidungszweigs, wenn kein speziellerer Ladegrund greift, und nicht automatisch einen technischen Fehler. Für den Wattpilot Flex sind der genaue Auslöser dieser Codes und ihre vollständige Semantik nicht bestätigt; insbesondere beweist ein Wert wie `notChargingBecauseFallbackAwattar` allein nicht, dass ein aWATTar-Tarif aktiviert ist.

| Code | Klartextwert |
| :--- | :--- |
| `0` | `notChargingBecauseNoChargeCtrlData` |
| `1` | `notChargingBecauseOvertemperature` |
| `2` | `notChargingBecauseAccessControlWait` |
| `3` | `chargingBecauseForceStateOn` |
| `4` | `notChargingBecauseForceStateOff` |
| `5` | `notChargingBecauseScheduler` |
| `6` | `notChargingBecauseEnergyLimit` |
| `7` | `chargingBecauseAwattarPriceLow` |
| `8` | `chargingBecauseAutomaticStopTestLadung` |
| `9` | `chargingBecauseAutomaticStopNotEnoughTime` |
| `10` | `chargingBecauseAutomaticStop` |
| `11` | `chargingBecauseAutomaticStopNoClock` |
| `12` | `chargingBecausePvSurplus` |
| `13` | `chargingBecauseFallbackGoEDefault` |
| `14` | `chargingBecauseFallbackGoEScheduler` |
| `15` | `chargingBecauseFallbackDefault` |
| `16` | `notChargingBecauseFallbackGoEAwattar` |
| `17` | `notChargingBecauseFallbackAwattar` |
| `18` | `notChargingBecauseFallbackAutomaticStop` |
| `19` | `chargingBecauseCarCompatibilityKeepAlive` |
| `20` | `chargingBecauseChargePauseNotAllowed` |
| `22` | `notChargingBecauseSimulateUnplugging` |
| `23` | `notChargingBecausePhaseSwitch` |
| `24` | `notChargingBecauseMinPauseDuration` |
| `26` | `notChargingBecauseError` |
| `27` | `notChargingBecauseLoadManagementDoesntWant` |
| `28` | `notChargingBecauseOcppDoesntWant` |
| `29` | `notChargingBecauseReconnectDelay` |
| `30` | `notChargingBecauseAdapterBlocking` |
| `31` | `notChargingBecauseUnderfrequencyControl` |
| `32` | `notChargingBecauseUnbalancedLoad` |
| `33` | `chargingBecauseDischargingPvBattery` |
| `34` | `notChargingBecauseGridMonitoring` |
| `35` | `notChargingBecauseOcppFallback` |

Die Bedeutungen und Einheiten der verwendeten `nrg`-Positionen sowie die Einheiten von `eto` und `wh` sind Implementierungs- beziehungsweise historische Interpretationen. Der dokumentierte Flex-Mitschnitt bestätigt Struktur und Datentypen, aber nicht unabhängig alle Einheiten, Enum-Bedeutungen oder Schreibrechte.

## 7. Fehlerbehebung

* **Status bleibt auf `disconnected`, `connecting`, `connectionFailed`, `authTimeout` oder `initializationTimeout`**:
  * Prüfen Sie die IP-Adresse. Kann der FHEM-Server die IP anpingen?
  * Sind FHEM und Wattpilot im gleichen Netzwerk? (Oft Probleme bei Gast-Netzwerken).
* **Log zeigt "Authentication Failed"**:
  * Prüfen Sie das Passwort mit `set <Name> password ...`.
  * Prüfen Sie die Gerätegeneration: Legacy-Wattpilot verwendet PBKDF2, Wattpilot Flex ausschließlich bcrypt. Eine manuelle Vorgabe sollte nur passend zur Gerätegeneration erfolgen.
* **Perl-Fehler im Log (`Can't locate Crypt/PBKDF2.pm`)**:
  * Die Voraussetzungen (Schritt 1) wurden nicht erfüllt. Installieren Sie das fehlende Perl-Modul nach.
