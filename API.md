# Wattpilot API documentation

This file is the stable entry point for the repository's JSON/WebSocket API documentation.

## Current empirical Flex reference

Use [`docs/WATTPILOT-FLEX-JSON-API.md`](docs/WATTPILOT-FLEX-JSON-API.md) for the sanitized observation from a Wattpilot Flex Home 22 C6 with firmware 43.4 and protocol 4. It is authoritative only for the observed key presence, nesting, array shape, JSON types, and sanitized representative values in that capture.

## Field names and description candidates

Use [`docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md`](docs/WATTPILOT-FLEX-FIELD-DESCRIPTIONS.md) as a companion lookup for readable aliases, titles, description candidates, unit candidates, enum candidates, categories, and historical read/write claims.

Those descriptions are retained from the former root `API.md` compilation. They are **historical candidates**, not confirmed Wattpilot Flex facts. Always cross-check them against the empirical Flex reference and the evidence notes in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md).

## Evidence rule

No document in this repository is an official Fronius API specification. A historical alias, a go-e description, current FHEM behavior, or a third-party implementation does not by itself establish field meaning, unit, enum semantics, requiredness, or writability for Wattpilot Flex.

When sources conflict, the conflict must remain visible rather than being silently resolved.
