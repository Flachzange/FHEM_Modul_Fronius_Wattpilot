# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [Unreleased]

## [v1.3.0] - 2026-06-21

### Hinzugefügt

- Expliziter Raw-JSON-Debugmodus, der vollständige ein- und ausgehende Frames nur bei gleichzeitigem `rawJsonLog=1` und `verbose=5` protokolliert und beim Aktivieren deutlich warnt.

### Geändert

- Zugangsdaten werden stabil FUUID-basiert gespeichert; bestehende namensbasierte Schlüssel werden verlustsicher migriert und erst nach erfolgreicher Neuspeicherung entfernt.
- `UndefFn`, Rename, `rereadcfg`, Reload und Disable erhalten Zugangsdaten. Nur `DeleteFn` entfernt sie bei einem echten Löschen des Geräts.
- Wattpilot-eigene normale Logs der Level 1–4 enthalten keine vollständigen JSON-Payloads, Tokens, HMACs, Passwort-Hashes, Seriennummern oder privaten Endpunkte mehr; transitive FHEM-Core-/HttpUtils-Logs bleiben ausdrücklich außerhalb dieser Garantie.
- Timer und DevIo-Verbindungen werden bei Undefine, Delete und Disable bereinigt.
- DevIo-eigene Level-5-Payload-Logs werden durch den zentralen Wattpilot-Schreibpfad unterdrückt; Raw JSON bleibt ausschließlich explizit verfügbar. Transitive HttpUtils-Endpoint-Logs sind über die aktuelle öffentliche DevIo-Schnittstelle nicht vollständig unterdrückbar und werden als technische Grenze dokumentiert.
- Credential-Löschfehler verhindern über einen `DeleteFn`-Fehlertext das endgültige Löschen, Auth-Hash-Speicherfehler stoppen den Login, und Passwortänderungen invalidieren alte Hashes transaktional mit Rollback.
- Fehlgeschlagene Rename-Migrationen bleiben über getrennte, nicht-sensitive und FUUID-bezogene Pending-Metadaten für Passwort und Passwort-Hash auch nach Reload oder Neustart retryfähig. Credential-Löschungen verwenden vollständige Snapshots und stellen bei Teilfehlern Werte sowie den nach `UndefFn` abgebauten Runtime-Zustand wieder her.

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
