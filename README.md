# FHEM Modul: 72_Wattpilot.pm - Benutzerhandbuch

Dieses Dokument beschreibt die Installation und Einrichtung des Fronius Wattpilot Moduls für FHEM. Das Modul ermöglicht die Steuerung der Wallbox über das lokale Netzwerk via WebSocket.

Aktuelle Modulversion: **2.1.4**. Dennis Gramespacher bleibt ursprünglicher Autor. Die Neuentwicklung der Version 2.x stammt von Flachzange und entstand mit KI-Unterstützung durch OpenAI ChatGPT; technische Entscheidungen und Release-Verantwortung liegen bei Flachzange. Weitere Angaben stehen in [`AUTHORS.md`](AUTHORS.md). Die Herkunft und Belastbarkeit der verwendeten Protokollinformationen ist in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md) dokumentiert. Die vollständige bereinigte Beobachtung der Wattpilot-Flex-JSON-Struktur steht in [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md). Der vollständige Reading-Kategorien-Audit und das `config`-Namensschema stehen in [`docs/READING-CATEGORIES.md`](docs/READING-CATEGORIES.md).

## Inkompatible Änderung in 2.0

Version 2.0 unterstützt ausschließlich eine frische Definition. Es gibt keine Aliase und keine automatische Migration der bisherigen Reading- oder Set-Namen. Alte Readings eines bestehenden Devices werden nicht automatisch gelöscht. DOIFs, Notifies, Plots, DbLog-/Influx-Abfragen, Dashboards und Skripte müssen manuell angepasst werden.

Version 2.0.7 benennt zusätzlich jedes Konfigurationsreading auf das Schema `config...` um. Version 2.0.8 ergänzt sechs Konfigurationsreadings für die in der Solar.wattpilot-App sichtbaren PV-Speichereinstellungen. Version 2.0.9 kürzt den Ladezustand in öffentlichen Namen einheitlich als `SoC` ab, benennt `configPvBatteryDischargeEndTime` in `configPvBatteryDischargeStopTime` um und ergänzt den gruppierten Setter `pvBattery`. Version 2.0.10 weist `reconnect` in FHEMWEB als echten Befehl ohne Argument aus, liefert die reguläre Set-Liste auch bei `disable=1` und lehnt überzählige Argumente bei einwertigen Set-Befehlen strikt ab; tatsächliche Set-Befehle bleiben dabei gesperrt. Version 2.1.0 korrigiert `modify`/`defmod` als vollständigen Sitzungswechsel, erhält `fullStatus.partial` auf Nachrichtenebene, prüft eingehende JSON-Typen und Uhrzeiten strikt und entfernt die wirkungslosen Attribute `debug` und `defaultAmp`. Version 2.1.1 behält getrennte Latest-Value-Caches und Dirty-Felder für Energie-, elektrische und stationäre Speichertelemetrie, veröffentlicht alle zulässigen geänderten Gruppen aber über einen gemeinsamen Intervalltakt und eine FHEM-Reading-Transaktion. Energie wird nur bei einer tatsächlichen Änderung des formatierten öffentlichen Werts vorgemerkt; diskrete Status-/Diagnosewerte erscheinen nur bei tatsächlicher Änderung. Version 2.1.2 vereinheitlicht öffentliche Mess- und Rechenwerte auf genau zwei Nachkommastellen; Prozent-, Ganzzahl-, Zeit- und Dauerwerte bleiben bewusst dokumentierte Ausnahmen. Gerundetes negatives Null wird als positives Null ausgegeben. Version 2.1.3 führt die bereits vorhandenen Reading- und Set-Inventare zu kleinen deklarativen Status- und Command-Schemas zusammen. Gewöhnliche skalare Felder und Set-Befehle werden daraus validiert, formatiert beziehungsweise versendet; spezielle Lifecycle-, Authentifizierungs-, Telemetrie-, Car-Transition-, `password`-, `reconnect`- und gruppierte `pvBattery`-Logik bleibt ausdrücklich im Code sichtbar. Öffentliche Namen, Payloads und Taktung bleiben unverändert. Es gibt keine Kompatibilitätsreadings, Aliase, automatische Reading-Bereinigung oder DbLog-Migration. Version 2.1.4 ersetzt die sechs einzelnen Setter für Phasenumschaltung und Mindestladezeiten durch die gruppierten Befehle `phaseSwitch` und `minimumCharging`. Protokollschlüssel, Einheiten, Validierung und bestätigte `config...`-Readings bleiben unverändert; für die entfernten einzelnen Set-Namen gibt es keine Aliase. Nach einem Reload können alte Reading-Einträge eines bestehenden Devices als nicht mehr aktualisierte Werte erhalten bleiben; Verbraucher und gegebenenfalls diese Einträge müssen manuell angepasst beziehungsweise entfernt werden.

| Reading bis 2.0.6 | Reading ab 2.0.7 |
| :--- | :--- |
| `forceState` | `configForceState` |
| `chargingCurrent` | `configChargingCurrent` |
| `chargingMode` | `configChargingMode` |
| `maximumCurrentLimit` | `configMaximumCurrentLimit` |
| `minimumChargingCurrent` | `configMinimumChargingCurrent` |
| `pvSurplusStartPower` | `configPvSurplusStartPower` |
| `pvSurplusEnabled` | `configPvSurplusEnabled` |
| `zeroFeedInEnabled` | `configZeroFeedInEnabled` |
| `pvControlPreference` | `configPvControlPreference` |
| `phaseSwitchMode` | `configPhaseSwitchMode` |
| `threePhaseSwitchPower` | `configThreePhaseSwitchPower` |
| `phaseSwitchDelay` | `configPhaseSwitchDelay` |
| `minimumPhaseSwitchInterval` | `configMinimumPhaseSwitchInterval` |
| `minimumChargeTime` | `configMinimumChargeTime` |
| `chargingPauseAllowed` | `configChargingPauseAllowed` |
| `minimumChargingPauseDuration` | `configMinimumChargingPauseDuration` |
| `minimumChargingInterval` | `configMinimumChargingInterval` |
| `nextTripTime` | `configNextTripTime` |

<!-- BEGIN 2.0 migration names -->

| Typ | 1.x | 2.0 |
| :--- | :--- | :--- |
| Reading | `state` | `state` |
| Reading | `version` | `firmwareVersion` |
| Reading | `authHashMode` | `authHashMode` |
| Reading | `CarState` | `carState` |
| Reading | `Laden_starten` | `configForceState` |
| Reading | `Strom` | `configChargingCurrent` |
| Reading | `Modus` | `configChargingMode` |
| Reading | `Zeit_NextTrip` | `configNextTripTime` |
| Reading | `EnergyTotal` | `energyTotal` |
| Reading | `Energie_seit_Anstecken` | `energySincePlugIn` |
| Reading | `Voltage_L1` | `voltageL1` |
| Reading | `Voltage_L2` | `voltageL2` |
| Reading | `Voltage_L3` | `voltageL3` |
| Reading | `Current_L1` | `currentL1` |
| Reading | `Current_L2` | `currentL2` |
| Reading | `Current_L3` | `currentL3` |
| Reading | `Power_L1` | `powerL1` |
| Reading | `Power_L2` | `powerL2` |
| Reading | `Power_L3` | `powerL3` |
| Reading | `power` | `power` |
| Reading | `lastCommandRequestId` | `lastCommandRequestId` |
| Reading | `lastCommandStatus` | `lastCommandStatus` |
| Reading | `lastCommandError` | `lastCommandError` |
| Set | `Password <secret>` | `password <secret>` |
| Set | `Strom <6..32>` | `chargingCurrent <6..32>` |
| Set | `Laden_starten Start|Stop` | `forceState neutral|off|on` |
| Set | `Modus Default|Eco|NextTrip` | `chargingMode default|eco|nextTrip` |
| Set | `Zeit_NextTrip HH:MM` | `nextTripTime HH:MM` |

<!-- END 2.0 migration names -->

## 1. Voraussetzungen (System & Perl Module)

Damit das Modul funktioniert, müssen auf dem Server (Raspberry Pi, PC, etc.), auf dem FHEM läuft, einige Perl-Zusatzmodule installiert sein. Das Modul nutzt modernere Verschlüsselung (PBKDF2), die nicht immer standardmäßig installiert ist.

### Benötigte Perl-Pakete

* `JSON`
* `Crypt::PBKDF2`
* `Crypt::URandom`
* `Crypt::Bcrypt`
* `Digest::SHA`
* `MIME::Base64`

### Installation der Pakete (Debian/Raspbian/Ubuntu)

Führen Sie folgende Befehle im Terminal aus:

```bash
sudo apt-get update
sudo apt-get install libjson-perl libdigest-sha-perl libmime-base64-perl
```

Für `Crypt::PBKDF2`, `Crypt::URandom` und `Crypt::Bcrypt` (oft nicht als apt-Paket verfügbar) nutzen Sie am besten cpanminus:

```bash
sudo apt-get install cpanminus
sudo cpanm Crypt::PBKDF2 Crypt::URandom Crypt::Bcrypt
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
* **[Seriennummer]** (Optional): Die Seriennummer der Box. Wenn weggelassen, versucht das Modul sie automatisch auszulesen.

**Hinweis:** Version 2.0 benötigt eine frische Definition. Das Passwort wird separat mit `set <Name> password <secret>` gesetzt.

**Versionsanzeige:** Das Internal `VERSION` zeigt die Modulversion. Die vom Wattpilot gemeldete Firmware steht separat im Reading `firmwareVersion`.

### Beispiel

Geben Sie dies in die FHEM Kommandozeile ein:

```text
define testWallbox Wattpilot 192.0.2.10 10000001
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

Akzeptiert werden ausschließlich ganze Werte von 6 bis 32. Intern wird `amp` gesendet.

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
set wallbox threePhaseSwitchPower 5200
set wallbox phaseSwitch delay 120
set wallbox phaseSwitch minInterval 600
```

Der gruppierte Befehl `phaseSwitch` schreibt `psm` mit `auto=0`, `force1=1` oder `force3=2`, rechnet `delay` für `mpwst` und `minInterval` für `mptwt` um. Die beiden Zeitwerte werden öffentlich in Sekunden angegeben und als exakte ganze Millisekunden übertragen. Die Leistungsschwelle bleibt ein separater Befehl `threePhaseSwitchPower` über `spl3`; das bestätigte Reading wird mit genau zwei Nachkommastellen ausgegeben.

### Lade- und Pausenverhalten

```text
set wallbox minimumCharging duration 300
set wallbox chargingPauseAllowed 1
set wallbox minimumCharging pauseDuration 120
set wallbox minimumCharging interval 0
```

Der gruppierte Befehl `minimumCharging` rechnet die öffentlichen Sekunden exakt in ganze Millisekunden um und schreibt `duration` über `fmt`, `pauseDuration` über `mcpd` und `interval` über `mci`. `chargingPauseAllowed` bleibt ein separater Befehl und schreibt das boolesche Feld `fap`. Die Einstellung `minimumCharging interval` folgt dem gepinnten API-Alias für `mci`; die aktuelle Fronius-Flex-Bedienungsanleitung nennt die Fahrzeugeinstellung „Forced charging interval“ beziehungsweise Zwangsladeintervall.

Diese zusätzlichen Setter verwenden den bestehenden gesicherten `setValue`-Pfad. Es wird kein Reading optimistisch geändert; nur eine Geräteantwort oder ein späterer Status bestätigt den Wert. Die Feldzuordnungen beruhen auf der im Projekt dokumentierten Kombination aus aktueller Fronius-Bedienungsdokumentation, gepinnten API-Quellen und der bereinigten Flex-43.4-Beobachtung. Alle elf Setter wurden mit einem Wattpilot Flex Home 22 C6, Firmware 43.4, einzeln geändert, per Geräte-Rückmeldung bestätigt und auf den Ausgangswert zurückgesetzt.

### PV-Speicher-Telemetrie

Die Readings `pvBatterySoC`, `pvBatteryPower` und `pvBatteryModeCode` beziehen sich ausschließlich auf den stationären PV-Speicher, nicht auf die Fahrzeugbatterie. Sie werden aus `fbuf_akkuSOC`, `fbuf_pAkku` und `fbuf_akkuMode` gelesen. `pvBatterySoC` und `pvBatteryPower` verwenden einen getrennten Latest-Value-Cache und Dirty-Felder, teilen aber den gemeinsamen Telemetrietakt mit `nrg` und Energie; ein Speichertelegramm veröffentlicht keine alten elektrischen Werte. `pvBatteryModeCode` ist ein diskreter Status und wird sofort nur bei tatsächlicher Änderung veröffentlicht. `pvBatterySoC` wird mit genau einer Nachkommastelle ausgegeben. Für diese drei Werte gibt es bewusst keine Setter; weder eine unbestätigte Modus-Enum noch eine unbestätigte Vorzeichenbedeutung wird erfunden.

Version 2.0.8 bildet außerdem die gleichzeitig in App und `fullStatus` beobachteten PV-Speichereinstellungen ab: `fam` als `configPvBatteryChargeAboveSoC`, `pdte` als `configPvBatteryDischargeEnabled`, `pdt` als `configPvBatteryDischargeUntilSoC`, `pdle` als `configPvBatteryDischargeTimeLimitEnabled`, `pdls` als `configPvBatteryDischargeStartTime` und `pdlo` als `configPvBatteryDischargeStopTime`. Die beiden Zeitwerte werden aus ganzen Sekunden seit Mitternacht als `HH:MM` dargestellt. Die Zuordnung ist für Wattpilot Flex Home 22 C6 mit Firmware 43.4 durch die exakt übereinstimmenden App-Werte und den zeitgleichen Status belegt.

Version 2.0.9 ergänzt dafür einen einzigen gruppierten Top-Level-Setter:

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

Der Befehl trennt die lokale WebSocket-Sitzung, verwirft sitzungsgebundene Timer, Authentifizierungs- und Teil-JSON-Zustände und startet genau einen neuen Verbindungs-/Anmeldezyklus. Vorhandene Betriebsreadings und Konfiguration bleiben erhalten. Ausstehende gesicherte Befehle werden mit `lastCommandStatus=failed` und `lastCommandError=reconnect requested` beendet. In der FHEMWEB-Set-Liste wird `reconnect:noArg` verwendet, damit kein unnötiges Wertefeld erscheint. Dies ist ausdrücklich **kein** belegter `fullStatus`-Request; ein nach der Anmeldung eingehender Initialstatus wird weiterhin vom Gerät gesendet.

### Next-Trip-Zeit setzen

```text
set wallbox nextTripTime 07:30
```

Das Format muss exakt `HH:MM` sein. Eine einstellige Stunde wie `7:30` wird abgewiesen. Intern wird der Wert als Sekunden nach Mitternacht über `ftt` gesendet.

## 5. Konfiguration (Attribute)

Sie können das Verhalten des Moduls über "Attribute" anpassen.

### `interval` (in Sekunden)

Legt fest, wie oft Telemetriereadings veröffentlicht werden: `energyTotal`, `energySincePlugIn`, `pvBatterySoC`, `pvBatteryPower` sowie die aus `nrg` abgeleiteten Spannungs-, Strom- und Leistungsreadings.

* Standard: `0` (kein Rate-Limit).
* Empfehlung: `10` oder `60`.
* Energie, elektrische `nrg`-Telemetrie und stationäre Speichertelemetrie besitzen getrennte Latest-Value-Caches und Dirty-Felder, verwenden aber einen gemeinsamen Intervalltakt. Ein Tick veröffentlicht alle zulässigen geänderten Gruppen in derselben FHEM-Reading-Transaktion und mit demselben Zeitstempel. Keine Gruppe kann eine andere blockieren oder deren Reading-Zeitstempel mit alten Cachewerten erneuern.
* Innerhalb des Intervalls wird je Gruppe nur der neueste gültige Stand gepuffert. Energie wird nur dirty, wenn sich der formatierte öffentliche Wert tatsächlich ändert; identische `eto`-/`wh`-Werte erneuern weder Zeitstempel noch Events. Fehlende, `null`-, typfalsche oder unvollständige Werte werden nicht dirty und verschieben den gemeinsamen Takt nicht.
* Alle 24 `config...`-Readings bleiben nach gültiger Gerätebestätigung sofort. `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `pvBatteryModeCode`, die vier Ladeentscheidungsreadings und `errorCode` werden sofort, aber nur bei tatsächlicher Wertänderung veröffentlicht.
* `fullStatus`, partielles `fullStatus`, `deltaStatus` und zugeordnete Response-`status` verwenden dieselbe Policy. `interval=0` deaktiviert die Rate-Limits.
* `deltaStatus` liefert nur die vom Gerät mitgesendeten Felder und dient damit als geräteseitige Änderungsfilterung. Daraus wird keine offiziell definierte Aktualisierungsfrequenz einzelner Flex-Felder abgeleitet; eine öffentliche Fronius-Spezifikation dafür ist nicht belegt.

### `update_while_idle` (0 oder 1)

Steuert ausschließlich die elektrische `nrg`-Telemetrie und `pvBatterySoC`/`pvBatteryPower`, wenn das Auto **nicht** lädt.

* `0` (Standard): Beide hochfrequenten Telemetriegruppen bleiben im Idle-Zustand passiv.
* `1`: Echte eingehende Idle-Werte von `nrg` und stationärem Speicher werden im gemeinsamen Telemetrietakt verarbeitet. Beim Wechsel von `car=2` zu einem gültigen nicht ladenden Zustand darf ein echtes `nrg` in derselben Nachricht oder innerhalb von 30 Sekunden den Takt einmalig umgehen, damit vom Gerät gelieferte Nullwerte veraltete Readings korrigieren.
* Es gibt keinen belegten expliziten Wattpilot-WebSocket-Status-Request; das Modul sendet deshalb kein `getAllValues` und erfindet kein Polling-Kommando. Fehlt im 30-Sekunden-Fenster ein gültiges `nrg`, wird höchstens ein kontrollierter Reconnect für diese Idle-Episode geplant.
* Fehlende Werte werden niemals als null interpretiert. Echte Nullwerte werden nur verarbeitet, wenn das Gerät sie gültig liefert.
* Das Attribut steuert Energie nicht. `energyTotal` und `energySincePlugIn` werden nur bei einem tatsächlich geänderten formatierten Wert für den gemeinsamen Takt vorgemerkt; identische Statuswerte bleiben ohne Timestamp- oder Event-Update. Das Repository behauptet nicht, in welchem Zustand oder mit welcher Frequenz der Wattpilot `eto`/`wh` sendet. Diskrete Status-/Diagnosewerte bleiben sofort-bei-Änderung aktiv. `pvBatteryModeCode` ist ein solcher diskreter Statuswert und gehört nicht zum Batterie-Rate-Limit.

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

Technische Grenze: In der geprüften FHEM-Revision `b2bc07a6ef698a5d836c9d5d5250600951b1638d` maskiert DevIo `privacy=1` nur die initiale Öffnungszeile. Für WebSockets erzeugt `DevIo_OpenDev` intern einen neuen HttpUtils-Hash ohne `hideurl` und ohne übernommenes `devioLoglevel`; HttpUtils kann URL, DNS/IP, Timeout- und Verbindungsfehler auf Level 4 oder 5 protokollieren. Wattpilot bewahrt die korrekte DevIo-Bedeutung von Initialverbindung (`reopen=0`) und Reconnect (`reopen=1`) und redigiert seine eigenen Meldungen, kann diese transitiven Core-Logs über die öffentliche DevIo-Schnittstelle aber nicht zuverlässig verhindern. Eine belastbare Vollunterdrückung erfordert eine FHEM-Core-Erweiterung, die `privacy` an HttpUtils als `hideurl` und ein geeignetes Log-/Fehler-Redaktionsverhalten weiterreicht. Bis dahin dürfen Logs bei hohem `verbose` nicht als endpointfrei betrachtet werden und müssen entsprechend geschützt und vor Weitergabe bereinigt werden.

`DevIo_DecodeWS` puffert auf dieser Revision unvollständige rohe WebSocket-Frames selbst in `.WSBUF`, wertet das `FIN`-Bit aber nicht als logische Nachrichtenbegrenzung aus. Wattpilot führt deshalb keinen zweiten Rohframe-Puffer, sondern nur einen separaten, auf insgesamt 1 MiB begrenzten JSON-Fortsetzungspuffer. Es verarbeitet mehrere vollständige, direkt verkettete JSON-Werte strukturell, wartet bei einem syntaktisch unvollständigen Top-Level-Objekt auf die nächste decodierte Nutzlast und lehnt fehlerhafte oder übergroße Folgen atomar ab. Statusnachrichten benötigen ein Objekt; bekannte skalare Felder und die ersten zwölf `nrg`-Elemente werden vor der Verwendung typgeprüft. Ausgelassene `deltaStatus`-Felder bleiben unverändert.

### `authHash` (auto, pbkdf2, bcrypt)

Wählt das Verfahren für die Passwort-Verschlüsselung.

* `auto` (Standard): Verwendet ausschließlich ausdrücklich angekündigtes `pbkdf2` oder `bcrypt`. Beim belegten Legacy-Profil `devicetype=wattpilot`, Protokoll 2, bleibt ein fehlendes `authRequired.hash` kompatibel und wählt PBKDF2. Ein ausdrücklich unbekanntes Verfahren oder ein fehlendes Verfahren außerhalb dieses Profils wird abgelehnt.
* `pbkdf2`: Erzwingt PBKDF2 (ältere Modelle).
* `bcrypt`: Erzwingt bcrypt (neuere Wattpilot Flex Modelle).

## 6. Readings (Messwerte)

Das Modul stellt exakt folgende 53 öffentlichen Readings bereit:

| Reading | Beschreibung |
| :--- | :--- |
| `state` | Lifecycle-Zustand: `disabled`, `passwordMissing`, `credentialError`, `connecting`, `authenticating`, `initializing`, `connected`, `disconnected`, `connectionFailed`, `authFailed`, `authTimeout`, `initializationTimeout`, `authSequenceInvalid`, `authConfigMissing`, `authChallengeInvalid`, `authHashUnsupported`, `authHashFailed`, `authHashStoreFailed` oder `authNonceFailed`. |
| `firmwareVersion` | Firmware-/Versionsstring aus der `hello`-Nachricht des Geräts. |
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
| `pvBatterySoC` | Ladezustand des stationären PV-Speichers aus `fbuf_akkuSOC`, als Prozentwert von `0` bis `100` mit genau einer Nachkommastelle. Fehlende oder ungültige Werte verändern das Reading nicht. |
| `pvBatteryPower` | Vorzeichenbehafteter Zahlenwert aus `fbuf_pAkku`, ausgegeben in Watt und grundsätzlich auf zwei Nachkommastellen formatiert. Die Vorzeichenrichtung für Laden und Entladen ist noch nicht durch einen kontrollierten Flex-Realtest bestätigt; das Modul deutet das Vorzeichen daher nicht um. |
| `pvBatteryModeCode` | Unveränderter nicht negativer Ganzzahlcode aus `fbuf_akkuMode`. Mangels belastbarer Enum wird bewusst kein Klartextmodus erfunden. |
| `configPvBatteryChargeAboveSoC` | App-Einstellung „Charge above“ aus `fam`, als gültiger Prozentwert von `0` bis `100`; schreibbar über `set <name> pvBattery chargeAboveSoC <0-100>`. |
| `configPvBatteryDischargeEnabled` | App-Schalter „Discharge until“ aus `pdte`, ausgegeben als `0` oder `1`; schreibbar über `set <name> pvBattery dischargeEnabled <0|1>`. |
| `configPvBatteryDischargeUntilSoC` | Zugehörige App-Einstellung „State of charge SoC“ aus `pdt`, als gültiger Prozentwert von `0` bis `100`; schreibbar über `set <name> pvBattery dischargeUntilSoC <0-100>`. |
| `configPvBatteryDischargeTimeLimitEnabled` | App-Schalter „Limit discharging time“ aus `pdle`, ausgegeben als `0` oder `1`; schreibbar über `set <name> pvBattery dischargeTimeLimitEnabled <0|1>`. |
| `configPvBatteryDischargeStartTime` | App-Startzeit aus `pdls`, von Sekunden seit Mitternacht nach `HH:MM` umgerechnet; schreibbar über `set <name> pvBattery dischargeStartTime <HH:MM>`. |
| `configPvBatteryDischargeStopTime` | App-Stoppzeit aus `pdlo`, von Sekunden seit Mitternacht nach `HH:MM` umgerechnet; schreibbar über `set <name> pvBattery dischargeStopTime <HH:MM|24:00>`. |
| `configNextTripTime` | Protokollwert als `HH:MM`; als Sekunden nach Mitternacht interpretiert. |
| `energyTotal` | `eto / 1000`, mit zwei Nachkommastellen. Die Interpretation Wh nach kWh ist Implementierungswissen und durch den bereinigten Flex-Mitschnitt nicht bewiesen. |
| `energySincePlugIn` | `wh`, mit zwei Nachkommastellen; als Wh interpretiert. |
| `voltageL1`, `voltageL2`, `voltageL3` | `nrg[0..2]`, als Volt interpretiert. |
| `currentL1`, `currentL2`, `currentL3` | `nrg[4..6]`, als Ampere interpretiert. |
| `powerL1`, `powerL2`, `powerL3` | `nrg[7..9]`, als Watt interpretiert. |
| `power` | `nrg[11]`, als Gesamtleistung in Watt interpretiert. |
| `lastCommandRequestId` | Korrelations-ID des letzten gesicherten Befehls. |
| `lastCommandStatus` | `pending`, `success`, `failed` oder `timeout`. |
| `lastCommandError` | Kurzer redigierter Fehler- oder Ergebnistext. |

Alle 24 `config...`-Readings werden nach gültiger Gerätebestätigung sofort veröffentlicht. Die diskreten Status-/Diagnosewerte `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `pvBatteryModeCode`, `chargingDecisionCode`, `chargingDecision`, `chargingDecisionInternalCode`, `chargingDecisionInternal` und `errorCode` werden ebenfalls sofort, aber nur bei einer tatsächlichen Änderung veröffentlicht; identische Wiederholungen erneuern weder Zeitstempel noch Event. Energie-, elektrische `nrg`- und stationäre Speichertelemetrie sind durch `interval` begrenzt. Sie behalten getrennte Latest-Value-Caches und Dirty-Felder, werden aber über denselben Takt und dieselbe FHEM-Reading-Transaktion veröffentlicht. Energie wird nur bei einer tatsächlichen Änderung des formatierten öffentlichen Werts dirty. Fehlende, `null`-, typfalsche oder unvollständige Felder lassen Readings unverändert und verschieben den Takt nicht.

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
  * Versuchen Sie ggf. das Attribut `authHash` fest auf `pbkdf2` oder `bcrypt` zu setzen.
* **Perl-Fehler im Log (`Can't locate Crypt/PBKDF2.pm`)**:
  * Die Voraussetzungen (Schritt 1) wurden nicht erfüllt. Installieren Sie das fehlende Perl-Modul nach.
