# Changelog

## [v2.1.7] - 2026-06-26

### Identity, device health, and optional raw diagnostics

- Adds always-visible `deviceType`, `deviceModel`, `deviceSubType`, `deviceVariant`, `helloProtocol`, and `statusProtocol` readings. The two protocol values remain source-separated and exact device strings are not mapped to invented models.
- Adds interval-controlled `deviceRebootCount` from `rbc` and `uptime` from `rbt`. `deviceRebootCount` is not idle-gated. Based on the maintainer live-device observation, `rbt` is treated as milliseconds and `uptime` is rendered after division by 1,000 as cumulative hours and minutes in `H:MM`; remaining seconds and milliseconds are discarded. `uptime` is eligible while charging or with `update_while_idle=1`.
- Adds boolean attribute `diagnosticReadings:0,1` with effective default `0`. Enabling it exposes fourteen exact `diag_`-prefixed raw scalar fields for real-device investigation, including `diag_fbuf_akkuSOC` and `diag_fbuf_pAkku` in place of the former standalone stationary-battery SOC/power readings; JSON numbers are rounded to exactly two decimal places without scaling, strings remain unchanged, and JSON booleans become `0|1`; no semantic interpretation is added.
- Setting `diagnosticReadings=0` or deleting the attribute immediately removes all optional diagnostic readings and clears their cache/dirty state. Optional diagnostics share the normal interval and charging/`update_while_idle` gate.
- Expands the authoritative reading inventory from 53 to 73 public readings and the consumed scalar status schema from 36 to 55 fields, with complete documentation and regression coverage.

## [v2.1.6] - 2026-06-26

### Positive interval timer replacement

- Changing `interval` between positive values now replaces the shared telemetry clock immediately when any telemetry owner is dirty. The new boundary is measured from the accepted attribute change, so queued values cannot remain unpublished while waiting for another status message.
- Positive-to-positive changes do not flush early, retain every owner cache and dirty field, preserve Idle eligibility, reject stale timer callbacks through the existing typed ownership context, and leave exactly one active `telemetry_flush` timer after repeated changes.
- When no telemetry is dirty, the positive replacement clock remains absent until later valid telemetry input starts it, preserving the established lazy-start contract. The existing positive-to-zero and delete-to-zero immediate flush behavior is unchanged.
- Extended `t/reading_update_policy.t` with queued publication without further input, repeated interval changes, stale callbacks, timer uniqueness, lazy no-dirty behavior, and Idle-gated owner coverage.

## [v2.1.5] - 2026-06-25

### Lifecycle and telemetry edge cases

- A regular WebSocket Close frame now results in a truthful `disconnected` state and exactly one guarded module reconnect when DevIo has removed its own ReadyFn/NEXT_OPEN owner. Ordinary EOF/read loss continues to use the DevIo-owned ReadyFn path without a competing module timer. The implementation is pinned to FHEM mirror revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b` and verifies that a `DevIoJustClosed` callback does not enter authentication without an open transport.
- The first valid authenticated `fullStatus` or `deltaStatus`, including `fullStatus` with `partial=true`, now completes initialization and cancels the initialization timeout. The `partial` flag controls snapshot completeness only; omitted fields still preserve existing readings.
- Session invalidation now centralizes pending-command finalization. Connection loss, disable, credential changes, authentication abort, lifecycle timeout, manual reconnect, definition replacement, and related session changes cancel the request timer, clear all pending entries, and expose one terminal redacted result for the newest request. Undefine and shutdown clear internal state without creating new command-reading events.
- The bounded Charging-to-Idle electrical refresh now runs with both `update_while_idle=0` and `1`. With `0`, only the one authoritative transition/grace-window `nrg` bypass is allowed; later ordinary Idle `nrg` and battery telemetry remain passive. Attribute changes do not duplicate or cancel an active refresh episode.
- Changing or deleting `interval` to an effective value of `0` now cancels the old shared clock and immediately publishes all currently eligible dirty telemetry owners in one FHEM reading transaction. Idle-gated electrical and battery data remains dirty/passive, while changed energy remains independently eligible.
- Added deterministic coverage for both DevIo reconnect-ownership paths, stale callbacks, partial initialization, all pending-command termination causes, both Idle-gate modes, attribute changes during refresh, and positive-to-zero/deleted interval transitions.

### Dynamic charging-current upper bound

- `chargingCurrent` now uses a device-confirmed `configMaximumCurrentLimit` as its local upper bound when that reading contains an integer from 6 through 32. The effective accepted range is `6..min(32, configMaximumCurrentLimit)`.
- Values above the effective limit are rejected before request creation and WebSocket output. The Usage response includes the accepted range, and FHEMWEB receives a matching dynamic slider maximum.
- Missing, not-yet-confirmed, malformed, non-integer, or out-of-range maximum-current readings retain the established compatibility range `6..32`; persisted readings are not trusted until `ama` has been received for the current device hash.
- The setter still sends only protocol key `amp` and never changes `configChargingCurrent` optimistically. The change adds no `ama` setter and does not promote third-party field evidence to an official Fronius Flex API claim.
- Added focused regression coverage for 16 A and 32 A limits, stale/missing/invalid/out-of-range fallback, dynamic Set discovery, exact error ranges, suppressed output on rejection, and device-confirmed reading ownership.

## [v2.1.4] - 2026-06-25

### Grouped phase-switch and minimum-charging setters

- Replaced the seven individual top-level Set commands `phaseSwitchMode`, `phaseSwitchDelay`, `minimumPhaseSwitchInterval`, `threePhaseSwitchPower`, `minimumChargeTime`, `minimumChargingPauseDuration`, and `minimumChargingInterval` with two grouped commands: `phaseSwitch mode|delay|minInterval|threePhasePower` and `minimumCharging duration|interval|pauseDuration`.
- Preserved the exact protocol mappings and value contracts: `psm`, `mpwst`, `mptwt`, `spl3`, `fmt`, `mci`, and `mcpd`; phase-switch mode keeps the existing enum mapping, public durations remain seconds converted exactly to whole protocol milliseconds, and `threePhasePower` remains a finite non-negative watt value.
- Kept `chargingPauseAllowed` as a separate top-level command. Confirmed `config...` readings, secured request correlation, device-response handling, cadence, and protocol semantics are unchanged.
- Added no compatibility aliases. FHEMWEB discovery now exposes each grouped command exactly once and no longer advertises the seven former individual names.
- Extended declarative-schema, energy-control, public-interface, documentation, and exact-arity tests for all grouped subcommands and invalid-input paths.

## [v2.1.3] - 2026-06-25

### Declarative status and command schemas

- Extended the existing authoritative reading inventory with incoming validators and formatter details. The runtime status schema and immediate publication list are now derived from that inventory instead of being maintained in separate branch tables.
- Added one compact command schema for public names, FHEMWEB widget metadata, exact arity, parsers, protocol keys, JSON conversion, Usage text, and the established `chargingMode` error behavior. `password`, `reconnect`, and grouped `pvBattery` handling remain explicit.
- Replaced repetitive immediate-reading and ordinary-Set branch chains with small generic helpers while keeping authentication, lifecycle, request correlation, telemetry caches, car transitions, and special protocol behavior visible. Public readings, commands, payloads, cadence, and command-result semantics are unchanged.
- Added schema completeness and behavior guards for all 36 consumed status fields, all 19 public Set commands, all 16 ordinary Set parsers, JSON boolean output, validator rejection, formatter execution, and generated Set discovery.
- Despite the added schema metadata, the module shrinks from 3,397 to 3,251 lines. `Wattpilot_UpdateImmediateReadings` drops from 158 to 14 lines and `Wattpilot_Set` from 134 to 50 lines; `Wattpilot_NormalizeStatus` and `Wattpilot_DispatchMessage` remain unchanged because their validation loop and lifecycle dispatch are already explicit.

## [v2.1.2] - 2026-06-25

### Public reading precision

- Public measured and calculated physical values are formatted with exactly two decimal places and retained trailing zeroes. Rounded negative zero is normalized to positive zero.
- `configPvSurplusStartPower` and `configThreePhaseSwitchPower` now follow the same two-decimal public format as voltage, current, power, energy, and `pvBatteryPower`. Validation and setter payload types are unchanged.
- Explicit exceptions remain documented in the existing authoritative reading inventory: `pvBatterySoC` keeps one decimal place; booleans, integer codes and settings, percentages, clocks, durations, enums, and text retain their established formats.
- Added exact-string regression coverage across fullStatus, deltaStatus, matched responses, fresh initialization, invalid input, scientific notation, and negative-zero rounding.

## [v2.1.1] - 2026-06-25

### Reading publication policy and rate-limit regression

- Added one authoritative policy inventory for all 53 public readings, including category, source, publication policy, idle gate, cache/history owner, formatter, and invalid-input behavior. Runtime categories and interface guards derive from that inventory.
- Keep separate latest-value caches and dirty fields for cumulative energy, electrical `nrg`, and stationary-battery SOC/power, but publish all eligible dirty owners on one shared interval clock and in one FHEM reading transaction. Owner separation prevents cross-group starvation and stale cache republication while aligned ticks provide one common timestamp.
- `energyTotal` and `energySincePlugIn` now obey the shared `interval` clock and become dirty only when the formatted public value changes. Identical `eto`/`wh` values renew neither timestamps nor events. `interval=0` publishes eligible dirty values immediately; missing, `null`, malformed, wrong-type, out-of-range, or incomplete input preserves readings and does not move the clock.
- `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `pvBatteryModeCode`, both charging-decision code/text pairs, and `errorCode` are immediate-on-change. Identical values from repeated snapshots do not renew timestamps or create events; decision code/text pairs remain atomic.
- Validated internal `car` state remains immediate and drives idle gating and charging-to-idle transitions before public publication. The bounded one-shot idle refresh/reconnect behavior remains intact, and no polling command or synthetic zero value was added.
- FullStatus, partial fullStatus, deltaStatus, and matched response status now use the same publication policy. Regression tests inspect values, timestamps, and events, including repeated battery-before-`nrg` ordering and exact interval boundaries.
- Updated both embedded command references, both READMEs, API, architecture, testing, protocol/evidence documents, reading-policy inventory, and release metadata. Real-device verification on a Wattpilot Flex Home 22 C6 with firmware 43.4 remains required before release.

## [v2.1.0] - 2026-06-25

### Audit corrections and simplification

- FHEM `modify` and `defmod` now validate the complete new definition before changing runtime state. A valid endpoint or serial change terminates pending commands, invalidates the old session, closes the old DevIo context, and schedules exactly one reconnect; a rejected modification is side-effect free.
- Message-envelope metadata is preserved separately from status fields. A `partial:true` `fullStatus` applies incremental fields without completing initialization or prematurely ending the one-shot idle-refresh wait.
- Consumed JSON fields now use exact string, number, integer, boolean, array, and object contracts. Numeric strings and boolean surrogates are rejected. `ftt`, `pdls`, and `pdlo` use shared range- and minute-aligned clock validation.
- The ineffective public attributes `debug` and `defaultAmp`, the empty attribute branch, and unused `defptr` bookkeeping were removed without aliases or migration.
- English and German command-reference inventories are checked against the runtime interface. Current API and release documentation was aligned.
- Release contents now come from one manifest. CI, build, verification, and reproducibility no longer rerun the full source suite recursively, and every maintained packaged file is byte-compared between source, package directory, and ZIP.

## [v2.0.10] - 2026-06-25

- Enforce exact argument counts for the single-value Set commands `password`, `forceState`, `chargingCurrent`, `chargingMode`, and `nextTripTime`; surplus arguments now return the documented Usage error without sending a frame or changing credential storage.

### Korrekte FHEMWEB-Set-Liste

- `reconnect` wird in der Set-Befehlsliste nun als `reconnect:noArg` veröffentlicht. FHEMWEB zeigt dadurch kein unnötiges Wertefeld für diesen argumentlosen Befehl an.
- Die Set-Liste wird zentral durch `Wattpilot_SetOptions` erzeugt und sowohl für die normale Hilfe als auch für unbekannte Befehle verwendet.
- `set <name> ?` wird vor der Laufzeitsperre für `disable=1` beantwortet. Dadurch erhält FHEMWEB auch bei deaktiviertem Device eine gültige Befehlsliste statt des Satzes `Device is disabled`, dessen Wörter zuvor als scheinbare Set-Befehle interpretiert wurden.
- Tatsächliche Set-Befehle bleiben bei `disable=1` unverändert gesperrt.
- Regressionstests prüfen die identische Befehlsliste im aktiven und deaktivierten Zustand, `reconnect:noArg` sowie das Fehlen der falschen Einträge `module`, `disabled` und `is`.

## [v2.0.9] - 2026-06-24

### Gruppierte PV-Speicher-Setter und konsistente SoC-Namen

- Einen einzigen Top-Level-Befehl `pvBattery` ergänzt. Die Unterbefehle `chargeAboveSoC`, `dischargeEnabled`, `dischargeUntilSoC`, `dischargeTimeLimitEnabled`, `dischargeStartTime` und `dischargeStopTime` schreiben die Rohfelder `fam`, `pdte`, `pdt`, `pdle`, `pdls` und `pdlo` über den bestehenden gesicherten `setValue`-Pfad.
- Prozent-Setter akzeptieren ausschließlich ganze Werte von 0 bis 100. Boolesche Setter senden echte JSON-Booleans. Startzeit akzeptiert `00:00` bis `23:59`; Stoppzeit zusätzlich `24:00`. Zeitwerte werden als ganze Sekunden seit Mitternacht übertragen.
- Keine optimistischen Reading-Updates: nur vom Gerät zurückgelieferter Status bestätigt einen neuen Wert; Fehlerantworten lassen den zuletzt bestätigten Wert unverändert.
- Öffentliche Namen verwenden einheitlich `SoC`: `pvBatterySoC`, `configPvBatteryChargeAboveSoC` und `configPvBatteryDischargeUntilSoC`. `configPvBatteryDischargeEndTime` wurde ohne Alias oder Migration in `configPvBatteryDischargeStopTime` umbenannt.
- Automatisierte Tests decken exakte Payload-Schlüssel und JSON-Typen, Grenzwerte, Zeitkonvertierung, ungültige Syntax, fehlende optimistische Updates sowie erfolgreiche und fehlgeschlagene Responses ab.
- Alle sechs gruppierten Setter wurden auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 einzeln geändert, vom Gerät angenommen, über geräteseitigen Status/Readback bestätigt und auf ihre Ausgangswerte zurückgesetzt. Bewusste Geräteablehnung, Persistenz über einen Neustart und weitere Firmware-/Modellstände bleiben ungetestet.

## [v2.0.8] - 2026-06-24

### PV-Speicher-Konfiguration aus App und Status zugeordnet

- Sechs auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 gleichzeitig in Solar.wattpilot-App und `fullStatus` beobachtete PV-Speichereinstellungen ausschließlich lesend veröffentlicht.
- `fam` wird als `configPvBatteryChargeAboveSoC`, `pdte` als `configPvBatteryDischargeEnabled`, `pdt` als `configPvBatteryDischargeUntilSoC`, `pdle` als `configPvBatteryDischargeTimeLimitEnabled`, `pdls` als `configPvBatteryDischargeStartTime` und `pdlo` als `configPvBatteryDischargeStopTime` ausgegeben.
- Prozentwerte werden nur im Bereich 0 bis 100 akzeptiert, boolesche Werte stabil als `0`/`1` ausgegeben und ganze Minuten seit Mitternacht als `HH:MM` dargestellt. Fehlende, `null`- oder ungültige Werte überschreiben bestehende Readings nicht.
- Die sechs Readings folgen unmittelbar dem in Version 2.0.7 eingeführten `config...`-Schema. Es gibt keine Aliase oder Migration.
- Noch keine Batterie-Set-Befehle ergänzt: Schreibbarkeit, Geräteantwort, Readback, Restore, Grenzen und weitere Modell-/Firmwarestände bleiben vor Veröffentlichung von Settern zu verifizieren.

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

## [v2.0.7] - 2026-06-24

### Einheitliches Schema für Konfigurationsreadings

- Alle 47 öffentlichen Readings wurden explizit als Lifecycle, Identität, Konfiguration, Laufzeitstatus, Telemetrie, Diagnose oder Command-Diagnose klassifiziert. Der vollständige Audit steht in `docs/READING-CATEGORIES.md` und wird über `Wattpilot_InterfaceSnapshot` automatisiert geprüft.
- Sämtliche 18 Konfigurationsreadings verwenden nun das feste Präfix `config`: `configForceState`, `configChargingCurrent`, `configChargingMode`, `configMaximumCurrentLimit`, `configMinimumChargingCurrent`, `configPvSurplusStartPower`, `configPvSurplusEnabled`, `configZeroFeedInEnabled`, `configPvControlPreference`, `configPhaseSwitchMode`, `configThreePhaseSwitchPower`, `configPhaseSwitchDelay`, `configMinimumPhaseSwitchInterval`, `configMinimumChargeTime`, `configChargingPauseAllowed`, `configMinimumChargingPauseDuration`, `configMinimumChargingInterval` und `configNextTripTime`.
- Die Namen und Semantik aller Set-Befehle bleiben unverändert. Beispielsweise schreibt `set <name> chargingMode eco` weiterhin die Konfiguration, während der bestätigte Gerätewert im Reading `configChargingMode` erscheint.
- Laufzeitwerte werden nicht allein wegen eines Konfigurationsbezugs präfixiert: `temperatureCurrentLimit` bleibt ein wirksames temperaturabhängiges Limit, `authHashMode` die tatsächlich gewählte Authentifizierungsmethode und `pvBatteryModeCode` ein aktueller Statuscode.
- Bewusst keine Migration: Es gibt keine Aliase, keine parallelen alten und neuen Readings, keine automatische Reading-Bereinigung, keine DbLog-Konvertierung und keine Übergangsfrist. DOIFs, Notifies, Plots, DbLog-/Influx-Abfragen, Dashboards und Skripte müssen auf die neuen Namen angepasst werden. Nach einem Reload können alte Reading-Einträge im bestehenden FHEM-Device als nicht mehr aktualisierte Werte erhalten bleiben und müssen bei Bedarf manuell entfernt oder durch eine frische Definition vermieden werden.
- Deutsche und englische Commandref, beide READMEs, API-/Architektur-/Protokolldokumentation, öffentliche Interface-Guards und Tests wurden auf das neue Schema aktualisiert.

## [v2.0.6] - 2026-06-24

- Drei ausschließlich lesende Readings für den stationären PV-Speicher ergänzt: `pvBatterySoC` aus `fbuf_akkuSOC`, `pvBatteryPower` aus `fbuf_pAkku` und `pvBatteryModeCode` aus `fbuf_akkuMode`. Sie bezeichnen ausdrücklich nicht den Fahrzeugakku.
- `pvBatterySoC` akzeptiert nur endliche Werte von 0 bis 100 Prozent und wird mit genau einer Nachkommastelle ausgegeben. `pvBatteryPower` gibt den vorzeichenbehafteten Wattwert grundsätzlich mit zwei Nachkommastellen aus; mangels kontrolliert bestätigter Vorzeichenrichtung wird Laden/Entladen nicht umgedeutet. `pvBatteryModeCode` bewahrt den nicht negativen Rohcode; mangels belastbarer Enum wird kein Klartextmodus erfunden.
- Fehlende, `null`-, typfalsche, NaN-, unendliche oder außerhalb des belegten SOC-Bereichs liegende Batteriefelder verändern vorhandene Readings nicht.
- Die damalige Version 2.0.6 verwendete für elektrische und stationäre Speicherreadings eine gemeinsame `interval`-Zeitbasis und einen gemeinsamen Zwischenspeicher. Diese historische Policy wurde in Version 2.1.1 wegen der daraus möglichen Verhungerung frischer `nrg`-Werte durch getrennte Zeitbasen ersetzt.
- Historisch konnten gültige Batterieinformationen einen gemeinsamen Messzyklus auslösen und dabei alte elektrische Cachewerte erneut veröffentlichen. Version 2.1.1 trennt deshalb Cache- und Dirty-Eigentum strikt, verwendet für die kontrollierte Veröffentlichung aber bewusst einen gemeinsamen Takt: Ein Tick veröffentlicht nur die jeweils zulässigen geänderten Eigentümer.
- Bewusst keine Batterie-Setter ergänzt: `fam` und die Rohschlüssel hinter den neueren Fronius-App-Einstellungen bleiben bis zur eindeutigen Semantik- und Schreibverifikation außerhalb der öffentlichen Schnittstelle.
- Die Endnutzerdokumentation erklärt nun, dass aWATTar ein Anbieter-/Tarifname ist und dass `Fallback` in den importierten go-e-Entscheidungsnamen einen Standardausgang der Logik, nicht automatisch einen technischen Fehler bezeichnet. Der bestehende Vorbehalt zur unbestätigten Flex-Semantik bleibt ausdrücklich erhalten.
- Dokumentation und Tests halten nun den erfolgreichen Realgerätetest von Version 2.0.5 fest: alle elf Konfigurationssetter wurden auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 einzeln geändert, bestätigt und zurückgesetzt; `set reconnect` stellte die Sitzung erfolgreich neu her.

## [v2.0.5] - 2026-06-24

### PV-, Phasen- und Fahrzeugparameter

- Elf weitere Konfigurationsfelder werden als öffentliche Readings verarbeitet: `pvSurplusEnabled` (`fup`), `zeroFeedInEnabled` (`fzf`), `pvControlPreference` (`frm`), `phaseSwitchMode` (`psm`), `threePhaseSwitchPower` (`spl3`), `phaseSwitchDelay` (`mpwst`), `minimumPhaseSwitchInterval` (`mptwt`), `minimumChargeTime` (`fmt`), `chargingPauseAllowed` (`fap`), `minimumChargingPauseDuration` (`mcpd`) und `minimumChargingInterval` (`mci`). Fehlende, `null`- oder typfalsche Delta-Felder verändern vorhandene Readings nicht.
- Für alle elf Werte gibt es gleichnamige Setter über den vorhandenen gesicherten `setValue`-Pfad. Boolesche Werte werden als echte JSON-Booleans übertragen; Enum-Werte werden auf die dokumentierten numerischen Protokollwerte abgebildet. Öffentliche Zeitwerte verwenden Sekunden und werden nur dann gesendet, wenn sie sich exakt in ganze Protokoll-Millisekunden umrechnen lassen.
- Das Modul setzt keine unbelegten Obergrenzen und übernimmt angeforderte Werte nicht optimistisch. Nur vom Gerät gelieferte Statusdaten bestätigen Readings; Ablehnung und Timeout bleiben über die vorhandenen Command-Status-Readings sichtbar.
- Die öffentliche Bezeichnung `minimumChargingInterval` folgt dem gepinnten API-Alias für `mci`; die aktuelle Fronius-Flex-Bedienungsanleitung bezeichnet die zugehörige Fahrzeugeinstellung als „Forced charging interval“. Diese Quellenabgrenzung ist dokumentiert. Alle elf Setter wurden anschließend auf einem Wattpilot Flex Home 22 C6 mit Firmware 43.4 einzeln geschrieben, per Geräte-Rückmeldung bestätigt und auf den Ausgangswert zurückgesetzt.

### Kontrollierter manueller Reconnect

- `set <name> reconnect` verwirft die aktuelle lokale WebSocket-Sitzung kontrolliert und startet genau einen neuen Verbindungs- und Authentifizierungszyklus. Der Befehl sendet kein Wattpilot-Protokollkommando und ist ausdrücklich kein `fullStatus`-Request.
- Sitzungsgebundene Timer, Authentifizierungs-, Teil-JSON- und Idle-Refresh-Zustände werden verworfen; Betriebsreadings, Definition, Seriennummer und Credentials bleiben erhalten. Ausstehende gesicherte Befehle enden mit `lastCommandStatus=failed` und `lastCommandError=reconnect requested`.
- Lifecycle-Tests decken verbundene, getrennte, fehlgeschlagene, verbindungsaufbauende und authentifizierende Zustände, schnelle Wiederholungen, veraltete asynchrone Open-Callbacks, fehlende oder nicht lesbare Credentials, deaktivierte beziehungsweise inaktive Devices sowie die Interaktion mit dem Idle-Refresh ab. Die Tests bilden außerdem den aktuellen DevIo-Nebeneffekt nach, dass ein erfolgreicher asynchroner Open vor dem Modul-Callback den Framework-State auf `opened` setzt; veraltete Callbacks stellen danach zuverlässig `disabled` beziehungsweise `disconnected` wieder her oder übergeben genau einen wartenden Reconnect. Ein echter Reconnect-Test am Wattpilot Flex steht noch aus.

## [v2.0.4] - 2026-06-24

### PV-Überschuss-Startleistung

- Das neue Reading `pvSurplusStartPower` gibt den nicht negativen, endlichen Zahlenwert aus dem Gerätefeld `fst` in Watt aus. Fehlende, `null`-, negative, nicht numerische oder nicht endliche Werte lassen ein vorhandenes Reading unverändert.
- `set <name> pvSurplusStartPower <Watt>` sendet `fst` über den bestehenden gesicherten `setValue`-Pfad. Das Modul setzt keine unbelegte Obergrenze und übernimmt den angeforderten Wert nicht optimistisch; nur ein vom Gerät gelieferter Statuswert bestätigt das Reading. Ablehnung und Timeout bleiben über die vorhandenen Command-Status-Readings sichtbar.
- Die Zuordnung und Schreibbarkeit stützen sich auf gepinnte offizielle go-e-API-Metadaten, gepinnte Wattpilot-spezifische Evidenz und den bereinigten Flex-43.4-Wert `fst=1400`. Dies wird nicht als offizielle Fronius-Flex-API-Spezifikation dargestellt.
- Automatisierte Tests decken Full-/Delta-Status, Null-/Fehlertypen, Nullwert, Dezimalwerte, gesicherte Request-Kodierung sowie erfolgreiche, abgelehnte, unvollständige und typfalsche Responses ab. Der Maintainer hat Lesen, Schreiben, Geräte-Rückmeldung und Wiederherstellung des Ausgangswerts anschließend mit FHEM und einem Wattpilot Flex mit Firmware 43.4 erfolgreich geprüft.

## [v2.0.3] - 2026-06-24

### Laufzeitkorrekturen nach dem ersten Flex-Praxistest

- Version 2.0.3 nahm `energyTotal` und `energySincePlugIn` historisch aus dem damaligen gemeinsamen `nrg`-/Idle-Gate heraus. Seit Version 2.1.1 behalten sie einen eigenen Latest-Value-/Dirty-Eigentümer, teilen aber den gemeinsamen Telemetrietakt und werden nur bei einer tatsächlichen Änderung ihres formatierten öffentlichen Werts veröffentlicht.
- Das Device-Internal `VERSION` enthält die Modulversion `2.0.3`. Die vom Wattpilot gemeldete Firmware überschreibt dieses Internal nicht mehr und bleibt im Reading `firmwareVersion`. Frische Definitionen und bestehende Devices beim Modul-Reload werden berücksichtigt, ohne Verbindung, Timer, Credentials oder Readings neu zu initialisieren.
- Nicht unterstützte JSON-Nachrichtentypen werden weiterhin ohne Payload ignoriert. Ein kurzer, streng begrenzter ASCII-Typname wird nun tatsächlich im Log genannt; ungeeignete Typwerte erscheinen als `redacted`.
- Der reale Flex-Startablauf mit Firmware 43.4 bestätigte zusätzlich die Nachrichtentypen `clearInverters`, `updateInverter` und `clearSmips`. Sie sind als beobachtete, derzeit ungenutzte Startnachrichten dokumentiert und werden ohne Level-3-Warnung ignoriert; Payload-Aufbau und Bedeutung bleiben ausdrücklich unbekannt.
- Zusätzlich zu den unveränderten Rohwerten `chargingDecisionCode` (`modelStatus`) und `chargingDecisionInternalCode` (`msi`) liefern `chargingDecision` und `chargingDecisionInternal` direkt nutzbare lowerCamelCase-Klartextwerte. Die Kompatibilitätszuordnung folgt der gepinnten offiziellen go-e-`modelStatus`-Enum; unbekannte Codes bleiben als `unknown:<Code>` sichtbar. Für `msi` wird dieselbe Tabelle verwendet, ohne eine unbestätigte Priorität oder Kausalkette zwischen beiden Gerätefeldern anzunehmen. Die genaue Beziehung, Auswertungsreihenfolge und eine mögliche Rolle von `cpDisabledRequest` bleiben für Wattpilot Flex ausdrücklich unbestätigt.

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
