# Wattpilot API documentation

This file is the stable entry point for the repository's JSON/WebSocket API documentation.

## Public FHEM interface

The active public interface of version 2.1.5 is documented in the embedded English and German command reference in [`72_Wattpilot.pm`](72_Wattpilot.pm), with setup examples in [`README_en.md`](README_en.md) and [`README.md`](README.md). The protocol documents below describe evidence and internal protocol mappings; they do not define additional public readings or set commands. Raw decision codes remain available beside compatibility text mappings with explicit `unknown:<code>` fallbacks; the exact relationship between `modelStatus` and `msi` remains unconfirmed. Version 2.0.5 added the evidenced PV-surplus, zero-feed-in, control-preference, phase-switch, and vehicle pause/timing fields from issue #44. Version 2.0.6 added read-only stationary-PV-battery telemetry as `pvBatterySoC` (`fbuf_akkuSOC`), `pvBatteryPower` (`fbuf_pAkku`), and `pvBatteryModeCode` (`fbuf_akkuMode`). The power sign is preserved without assigning an unverified charge/discharge direction, and the mode remains a raw code because no reliable enum is established. These telemetry readings are not writable.

Version 2.0.7 classifies every public reading and uses the exact `config` prefix for all stored or user-selectable configuration readings. Set-command names remain unchanged. The complete audit and the deliberate non-configuration exceptions are recorded in [`docs/READING-CATEGORIES.md`](docs/READING-CATEGORIES.md). There are no aliases, duplicate old/new readings, automatic reading migration, DbLog migration, or transition period. Existing consumers must be adapted explicitly; stale old readings may remain in an already existing FHEM device until the device is recreated or those readings are removed manually.

Version 2.0.8 adds six stationary-PV-battery configuration readings: `configPvBatteryChargeAboveSoC` (`fam`), `configPvBatteryDischargeEnabled` (`pdte`), `configPvBatteryDischargeUntilSoC` (`pdt`), `configPvBatteryDischargeTimeLimitEnabled` (`pdle`), `configPvBatteryDischargeStartTime` (`pdls`), and `configPvBatteryDischargeStopTime` (`pdlo`). The mapping is evidenced by exact agreement between a simultaneous Solar.wattpilot app view and a Flex Home 22 C6 firmware-43.4 `fullStatus`.

Version 2.0.9 consistently uses `SoC` in public names, renames the former discharge end-time reading to `configPvBatteryDischargeStopTime`, and adds one grouped command: `set <name> pvBattery <subcommand> <value>`. The six subcommands write `fam`, `pdte`, `pdt`, `pdle`, `pdls`, and `pdlo` through the existing secured `setValue` path without optimistic reading updates. All six grouped setters were changed individually on a Wattpilot Flex Home 22 C6 running firmware 43.4, accepted by the device, confirmed through device-supplied status/readback, and restored to their original values. Deliberate device rejection, persistence across reboot, and broader firmware/model scope remain unverified.

Version 2.0.10 advertises `reconnect` as `reconnect:noArg`, returns the same authoritative Set list for `set <name> ?` with `disable=1`, and enforces exact argument counts for the previously permissive single-value commands `password`, `forceState`, `chargingCurrent`, `chargingMode`, and `nextTripTime`. Runtime commands remain rejected while disabled.

Version 2.1.0 treats a successful FHEM `modify`/`defmod` definition change as a full session transition, while an invalid modification is side-effect free. Incoming status fields now use exact JSON-type validation, `fullStatus.partial` remains message-envelope metadata, and clock fields reject wrong types, invalid ranges, and non-minute values. The no-op `debug` and `defaultAmp` attributes were removed without aliases or migration.

Version 2.1.1 applies one authoritative reading policy to fullStatus, partial fullStatus, deltaStatus, and matched response status. Configuration remains device-confirmed and immediate; discrete status and diagnostic readings are immediate-on-change. Cumulative energy, electrical `nrg`, and stationary-battery SOC/power keep separate latest-value caches and dirty fields but publish all eligible changes on one shared interval clock and in one FHEM reading transaction. Energy is dirty only when its formatted public value changes. Unrelated owners cannot republish stale cache values, invalid input does not move the shared clock, and validated internal `car` state remains immediate.

Version 2.1.2 records the public formatter in that same reading inventory. Measured and calculated physical values use exactly two decimal places with trailing zeroes, including the `fst` and `spl3` configuration readings. Rounded negative zero is normalized to positive zero. Explicit exceptions remain for percentages, integral settings and codes, clocks, and durations; `pvBatterySoC` intentionally keeps one decimal place. Validation and setter payload types are unchanged.

Version 2.1.3 adds no public API elements. Incoming validators, immediate status formatting, ordinary Set parser/arity contracts, protocol keys, FHEMWEB widget metadata, and Usage strings are now derived from the authoritative reading and command schemas. `password`, `reconnect`, grouped `pvBattery`, lifecycle, authentication, telemetry caching, and car-transition behavior remain explicit. Public names, payload types, rate limits, and response semantics are unchanged.

Version 2.1.4 changes only the public Set command grouping for seven already verified fields. `phaseSwitch mode|delay|minInterval|threePhasePower` writes `psm`, `mpwst`, `mptwt`, and `spl3`; `minimumCharging duration|interval|pauseDuration` writes `fmt`, `mci`, and `mcpd`. The former individual Set names are removed without aliases. Protocol keys, JSON types, units, validation, secured request handling, device-confirmed readings, and rate limits are unchanged.

Version 2.1.5 uses a usable, device-confirmed `configMaximumCurrentLimit` (`ama`) as the local upper bound for `chargingCurrent` (`amp`). The effective range is `6..min(32, configMaximumCurrentLimit)`. Missing, not-yet-confirmed, malformed, non-integer, or out-of-range limit readings retain the compatibility range `6..32`. The same bound is used for the FHEMWEB slider and local validation; rejected values create no secured request. This is a FHEM safety/UX constraint based on the already published read-only reading and does not add writability for `ama` or change the device-confirmed ownership of `configChargingCurrent`.

Public power values use watts and public durations use seconds while the corresponding protocol fields use milliseconds. These mappings combine official Fronius behavior documentation, pinned go-e API metadata, pinned Wattpilot-specific implementation evidence, and the sanitized Flex 43.4 field observation; they are not presented as an official Fronius WebSocket API specification. `set <name> reconnect` is a local lifecycle command that sends no protocol frame and must not be interpreted as a `fullStatus` request.

## Protocol profiles

The original Wattpilot generation is covered by [`docs/WATTPILOT-LEGACY-PROTOCOL2.md`](docs/WATTPILOT-LEGACY-PROTOCOL2.md) and the synthetic fixture [`t/fixtures/legacy-protocol2-session.json`](t/fixtures/legacy-protocol2-session.json). The Flex generation is documented separately below. Neither document is an official protocol specification.

## Pure sanitized JSON example

The complete sanitized `fullStatus` capture is available as a standalone JSON file:

[`t/fixtures/fullStatus-flex-observed.json`](t/fixtures/fullStatus-flex-observed.json)

It contains the complete observed message wrapper and all 558 direct `status` keys from the documented Wattpilot Flex Home 22 C6 capture. Identifiers, network coordinates, authentication material, exact operational counters, market data, and installation-specific labels were replaced while preserving the key set, nesting, array lengths, null positions, JSON scalar types, and representative values.

This fixture is the single canonical JSON copy used both by the documentation and automated tests. It should not be duplicated under another path, because two independently editable copies could drift apart.

## Current empirical Flex reference

Use [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md) for the sanitized observation from a Wattpilot Flex Home 22 C6 with firmware 43.4 and observed status field `proto=4`. Separate live FHEM observations derived `hello.protocol=2` and recorded the unused startup message types `clearInverters`, `updateInverter`, and `clearSmips`; these facts are documented independently and no unobserved semantics are assumed. The reference is authoritative only for the explicitly recorded structure, ordering, type names, JSON types, and sanitized representative values of the cited observations.

## Field names and description candidates

Use [`docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md`](docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md) as a companion lookup for readable aliases, titles, description candidates, unit candidates, enum candidates, categories, and historical read/write claims.

Those descriptions are retained from the former root `API.md` compilation. They are historical candidates, not confirmed Wattpilot Flex facts. Always cross-check them against the empirical Flex reference and [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md).

## Evidence rule

No document in this repository is an official Fronius API specification. A historical alias, current implementation, or third-party implementation does not by itself establish field meaning, unit, enum semantics, requiredness, or writability.

When sources conflict, the conflict must remain visible rather than being silently resolved.
