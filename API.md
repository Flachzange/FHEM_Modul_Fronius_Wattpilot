# Wattpilot API documentation

This file is the stable entry point for the repository's JSON/WebSocket API documentation.

## Public FHEM interface

The active public interface of version 2.0.3 is documented in the embedded English and German command reference in [`72_Wattpilot.pm`](72_Wattpilot.pm), with setup examples in [`README_en.md`](README_en.md) and [`README.md`](README.md). The protocol documents below describe evidence and internal protocol mappings; they do not define additional public readings or set commands. `chargingDecision` and `chargingDecisionInternal` are public convenience mappings of the corresponding raw code readings and retain `unknown:<code>` for unmapped values. The Internal `VERSION` reports the module version; wallbox firmware remains separate in `firmwareVersion`. `chargingDecisionCode` and `chargingDecisionInternalCode` retain the raw device values, while `chargingDecision` and `chargingDecisionInternal` expose a documented compatibility text mapping with explicit `unknown:<code>` fallbacks. The exact relationship and precedence between `modelStatus` and `msi` are not confirmed for Wattpilot Flex; the repository does not describe them as a proven final-decision/pre-decision pipeline.

Old 1.x public names appear only in explicit breaking-change or historical mapping sections. Version 2.0 provides no aliases or automatic migration for them.

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
