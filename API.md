# Wattpilot API documentation

This file is the stable entry point for the repository's JSON/WebSocket API documentation.

## Protocol profiles

The original Wattpilot generation is covered by the evidence-qualified regression contract in [`docs/WATTPILOT-LEGACY-PROTOCOL2.md`](docs/WATTPILOT-LEGACY-PROTOCOL2.md). Its compact synthetic fixture is [`t/fixtures/legacy-protocol2-session.json`](t/fixtures/legacy-protocol2-session.json). The Flex generation is documented separately below. Neither document is an official Fronius specification.

## Pure sanitized JSON example

The complete sanitized `fullStatus` capture is available as a standalone JSON file:

[`t/fixtures/fullStatus-flex-observed.json`](t/fixtures/fullStatus-flex-observed.json)

It contains the complete observed message wrapper and all 558 direct `status` keys from the documented Wattpilot Flex Home 22 C6 capture. Identifiers, network coordinates, authentication material, exact operational counters, market data, and installation-specific labels were replaced while preserving the key set, nesting, array lengths, null positions, JSON scalar types, and representative values.

This fixture is the single canonical JSON copy used both by the documentation and automated tests. It should not be duplicated under another path, because two independently editable copies could drift apart.

## Current empirical Flex reference

Use [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md) for the sanitized observation from a Wattpilot Flex Home 22 C6 with firmware 43.4 and protocol 4. It is authoritative only for the observed key presence, nesting, array shape, JSON types, and sanitized representative values in that capture.

## Field names and description candidates

Use [`docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md`](docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md) as a companion lookup for readable aliases, titles, description candidates, unit candidates, enum candidates, categories, and historical read/write claims.

Those descriptions are retained from the former root `API.md` compilation. They are **historical candidates**, not confirmed Wattpilot Flex facts. Always cross-check them against the empirical Flex reference and the evidence notes in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md).

## Evidence rule

No document in this repository is an official Fronius API specification. A historical alias, a go-e description, current FHEM behavior, or a third-party implementation does not by itself establish field meaning, unit, enum semantics, requiredness, or writability for Wattpilot Flex.

When sources conflict, the conflict must remain visible rather than being silently resolved.
