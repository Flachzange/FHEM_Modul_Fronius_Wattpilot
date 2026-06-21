# AGENTS.md — Wattpilot

This repository contains the FHEM module `Wattpilot` for local communication with a Fronius Wattpilot wallbox.

## Source of truth

- The only authoritative runtime source is `72_Wattpilot.pm` in the repository root.
- Never use generated versioned module copies, ZIP files, old releases, chat transcripts, or previous branches as source-code references.
- Generated release artifacts belong in `dist/`; do not edit them manually or commit them.
- Before changing code, inspect the current root module and follow every affected control path completely.
- `docs/PROTOCOL-SOURCES.md` is the authoritative provenance register for protocol claims. `API.md` is a historical compilation and must not silently be treated as current official documentation.

## Project identity

- Module type: `Wattpilot`
- File: `72_Wattpilot.pm`
- Initialize callback: `Wattpilot_Initialize`
- Global subroutines use the `Wattpilot_` prefix.
- License: GPL-2.0-or-later
- Original author: Dennis Gramespacher
- Repository maintainer: Flachzange
- Release status: testing / experimental
- Embedded META is registered through `FHEM::Meta::InitMod`.

## Protocol evidence rules

1. Do not speculate about Wattpilot or FHEM behavior.
2. Clearly separate verified facts, empirical observations, third-party interpretations, assumptions, and open questions in code reviews and documentation.
3. A field name, third-party alias, example value, or existing implementation does not by itself prove semantics or writability.
4. Add or modify a set command only when writability, accepted values, and units are supported by an explicit source or a reproducible device test.
5. Official go-e documentation is evidence for go-e devices only; it is not automatically official Fronius Wattpilot documentation.
6. Pin online source references to a concrete commit or tag where practical and record the date checked.
7. Missing keys in `deltaStatus` represent an absent partial update and must never delete or reset existing readings.
8. Do not silently turn unknown protocol states into a known state. Preserve uncertainty through explicit fallbacks, errors, or logs as appropriate.
9. Any new protocol claim must update `docs/PROTOCOL-SOURCES.md` with its confidence class and limitations.

## FHEM engineering rules

- Verify uncertain FHEM behavior against the current FHEM commandref or current FHEM source.
- Do not invent attributes, readings, callbacks, DevIo behavior, or module mechanisms.
- Prefer explicit documented interfaces over hidden or implicit behavior.
- Keep existing public readings, set commands, attribute names, and command semantics stable unless the scoped issue explicitly changes them.
- Treat new readings and commands as user-facing API changes that require documentation and tests.
- Preserve the `Wattpilot_` callback prefix and keep callback registration consistent with current FHEM conventions.
- Do not add runtime dependencies without documenting them in META and testing their availability in CI.
- Keep diagnostics useful but do not expose secrets or unnecessarily duplicate public state.

## Connection and authentication lifecycle

For every change involving networking, authentication, timers, reconnects, enable/disable behavior, or shutdown, review the complete lifecycle together:

- `Wattpilot_Define`
- connection setup and `Wattpilot_Connect`
- `ReadyFn` and reconnect behavior
- `Wattpilot_Read` and `Wattpilot_Parse`
- authentication challenge, success, and error paths
- attribute-driven disable/enable behavior
- timers and delayed callbacks
- `Wattpilot_Undefine`

Requirements:

- Do not create duplicate connections or duplicate reconnect timers.
- Disabled or undefined devices must not continue reconnecting or processing delayed callbacks.
- Undefine and shutdown-related paths must remove timers and close DevIo connections where applicable.
- Authentication failures must not leave the device falsely marked as connected.
- Never log or commit passwords, password hashes, authentication material, serial numbers, MAC addresses, private IP addresses, signed URLs, or unsanitized device captures.
- Tests and fixtures must use minimal synthetic values and documentation address ranges.

## Change completeness

Every user-visible behavior change must update all relevant artifacts:

- `72_Wattpilot.pm`
- English commandref
- German commandref
- central source version and embedded META
- `CHANGELOG.md`
- automated tests
- README and testing documentation where relevant
- `docs/PROTOCOL-SOURCES.md` when protocol fields, meanings, units, enums, or writability are affected

Do not bump the module version for analysis-only, test-only, or documentation-only work unless the documented current version itself is being corrected.

Version representations describe the same semantic version but intentionally use different formats:

- source constant: `x.y.z`
- embedded META: `vx.y.z`
- changelog heading and release artifact names: corresponding `v`-prefixed version

All representations must be kept consistent and validated automatically.

## Tests and release completeness

Run at minimum:

```sh
scripts/ci.sh
```

Before publishing or reviewing release artifacts, also run:

```sh
scripts/build-release.sh
scripts/check_reproducible_release.sh
```

The automated checks must cover, as applicable:

- Perl syntax and module loading with stubs
- the complete test suite
- callback registration and global subroutine structure
- strict embedded META and `CPAN::Meta` validation
- English and German commandref blocks
- fixture privacy and JSON validity
- UTF-8 and mojibake detection
- MANIFEST and internal SHA-256 sums
- ZIP integrity and external ZIP checksum
- byte equality of root, standalone, packaged, and ZIP-contained module copies
- semantic version consistency
- deterministic release output

Do not claim that stub tests replace real integration tests. Every PR or release summary must explicitly state which real FHEM, Wattpilot, network, WebSocket, authentication, reconnect, command, and live-reading tests were not performed.

## Git workflow

- Work on a branch named `codex/<short-description>` unless the maintainer explicitly requests a direct commit.
- Keep changes focused and reviewable.
- Do not commit generated files below `dist/`.
- Open a draft pull request unless explicitly asked for a ready PR or direct commit.
- The PR body must explain what changed, why it changed, user impact, validation performed, artifact checksums when relevant, and unperformed integration tests.
- Do not rewrite published history or force-push shared branches without explicit maintainer approval.
