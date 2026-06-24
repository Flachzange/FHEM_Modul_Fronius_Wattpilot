# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [v2.0.3] - 2026-06-24

### Laufzeitkorrekturen nach dem ersten Flex-Praxistest

- `energyTotal` und `energySincePlugIn` werden nicht mehr zusammen mit den hochfrequenten `nrg`-Messwerten durch `update_while_idle` beziehungsweise `interval` gesperrt. Bei vorhandenen `eto`-/`wh`-Feldern werden die Energiezähler immer aktualisiert; nur Spannung, Strom und Leistung bleiben im Idle-Zustand optional begrenzt.
- Das Device-Internal `VERSION` enthält die Modulversion `2.0.3`. Die vom Wattpilot gemeldete Firmware überschreibt dieses Internal nicht mehr und bleibt im Reading `firmwareVersion`. Frische Definitionen und bestehende Devices beim Modul-Reload werden berücksichtigt, ohne Verbindung, Timer, Credentials oder Readings neu zu initialisieren.
- Nicht unterstützte JSON-Nachrichtentypen werden weiterhin ohne Payload ignoriert. Ein kurzer, streng begrenzter ASCII-Typname wird nun tatsächlich im Log genannt; ungeeignete Typwerte erscheinen als `redacted`.

### Protokollabgrenzung und Tests

- Die Dokumentation unterscheidet ausdrücklich das beim Live-Test indirekt beobachtete `hello.protocol=2` vom im bereinigten `fullStatus` enthaltenen Feld `status.proto=4`; daraus wird keine weitergehende Semantik abgeleitet.
- Neue Regressionstests decken Idle-Energiezähler, optionale `nrg`-Verarbeitung, frische Definition, Reload-Aktualisierung des Versions-Internals, Firmware-Trennung, sichere Typdiagnostik und die getrennte Behandlung der beiden Protokollfelder ab.
- Der alte Fehler wurde am 24. Juni 2026 mit FHEM, einem Wattpilot Flex mit Firmware 43.4 und Modul 2.0.2 reproduziert. Die korrigierte Version 2.0.3 wurde dabei noch nicht auf echter Hardware getestet.

## [v2.0.2] - 2026-06-24

### Autorenschaft und Entwicklungsunterstützung im Modul

- Der Modulheader weist Dennis Gramespacher als ursprünglichen Autor und Flachzange als Autor der Neuentwicklung und grundlegenden Überarbeitung der Version 2.x aus.
- OpenAI ChatGPT wird im Modulheader und in den eingebetteten META-Daten als KI-gestützte Entwicklungsunterstützung genannt; technische Entscheidungen und Release-Verantwortung verbleiben bei Flachzange.
- Die META-Autorenliste enthält Dennis Gramespacher und Flachzange. Zusätzliche `x_...`-Felder trennen ursprüngliche Autorenschaft, Version-2.x-Autorenschaft und Entwicklungsunterstützung eindeutig.
- `AUTHORS.md`, beide READMEs und die Projektregeln dokumentieren dieselbe Zuordnung. Reload-Sicherheit innerhalb der 2.x-Reihe ist als grundsätzliches Kompatibilitätsziel festgeschrieben.

## [v2.0.1] - 2026-06-24

### Operative Status-Readings

- Sieben neue öffentliche Readings geben die vom Gerät gelieferten Felder `alw`, `modelStatus`, `msi`, `err`, `ama`, `amt` und `mca` als `chargingAllowed`, `chargingDecisionCode`, `chargingDecisionInternalCode`, `errorCode`, `maximumCurrentLimit`, `temperatureCurrentLimit` und `minimumChargingCurrent` aus.
- `chargingAllowed` wird stabil als `0` oder `1` ausgegeben. Entscheidungs- und Fehlerwerte bleiben unveränderte Ganzzahlcodes; es wird bewusst keine unbestätigte Text-Enum eingeführt.
- Die neuen Statuswerte werden unabhängig vom elektrischen `interval` und von `update_while_idle` sofort verarbeitet. Fehlende, `null`- oder typfalsche Felder löschen oder überschreiben vorhandene Readings nicht.
- Es wurden keine neuen Set-Befehle oder Geräte-Konfigurationsattribute ergänzt.

## [v2.0.0] - 2026-06-23

### Autorenschaft und Entwicklungsunterstützung

- Die Neuentwicklung und grundlegende Überarbeitung der Version 2.x stammt von Flachzange.
- Architektur, Implementierung, Review, Tests und Dokumentation entstanden mit KI-Unterstützung durch OpenAI ChatGPT. Technische Entscheidungen und Release-Verantwortung verbleiben bei Flachzange. Dennis Gramespacher bleibt als ursprünglicher Autor des Moduls ausgewiesen.

### FHEM-Schnittstellenhärtung

- Das Modul registriert keine leere `GetFn` mehr, solange keine eigenen Get-Befehle implementiert sind.
- Modulattribute werden vor der Speicherung auf ihre dokumentierten Wertebereiche geprüft; ungültige Werte lösen keine Lifecycle-, Credential-, Timer-, Verbindungs- oder Reading-Seiteneffekte aus.
- `define` akzeptiert ausschließlich die dokumentierte Form mit IP beziehungsweise Hostname und optionaler rein numerischer Seriennummer. Fehlende oder zusätzliche Argumente sowie ungültige Seriennummern werden vor jeder Zustandsänderung abgewiesen.

### Inkompatible öffentliche Schnittstelle

- Die öffentliche FHEM-Schnittstelle verwendet ausschließlich englische `lowerCamelCase`-Namen: 23 definierte Readings und die fünf Set-Befehle `password`, `chargingCurrent`, `forceState`, `chargingMode` und `nextTripTime`.
- Alte Reading-, Befehls-, Enum- und Lifecycle-Namen werden nicht parallel erzeugt und nicht als Aliase akzeptiert. Version 2.0.0 erfordert eine frische Definition; vorhandene alte Readings werden nicht automatisch gelöscht und Verbraucher müssen manuell angepasst werden.
- Enum-Werte und Lifecycle-Zustände sind stabil englisch benannt. Unbekannte `car`, `frc`- und `lmo`-Werte bleiben als `unknown:<Rohwert>` sichtbar. `nextTripTime` verlangt exakt `HH:MM`.

### Architektur und Persistenz

- Das Modul verwendet ausschließlich die beiden stabilen FUUID-basierten Credential-Schlüssel. Die namensbasierte Migration, Owner-Marker und Pending-Listen wurden aus dem Runtime-Code entfernt. Alte namensbasierte Schlüssel bleiben unangetastet; die veröffentlichten 1.6.x-Versionen sind die letzten Releases mit Upgrade-Unterstützung für diese Ressourcen.
- Passwortänderung und Gerätelöschung sind transaktionale Zwei-Schlüssel-Operationen mit vollständigem Snapshot, Rollback in umgekehrter Reihenfolge und ausdrücklicher Meldung eines unvollständigen Rollbacks.
- Gemeinsame Session-Invalidierung und die Ermittlung des konfigurierten Runtime-Zustands sind zentralisiert, ohne die bewährte Timer-, DevIo- und Reconnect-Eigentumslogik zu ersetzen.
- Statusdaten werden genau einmal in einer Kopie normalisiert. Die Reading-Verarbeitung ist in unmittelbare Werte, Fahrzeugübergänge, Electrical-Gating, Energiewerte und `nrg`-Readings aufgeteilt.

### Dokumentation und Tests

- Deutsche und englische Commandref, beide READMEs, API-Einstieg, Feldkatalog und Protokollmapping dokumentieren denselben aktiven 2.0-Vertrag. Alte 1.x-Namen bleiben nur in ausdrücklich markierten Umstellungs- oder Historienabschnitten.
- Vertragstests verlangen exakt die 23 öffentlichen Readings, prüfen bekannte und unbekannte Enum-Abbildungen, lehnen alle alten Set-Befehle ab und verhindern alte öffentliche Strings außerhalb ausdrücklich markierter Negativ-, Umstellungs- oder Historienbereiche.
- Legacy-Wattpilot-Protokoll 2, Parserhärtung, Authentifizierung, Command-Korrelation, Idle-Refresh, Lifecycle-Rennen und Credential-Rollback bleiben deterministisch abgesichert.

## [v1.6.0] - 2026-06-23

### Geändert

- `update_while_idle` hat eine dokumentierte Idle-Semantik: Es wird kein unbelegter Status-Request und kein `getAllValues` gesendet. Stattdessen verarbeitet das Modul echte Idle-`nrg`-Werte, lässt beim Charging-zu-Idle-Wechsel einen einmaligen Rate-Limit-Bypass für den ersten autoritativen Idle-Wert zu und plant bei fehlendem `nrg` höchstens einen begrenzten Reconnect pro Idle-Episode. Fehlende Werte werden niemals als Null interpretiert.
- Der Verbindungslebenszyklus unterscheidet jetzt `connecting`, `authenticating`, `initializing` und `connected`. `connected` wird erst nach erfolgreicher Authentifizierung und einer gültigen post-authentication Statusnachricht gesetzt.
- Authentication- und Initialization-Timeouts laufen jeweils nach 30 Sekunden ab und erlauben höchstens einen verzögerten Retry nach fünf Sekunden. `authError`, ungültige Auth-Konfiguration und Credential-Fehler starten keine automatische Retry-Schleife.
- Timer werden nach Art und Lifecycle-Generation verwaltet; veraltete Timer- und DevIo-Callbacks nach Disable, Undefine, Delete oder Shutdown bleiben wirkungslos. `ReadyFn` nutzt denselben guarded Open-Pfad wie Define, Enable und Auth-Änderungen.
- `ShutdownFn` ist registriert und führt synchronen, idempotenten Cleanup aus, ohne persistente Credentials zu löschen.

### Tests

- Neue deterministische Tests decken Idle-Refresh, Timeout-Retry, State-Machine, Timer-Kontexte, ReadyFn/DevIo-Seiteffekte, Open-Guard und Shutdown-Cleanup ab.

## [v1.5.0] - 2026-06-22

### Sicherheit und Robustheit

- JSON-Rückgaben werden bis insgesamt 1 MiB und höchstens 256 verkettete Dokumente strukturell und atomar verarbeitet. Mehrere vollständige Objekte sind zulässig; syntaktisch unvollständige Top-Level-Objekte werden in einem eigenen begrenzten JSON-Fortsetzungspuffer gehalten, während fehlerhafte, übergroße sowie skalare oder Array-Top-Level-Werte sicher abgewiesen werden. Das Modul verlässt sich für rohe WebSocket-Frame-Pufferung auf DevIos `.WSBUF` und führt keinen zweiten Rohframe-Puffer.
- Der Nachrichtentyp muss ein echter JSON-String sein; Statusobjekte, bekannte skalare Felder und die ersten zwölf `nrg`-Positionen werden vor der Verwendung validiert. Ungültige Felder verändern keine bestehenden Readings; ausgelassene `deltaStatus`-Felder bleiben unverändert. Unbekannte Nachrichtentypen und Zusatzfelder bleiben nicht fatal und werden normal nur redigiert protokolliert.
- `token3` verwendet 16 Bytes aus `Crypt::URandom`. Unbekannte ausdrücklich angekündigte Hashverfahren werden abgewiesen; der belegte Legacy-Fall `devicetype=wattpilot`, Protokoll 2, ohne `authRequired.hash` bleibt PBKDF2-kompatibel. Fehler bei der Signaturschlüssel-Speicherung brechen die Authentifizierung ab, und temporärer Auth-Zustand wird auf allen Disconnect-, Disable-, Passwort-, Fehler-, Undefine-, Delete- und Reconnect-Pfaden sowie beim Ändern oder Löschen von `authHash` bereinigt. Bei aktiviertem Gerät und lesbarem Passwort wird anschließend genau eine frische Anmeldung geplant; andernfalls bleibt der zutreffende Fehler- oder Disabled-Zustand erhalten.
- Gesicherte Nachrichten werden kanonisch serialisiert und behalten numerische innere Request-IDs, `sm`-Korrelation und HMAC-Vertrag. Deterministische synthetische PBKDF2-, bcrypt-, Auth-Antwort-, JSON- und HMAC-Vektoren sowie adversariale Parser- und Lifecycle-Tests schützen Legacy-Protokoll 2 und Flex.

## [v1.4.0] - 2026-06-22

### Geändert

- `frc` verwendet die korrigierten Werte 0=Neutral, 1=Stop und 2=Start; unbekannte Werte bleiben ausdrücklich unbekannt.
- Gesicherte Befehle werden nur bei offener und authentifizierter Verbindung sowie vorhandenem Signaturschlüssel gesendet. `Strom` wird vor dem Senden auf 6–32 A begrenzt.
- `response`-Nachrichten werden über die Request-ID korreliert, erfolgreiche Statuswerte über denselben Reading-Pfad verarbeitet und Fehler beziehungsweise Timeouts redigiert über Command-Readings gemeldet. Pending-Requests sind auf 32 Einträge und 30 Sekunden begrenzt.

## [v1.3.0] - 2026-06-21

### Hinzugefügt

- Expliziter Raw-JSON-Debugmodus, der vollständige ein- und ausgehende Frames nur bei gleichzeitigem `rawJsonLog=1` und `verbose=5` protokolliert und beim Aktivieren deutlich warnt.

### Geändert

- Zugangsdaten werden stabil FUUID-basiert gespeichert. Frühere Namen werden nur nach erfolgreicher Speicherung eines FUUID-basierten Pending-Verweises migriert oder bereinigt; ein Gerätename allein berechtigt nie zur Übernahme eines Legacy-Werts. Unbeanspruchte Altwerte bleiben unangetastet und können ein erneutes Setzen des Passworts erfordern.
- `UndefFn`, Rename, `rereadcfg`, Reload und Disable erhalten Zugangsdaten. Nur `DeleteFn` entfernt sie bei einem echten Löschen des Geräts.
- Wattpilot-eigene normale Logs der Level 1–4 enthalten keine vollständigen JSON-Payloads, Tokens, HMACs, Passwort-Hashes, Seriennummern oder privaten Endpunkte mehr; transitive FHEM-Core-/HttpUtils-Logs bleiben ausdrücklich außerhalb dieser Garantie.
- Timer und DevIo-Verbindungen werden bei Undefine, Delete und Disable bereinigt.
- DevIo-eigene Level-5-Payload-Logs werden durch den zentralen Wattpilot-Schreibpfad unterdrückt; Raw JSON bleibt ausschließlich explizit verfügbar. Transitive HttpUtils-Endpoint-Logs sind über die aktuelle öffentliche DevIo-Schnittstelle nicht vollständig unterdrückbar und werden als technische Grenze dokumentiert.
- Credential-Löschfehler verhindern über einen `DeleteFn`-Fehlertext das endgültige Löschen, Auth-Hash-Speicherfehler stoppen den Login, und Passwortänderungen invalidieren alte Hashes transaktional mit Rollback.
- Rename-Migrationen hängen nicht von der durch FHEM verworfenen `RenameFn`-Rückgabe ab. Persistente Pending-Metadaten sind der FUUID-basierte Eigentumsnachweis für Wiederholungen und dürfen fehlende Owner-Marker wiederherstellen; fehlt dieser Nachweis, wird sicher abgebrochen und ein später unter demselben Namen definiertes Gerät kann den Altwert nicht übernehmen. Credential-Lesefehler bleiben bis zu Define, Enable, Authentifizierung, gesicherten Befehlen und Delete-Wiederherstellung als `credential error` unterscheidbar. Credential-Löschungen verwenden vollständige Snapshots und stellen bei Teilfehlern Werte sowie den nach `UndefFn` abgebauten Runtime-Zustand wieder her.
- Der Verbindungsaufbau in Define hängt nur vom lesbaren Passwort ab. Fehler bei der best-effort-Migration oder -Bereinigung des optionalen Passwort-Hashes blockieren keinen Reconnect; die Authentifizierung schreibt anschließend einen aktuellen FUUID-basierten Hash, ohne fremde Legacy-Ressourcen zu verändern.

### Hinzugefügt

- Reproduzierbare Entwicklungs-, Strukturtest- und CI-Grundlage ohne Änderung des Modulverhaltens.

- Zentrale Modulversion und validierte FHEM-META-Daten mit getrennter Autor- und Maintainer-Zuordnung.
- Dokumentation der Protokollquellen und ihrer Vertrauensklassen.
- Reproduzierbare Release-Erzeugung mit Manifest-, SHA-256-, ZIP- und Bytegleichheitsprüfungen.

## [v1.2.0] - 2026-04-24

### Hinzugefügt

- **Wattpilot Flex Support:** Unterstützung für die neue Wattpilot Flex Generation durch Implementierung der `bcrypt`-Authentifizierung.
- **Sicherheit:** Das Passwort wird nun nicht mehr in der Definition, sondern separat über `set <name> Password <secret>` gesetzt und persistent (aber außerhalb der Konfigurationsdatei) gespeichert.
- **Authentifizierungs-Modus:** Neues Attribut `authHash` zur Auswahl des Verfahrens (`auto`, `pbkdf2`, `bcrypt`).
- **Erweiterte Messwerte:** Neue Readings für Einzelleistungen pro Phase (`Power_L1`, `Power_L2`, `Power_L3`) sowie die Firmware-Version (`version`) und das aktive Authentifizierungsverfahren (`authHashMode`).

### Geändert

- **Definition:** Die Syntax des `define`-Befehls hat sich geändert. Das Passwort ist kein Parameter mehr.

## [v1.1.1] - 2026-03-07


### Geändert

- **Performance:** Optimierung der PBKDF2-Kryptographie-Berechnung für den Login. Die angeforderte Hash-Länge wurde von 256 auf 24 Bytes reduziert, was zu einer um ca. 75 % schnelleren Hash-Block-Generierung führt. Für eine verbesserte Effizienz wird nun die native `PBKDF2_base64`-Methode genutzt.

## [v1.1.0] - 2026-01-26

### Hinzugefügt

- Das Reading `Energie_seit_Anstecken` wurde hinzugefügt.

## [v1.0.0] - 2026-01-06

### Hinzugefügt

- Erste Veröffentlichung (Initial Release).
