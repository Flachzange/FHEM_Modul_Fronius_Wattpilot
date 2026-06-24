# FHEM Modul: 72_Wattpilot.pm - Benutzerhandbuch

Dieses Dokument beschreibt die Installation und Einrichtung des Fronius Wattpilot Moduls für FHEM. Das Modul ermöglicht die Steuerung der Wallbox über das lokale Netzwerk via WebSocket.

Aktuelle Modulversion: **2.0.3**. Dennis Gramespacher bleibt ursprünglicher Autor. Die Neuentwicklung der Version 2.x stammt von Flachzange und entstand mit KI-Unterstützung durch OpenAI ChatGPT; technische Entscheidungen und Release-Verantwortung liegen bei Flachzange. Weitere Angaben stehen in [`AUTHORS.md`](AUTHORS.md). Die Herkunft und Belastbarkeit der verwendeten Protokollinformationen ist in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md) dokumentiert. Die vollständige bereinigte Beobachtung der Wattpilot-Flex-JSON-Struktur steht in [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md).

## Inkompatible Änderung in 2.0

Version 2.0 unterstützt ausschließlich eine frische Definition. Es gibt keine Aliase und keine automatische Migration der bisherigen Reading- oder Set-Namen. Alte Readings eines bestehenden Devices werden nicht automatisch gelöscht. DOIFs, Notifies, Plots, DbLog-/Influx-Abfragen, Dashboards und Skripte müssen manuell angepasst werden.

<!-- BEGIN 2.0 migration names -->

| Typ | 1.x | 2.0 |
| :--- | :--- | :--- |
| Reading | `state` | `state` |
| Reading | `version` | `firmwareVersion` |
| Reading | `authHashMode` | `authHashMode` |
| Reading | `CarState` | `carState` |
| Reading | `Laden_starten` | `forceState` |
| Reading | `Strom` | `chargingCurrent` |
| Reading | `Modus` | `chargingMode` |
| Reading | `Zeit_NextTrip` | `nextTripTime` |
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

### Next-Trip-Zeit setzen

```text
set wallbox nextTripTime 07:30
```

Das Format muss exakt `HH:MM` sein. Eine einstellige Stunde wie `7:30` wird abgewiesen. Intern wird der Wert als Sekunden nach Mitternacht über `ftt` gesendet.

## 5. Konfiguration (Attribute)

Sie können das Verhalten des Moduls über "Attribute" anpassen.

### `interval` (in Sekunden)

Legt fest, wie oft **hochfrequente Messwerte** (Spannung, Leistung, aktueller Strom) aktualisiert werden.

* Standard: `0` (Jede Änderung wird sofort angezeigt -> kann das Log füllen "Spam").
* Empfehlung: `10` oder `60`.
* *Hinweis:* Wichtige Änderungen (Ladevorgang startet, Auto angesteckt) werden immer **sofort** angezeigt, unabhängig vom Intervall.

### `update_while_idle` (0 oder 1)

Steuert, wie hochfrequente elektrische Messwerte verarbeitet werden, wenn das Auto **nicht** lädt.

* `0` (Standard): Idle-`nrg`-, Leistungs- und Stromwerte bleiben passiv und können weiter durch `interval` begrenzt oder übersprungen werden.
* `1`: Echte eingehende Idle-Werte werden verarbeitet, weiterhin unter Beachtung von `interval`. Beim Wechsel von `car=2` zu einem gültigen nicht ladenden Zustand darf ein echtes `nrg` in derselben Nachricht oder innerhalb von 30 Sekunden einmalig das Rate-Limit umgehen, damit vom Gerät gelieferte Nullwerte stale Readings korrigieren.
* Es gibt keinen belegten expliziten Wattpilot-WebSocket-Status-Request; das Modul sendet deshalb kein `getAllValues` und erfindet kein Polling-Kommando. Wenn in dem 30-Sekunden-Fenster kein gültiges `nrg` kommt, wird höchstens ein kontrollierter Reconnect für diese Idle-Episode geplant. Dieser Reconnect ist ein begrenzter, aus Drittquellen abgeleiteter Fallback und kein offizielles Fronius-Protokollfeature.
* Fehlende Werte werden niemals als null interpretiert. Echte Nullwerte werden nur verarbeitet, wenn das Gerät sie in einem gültigen `nrg` liefert.
* `energyTotal` und `energySincePlugIn` werden bei eingehenden `eto`-/`wh`-Feldern unabhängig von `interval` und `update_while_idle` aktualisiert. Das Idle-Gate betrifft nur die aus `nrg` abgeleiteten Spannungs-, Strom- und Leistungsreadings.

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

Das Modul stellt exakt folgende 30 öffentlichen Readings bereit:

| Reading | Beschreibung |
| :--- | :--- |
| `state` | Lifecycle-Zustand: `disabled`, `passwordMissing`, `credentialError`, `connecting`, `authenticating`, `initializing`, `connected`, `disconnected`, `connectionFailed`, `authFailed`, `authTimeout`, `initializationTimeout`, `authSequenceInvalid`, `authConfigMissing`, `authChallengeInvalid`, `authHashUnsupported`, `authHashFailed`, `authHashStoreFailed` oder `authNonceFailed`. |
| `firmwareVersion` | Firmware-/Versionsstring aus der `hello`-Nachricht des Geräts. |
| `authHashMode` | Tatsächlich verwendetes Verfahren: `pbkdf2` oder `bcrypt`. |
| `carState` | `unknown`, `idle`, `charging`, `waitingForCar`, `complete`, `error` oder `unknown:<Rohwert>`. |
| `forceState` | `neutral`, `off`, `on` oder `unknown:<Rohwert>`. |
| `chargingCurrent` | Konfigurierter/angeforderter Ladestrom; als Ampere interpretiert. |
| `chargingMode` | `default`, `eco`, `nextTrip` oder `unknown:<Rohwert>`. |
| `chargingAllowed` | Boolesches Feld `alw`, ausgegeben als `0` oder `1`. Die Bedeutung als aktuelle Ladefreigabe stammt aus gepinnter Wattpilot-Drittquellenevidenz; der Flex-Mitschnitt bestätigt Feld und Typ. |
| `chargingDecisionCode` | Unveränderter Ganzzahlwert aus `modelStatus`; keine unbestätigte Text-Enum. |
| `chargingDecisionInternalCode` | Unveränderter Ganzzahlwert aus `msi`; keine unbestätigte Text-Enum. |
| `errorCode` | Unveränderter Ganzzahlwert aus `err`; keine unbestätigte Fehler-Enum. |
| `maximumCurrentLimit` | Unveränderter Ganzzahlwert aus `ama`; als maximale Stromgrenze in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `temperatureCurrentLimit` | Unveränderter Ganzzahlwert aus `amt`; als temperaturbedingte Stromgrenze in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `minimumChargingCurrent` | Unveränderter Ganzzahlwert aus `mca`; als Mindestladestrom in Ampere nur aufgrund gepinnter Drittquellenevidenz interpretiert. |
| `nextTripTime` | Protokollwert als `HH:MM`; als Sekunden nach Mitternacht interpretiert. |
| `energyTotal` | `eto / 1000`, mit zwei Nachkommastellen. Die Interpretation Wh nach kWh ist Implementierungswissen und durch den bereinigten Flex-Mitschnitt nicht bewiesen. |
| `energySincePlugIn` | `wh`, mit zwei Nachkommastellen; als Wh interpretiert. |
| `voltageL1`, `voltageL2`, `voltageL3` | `nrg[0..2]`, als Volt interpretiert. |
| `currentL1`, `currentL2`, `currentL3` | `nrg[4..6]`, als Ampere interpretiert. |
| `powerL1`, `powerL2`, `powerL3` | `nrg[7..9]`, als Watt interpretiert. |
| `power` | `nrg[11]`, als Gesamtleistung in Watt interpretiert. |
| `lastCommandRequestId` | Korrelations-ID des letzten gesicherten Befehls. |
| `lastCommandStatus` | `pending`, `success`, `failed` oder `timeout`. |
| `lastCommandError` | Kurzer redigierter Fehler- oder Ergebnistext. |

Die sieben operativen Status-Readings werden bei jeder gültigen Geräteinformation sofort verarbeitet und unterliegen weder `interval` noch `update_while_idle`. Fehlende, `null`- oder typfalsche Felder lassen bestehende Werte unverändert.

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
