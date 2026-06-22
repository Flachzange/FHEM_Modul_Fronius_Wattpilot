# FHEM Modul: 72_Wattpilot.pm - Benutzerhandbuch

Dieses Dokument beschreibt die Installation und Einrichtung des Fronius Wattpilot Moduls für FHEM. Das Modul ermöglicht die Steuerung der Wallbox über das lokale Netzwerk via WebSocket.

Aktuelle Modulversion: **1.4.0**. Dennis Gramespacher bleibt ursprünglicher Autor; Flachzange pflegt dieses Repository. Die Herkunft und Belastbarkeit der verwendeten Protokollinformationen ist in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md) dokumentiert. Die vollständige bereinigte Beobachtung der Wattpilot-Flex-JSON-Struktur steht in [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md).

## 1. Voraussetzungen (System & Perl Module)

Damit das Modul funktioniert, müssen auf dem Server (Raspberry Pi, PC, etc.), auf dem FHEM läuft, einige Perl-Zusatzmodule installiert sein. Das Modul nutzt modernere Verschlüsselung (PBKDF2), die nicht immer standardmäßig installiert ist.

### Benötigte Perl-Pakete

* `JSON`
* `Crypt::PBKDF2`
* `Crypt::Bcrypt`
* `Digest::SHA`
* `MIME::Base64`

### Installation der Pakete (Debian/Raspbian/Ubuntu)

Führen Sie folgende Befehle im Terminal aus:

```bash
sudo apt-get update
sudo apt-get install libjson-perl libdigest-sha-perl libmime-base64-perl
```

Für `Crypt::PBKDF2` und `Crypt::Bcrypt` (oft nicht als apt-Paket verfügbar) nutzen Sie am besten cpanminus:

```bash
sudo apt-get install cpanminus
sudo cpanm Crypt::PBKDF2 Crypt::Bcrypt
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

**Hinweis:** Das Passwort wird nicht mehr in der Definition angegeben, sondern separat mit dem `set Password` Befehl gesetzt.

### Beispiel

Geben Sie dies in die FHEM Kommandozeile ein:

```text
define testWallbox Wattpilot 192.0.2.10 10000001
set testWallbox Password nur-ein-dokumentationswert
```

## 4. Funktionen & Befehle (Steuerung)

Sobald das Gerät definiert ist, müssen Sie zuerst das Passwort setzen:

### Passwort setzen

Speichert das Passwort persistent in FHEM (verschlüsselt in der FHEM-Datenbank, nicht in der `fhem.cfg`).

```text
set wallbox Password <DeinPasswort>
```

Danach verbindet sich das Modul automatisch. Sobald der Status `connected` ist, können Sie es steuern.

Das Passwort und der daraus abgeleitete Authentifizierungswert werden unter stabilen FUUID-basierten Schlüsseln gespeichert. Der Rename-Pfad berücksichtigt, dass FHEM den Namen bereits vor `RenameFn` ändert und dessen Rückgabe verwirft. Vor jeder Migration oder Bereinigung wird deshalb zuerst ein FUUID-basierter Pending-Verweis auf den früheren Namen gespeichert. Nur dieser persistente Verweis darf einen fehlenden Owner-Marker für dieselbe FUUID wiederherstellen; der aktuelle Gerätename allein begründet niemals Eigentum. Schlägt das Speichern des Pending-Verweises fehl, werden namensbasierte Altwerte weder gelesen noch beansprucht oder verschoben. Namensbasierte Werte ohne belastbaren Eigentumsnachweis bleiben unangetastet und können nach einem Update ein erneutes `set <name> Password <secret>` erfordern. Fremde oder nicht verifizierbare Ressourcen bleiben ebenfalls unangetastet. Ein vorhandener stabiler Zugangswert bleibt trotz eines solchen Bereinigungskonflikts nutzbar; der Konflikt wird protokolliert. `rereadcfg`, Reload, Disable und normales Undefine löschen keine Zugangsdaten; nur das tatsächliche Löschen des FHEM-Geräts entfernt eindeutig eigene Werte.

Beim Ändern des Passworts invalidiert das Modul zuerst alle bekannten stabilen und namensbasierten Passwort-Hashes. Danach speichert es das neue stabile Passwort und entfernt verbliebene Legacy-Passwörter. Schlägt ein Schritt fehl, werden bereits vorgenommene Änderungen aus zuvor gelesenen Werten zurückgerollt und FHEM erhält einen Fehlertext. `DeleteFn` liest vor Änderungen Snapshots aller stabilen, bekannten Legacy- und Pending-Metadatenwerte. Bei Lese- oder Löschfehlern bricht es ab und stellt bereits gelöschte Werte wieder her; auch ein unvollständiger Rollback wird ausdrücklich gemeldet, damit FHEM das Gerät nicht endgültig löscht. Nach dem realen FHEM-Ablauf `UndefFn` gefolgt von einer fehlgeschlagenen `DeleteFn` werden `defptr`, ein ehrlicher Status und – nur bei aktivem Gerät mit vorhandenem Passwort – genau ein Reconnect-Timer wiederhergestellt.

Credential-Lesezugriffe unterscheiden Wert vorhanden, Wert nicht vorhanden und Speicherfehler. Der Verbindungsaufbau in Define hängt ausschließlich von einem lesbaren Passwort ab; Migration oder Bereinigung des optionalen Passwort-Hashes erfolgt dort best effort und blockiert ein Gerät mit eigenem stabilem Passwort nicht. Nach der Verbindung erzeugt die Authentifizierung den aktuellen FUUID-basierten Hash neu. Sonstige relevante Speicher- oder Metadatenfehler werden in Define, Enable, Authentifizierung, gesicherten Befehlen und fehlgeschlagener Delete-Wiederherstellung als `credential error` behandelt und nicht als fehlendes Passwort ausgegeben.

### Ladung Starten / Stoppen

Startet oder stoppt den Ladevorgang manuell. `Start` sendet `frc=2`, `Stop` sendet `frc=1`; das Reading zeigt zusätzlich `Neutral` für `frc=0`. Befehle werden nur bei offener, authentifizierter Verbindung und vorhandenem Signaturschlüssel gesendet.

```text
set wallbox Laden_starten Start
set wallbox Laden_starten Stop
```

### Stromstärke ändern (Ampere)

Legt den Ladestrom in Ampere fest. Nur ganzzahlige Werte von 6 A bis 32 A werden akzeptiert; ungültige Werte werden vor dem Senden abgewiesen.

```text
set wallbox Strom 16
```

Tipp: In der FHEM Oberfläche erscheint hierfür oft ein Slider.

### Modus ändern

Wechselt den Betriebsmodus der Wallbox.

```text
set wallbox Modus Eco
set wallbox Modus NextTrip
set wallbox Modus Default
```

### Next Trip Zeit einstellen

Setzt die gewünschte Uhrzeit für den "Next Trip" Modus.

```text
set wallbox Zeit_NextTrip 07:30
```

Format: `hh:mm`

## 5. Konfiguration (Attribute)

Sie können das Verhalten des Moduls über "Attribute" anpassen.

### `interval` (in Sekunden)

Legt fest, wie oft **hochfrequente Messwerte** (Spannung, Leistung, aktueller Strom) aktualisiert werden.

* Standard: `0` (Jede Änderung wird sofort angezeigt -> kann das Log füllen "Spam").
* Empfehlung: `10` oder `60`.
* *Hinweis:* Wichtige Änderungen (Ladevorgang startet, Auto angesteckt) werden immer **sofort** angezeigt, unabhängig vom Intervall.

### `update_while_idle` (0 oder 1)

Steuert, ob Messwerte aktualisiert werden, wenn das Auto **nicht** lädt.

* `0` (Standard): Wenn nicht geladen wird, werden Spannung/Leistung nicht aktualisiert, um Systemlast zu sparen (da meistens eh 0).
* `1`: Aktualisiert Werte auch im Leerlauf (z.B. zur Fehlersuche oder um Netzspannung zu überwachen). Greift nur in Kombination mit dem `interval`.

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

Technische Grenze: In der geprüften FHEM-Revision `5354e001b55c323f457bd907434e46f284d9582c` maskiert DevIo `privacy=1` nur die initiale Öffnungszeile. Für WebSockets erzeugt `DevIo_OpenDev` intern einen neuen HttpUtils-Hash ohne `hideurl` und ohne übernommenes `devioLoglevel`; HttpUtils kann URL, DNS/IP, Timeout- und Verbindungsfehler auf Level 4 oder 5 protokollieren. Wattpilot bewahrt die korrekte DevIo-Bedeutung von Initialverbindung (`reopen=0`) und Reconnect (`reopen=1`) und redigiert seine eigenen Meldungen, kann diese transitiven Core-Logs über die öffentliche DevIo-Schnittstelle aber nicht zuverlässig verhindern. Eine belastbare Vollunterdrückung erfordert eine FHEM-Core-Erweiterung, die `privacy` an HttpUtils als `hideurl` und ein geeignetes Log-/Fehler-Redaktionsverhalten weiterreicht. Bis dahin dürfen Logs bei hohem `verbose` nicht als endpointfrei betrachtet werden und müssen entsprechend geschützt und vor Weitergabe bereinigt werden.

### `authHash` (auto, pbkdf2, bcrypt)

Wählt das Verfahren für die Passwort-Verschlüsselung.

* `auto` (Standard): Wählt automatisch das vom Gerät geforderte Verfahren.
* `pbkdf2`: Erzwingt PBKDF2 (ältere Modelle).
* `bcrypt`: Erzwingt bcrypt (neuere Wattpilot Flex Modelle).

## 6. Readings (Messwerte)

Das Modul stellt folgende Werte ("Readings") zur Verfügung:

| Reading | Beschreibung |
| :--- | :--- |
| `state` | Verbindungsstatus (initialized, connected, auth_failed, password missing, disabled). |
| `version` | Firmware-/Protokollversion des Geräts. |
| `authHashMode` | Verwendetes Authentifizierungsverfahren (pbkdf2 oder bcrypt). |
| `CarState` | Status des Autos (Idle, Charging, WaitCar, Complete). |
| `power` | Aktuelle Gesamtleistung in Watt. |
| `Power_L1..3` | Leistung auf den einzelnen Phasen in Watt. |
| `EnergyTotal` | Gesamter Energiezähler in kWh. |
| `Voltage_L1..3` | Spannung auf den 3 Phasen in Volt. |
| `Current_L1..3` | Strom auf den 3 Phasen in Ampere. |
| `Strom` | Die aktuell im Wattpilot eingestellte Stromgrenze (Ampere). |
| `Laden_starten` | Status der manuellen Ladesteuerung (Start/Stop). |
| `Modus` | Aktueller Lademodus (Eco/Default/NextTrip). |
| `Zeit_NextTrip` | Eingestellte Uhrzeit für Next Trip (Format hh:mm). |
| `Energie_seit_Anstecken` | Geladene Energie in Wh seit das Auto angesteckt wurde. |

## 7. Fehlerbehebung

* **Status bleibt auf `initialized` oder `disconnected`**:
  * Prüfen Sie die IP-Adresse. Kann der FHEM-Server die IP anpingen?
  * Sind FHEM und Wattpilot im gleichen Netzwerk? (Oft Probleme bei Gast-Netzwerken).
* **Log zeigt "Authentication Failed"**:
  * Prüfen Sie das Passwort mit `set <Name> Password ...`.
  * Versuchen Sie ggf. das Attribut `authHash` fest auf `pbkdf2` oder `bcrypt` zu setzen.
* **Perl-Fehler im Log (`Can't locate Crypt/PBKDF2.pm`)**:
  * Die Voraussetzungen (Schritt 1) wurden nicht erfüllt. Installieren Sie das fehlende Perl-Modul nach.
