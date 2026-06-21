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
- Keep diagnostics useful while protecting credentials, authentication material, device identifiers, and private endpoint data.

## Framework side-effect audit

Before implementation or approval, inventory every called FHEM or Perl framework function that can affect the requested behavior. This includes lifecycle callbacks, `DevIo_*`, timer helpers, logging, attribute access, persistence helpers, and metadata helpers.

For every relevant external function:

- inspect the current implementation or current authoritative documentation;
- check logging, return values, retries, buffering, state changes, timers, persistence, cleanup, privacy handling, and error propagation;
- follow transitive behavior instead of reviewing only the module wrapper;
- record the inspected source revision in the PR description or review notes;
- repeat the inspection when the relevant framework source may have changed.

A safety or correctness statement must cover the complete runtime call chain. A module-level test is insufficient when a called framework function can independently log data, alter state, retry operations, suppress errors, or schedule work.

## Connection and authentication lifecycle

For every change involving networking, authentication, credentials, timers, reconnects, enable/disable behavior, rename, delete, reload, or shutdown, review the complete lifecycle together:

- `Wattpilot_Define`
- connection setup and `Wattpilot_Connect`
- `ReadyFn` and reconnect behavior
- `Wattpilot_Read` and `Wattpilot_Parse`
- authentication challenge, success, and error paths
- attribute-driven disable/enable behavior
- credential and authentication-attribute changes
- timers and delayed callbacks
- `Wattpilot_Undefine`
- `DeleteFn`, `RenameFn`, and shutdown-related cleanup where applicable

Requirements:

- Do not create duplicate connections or duplicate reconnect timers.
- Disabled, undefined, deleted, renamed, or shutting-down devices must not continue reconnecting or processing stale delayed callbacks.
- Undefine and shutdown-related paths must remove timers and close DevIo connections where applicable.
- Authentication failures must not leave the device falsely marked as connected.
- Persistence failures must not silently leave partially updated or conflicting state.
- Normal operation, tests, fixtures, issues, documentation, and releases must not expose sensitive credentials, authentication data, device identifiers, private endpoints, or unsanitized captures.
- The sole runtime exception is the explicitly enabled diagnostic mode requiring both device attributes `rawJsonLog=1` and `verbose=5`. It may log exact inbound and outbound JSON, including authentication and `securedMsg` frames, must warn when activated, must never activate automatically, and its output must be sanitized before reuse anywhere else.
- Tests and fixtures must use minimal synthetic values and documentation address ranges.

## Test-double fidelity

Test stubs and mocks must reproduce every real framework behavior that is relevant to the property being tested.

- Derive relevant stub behavior from the current FHEM source or authoritative documentation.
- A no-op or simplified stub must not be used to prove a property that depends on omitted logging, return values, state transitions, retries, buffering, timers, persistence, or cleanup.
- When a framework helper has a relevant side effect, model it in the stub or test an equivalent integration boundary.
- Safety tests must include indirect framework behavior, not only actions generated directly by `72_Wattpilot.pm`.
- Add a negative control where practical to demonstrate that the test fails when the known unsafe behavior is present.
- Keep the source revision behind framework-derived test behavior visible in the test code or testing documentation.
- Green tests built around weaker-than-real stubs are not sufficient evidence.

## Adversarial completion review

Before declaring a task complete, perform a separate review whose goal is to disprove the implementation and the PR claims.

At minimum:

1. Re-read the issue, `AGENTS.md`, and the complete diff independently of the implementation plan.
2. Trace success, failure, retry, partial-success, cleanup, reload, rename, delete, disable, and shutdown paths where relevant.
3. Inject or reason through failures for every external I/O, persistence, timer, authentication, parsing, and cleanup operation.
4. Look specifically for indirect data exposure, stale persistent values, mixed old/new state, failed rollback, duplicate timers or connections, callbacks after cleanup, ignored return values, incorrect unknown-state handling, and tests weakened by incomplete stubs.
5. Compare every broad statement in the PR description with what the code and tests actually prove.
6. Compare all relevant framework calls against the current FHEM source.
7. State remaining assumptions, uncertainty, and unperformed integration tests explicitly.

Implementation and adversarial review are separate activities. Tests that merely mirror the implementation are not a substitute for attempting to falsify it.

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
- realistic framework-side-effect coverage for the properties under test
- failure injection for persistence, logging, timers, connection, and cleanup where relevant
- strict embedded META and `CPAN::Meta` validation
- English and German commandref blocks
- fixture privacy and JSON validity
- UTF-8 and mojibake detection
- MANIFEST and internal SHA-256 sums
- ZIP integrity and external ZIP checksum
- byte equality of root, standalone, packaged, and ZIP-contained module copies
- semantic version consistency
- deterministic release output

Do not claim that stub tests replace real integration tests. Every PR or release summary must explicitly state which real FHEM, Wattpilot, network, WebSocket, authentication, persistence, rename, reload, delete, reconnect, command, and live-reading tests were not performed.

## Git workflow

- Work on a branch named `codex/<short-description>` unless the maintainer explicitly requests a direct commit.
- Keep changes focused and reviewable.
- Do not commit generated files below `dist/`.
- Open a draft pull request unless explicitly asked for a ready PR or direct commit.
- The PR body must explain what changed, why it changed, user impact, validation performed, artifact checksums when relevant, and unperformed integration tests.
- For changes involving FHEM framework behavior, the PR body must list the inspected framework functions, source revision, relevant side effects, and how tests model them.
- Do not claim a safety or lifecycle property unless the complete call chain and relevant failure paths are covered by review and tests.
- Do not rewrite published history or force-push shared branches without explicit maintainer approval.
