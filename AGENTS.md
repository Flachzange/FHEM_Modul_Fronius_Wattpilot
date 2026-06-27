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
- Version 2.x redesign and implementation: Flachzange
- Development assistance for version 2.x: OpenAI ChatGPT (AI-assisted design, implementation, review, testing, and documentation; technical decisions and release responsibility remain with the maintainer)
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
- Public readings that expose stored or user-selectable configuration use the exact camel-case prefix `config`, for example `configChargingMode`. Read-only configuration values use the same prefix as writable configuration values. Effective runtime limits, live status, telemetry, lifecycle state, identity, and diagnostics must not be prefixed merely because they are related to configuration.
- Use `SoC` consistently in public identifiers for state of charge; do not spell out `StateOfCharge` in reading or command names.
- Related stationary-PV-battery writes use the grouped top-level Set command `pvBattery` with explicit subcommands rather than separate top-level Set commands.
- Phase-switch mode/timing writes use `phaseSwitch mode|delay|minInterval|threePhasePower`; minimum-charging timing writes use `minimumCharging duration|interval|pauseDuration`. Do not reintroduce the seven former individual top-level Set commands or compatibility aliases.
- `chargingCurrent` uses a usable device-confirmed `configMaximumCurrentLimit` from 6 through 32 as its local upper bound and FHEMWEB slider maximum. Missing, stale, malformed, non-integer, or out-of-range values fall back to 32. Do not add `configMinimumChargingCurrent` or `temperatureCurrentLimit` to this validation without separate evidence and an explicit issue.
- At the current experimental development stage, public-interface changes do not provide migration code, compatibility aliases, duplicate old/new readings, automatic DbLog conversion, or transition periods. Breaking reading-name changes are documented and consumers must be adapted explicitly.
- Treat new readings and commands as user-facing API changes that require documentation and tests.
- Public measured or calculated physical values use exactly two decimal places with trailing zeroes. A value that rounds to negative zero is published as positive zero. Exceptions are limited to explicitly documented booleans, integer codes, enums, counters, clocks, durations, percentages, and intentionally integral settings. The authoritative reading inventory records the formatter for every public reading.
- Straightforward consumed status fields and ordinary one-value Set commands must use the existing declarative reading/command inventories. Keep lifecycle, authentication, request correlation, telemetry caches, car transitions, `password`, `reconnect`, and grouped-command logic explicit; do not introduce a generic framework that obscures those special paths.
- Prefer reuse, extension, and consolidation of existing code paths over adding new helpers or parallel implementations. Before introducing a new function, inspect whether the behavior belongs in an existing function, declarative schema, lifecycle path, or shared helper.
- Do not append narrowly scoped functions merely to avoid adapting the existing architecture. A new function must represent a genuinely distinct responsibility and must not duplicate validation, state handling, transport, formatting, cleanup, or error handling already present elsewhere.
- When a scoped change reveals duplicated or overlapping logic, consolidate it where this can be done safely and reviewably. The PR description must justify every newly introduced function whose responsibility overlaps an existing path.
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

## Framework callback sequences and state lifetime

Do not validate FHEM callbacks only as isolated functions. Inspect and test the actual framework-level invocation sequence, including what happens when a later callback fails after an earlier callback has already changed runtime state.

For lifecycle changes, reproduce the relevant command-level sequences from current FHEM source, including where applicable:

- define and modify;
- rename;
- `rereadcfg` and module reload;
- disable and enable;
- disconnect and reconnect;
- `UndefFn` followed by `DeleteFn`;
- failure of `DeleteFn` after successful `UndefFn`;
- shutdown and restart.

### Reload safety as a 2.x compatibility goal

Within the supported 2.x line, updating from one 2.x version to a later 2.x version with `reload 72_Wattpilot` should normally be safe without restarting FHEM or deleting and redefining the device. Treat this as a design and review goal for every change, not as an automatic claim that has been proven for all future versions.

A reload-safe change must, as applicable:

- preserve the existing definition, FUUID-owned credentials, attributes, and user-visible configuration;
- ensure that old WebSocket, DevIo, authentication, command, JSON, timer, and reconnect state cannot continue operating beside the newly loaded code;
- leave at most one active connection attempt, one live session, and one timer per timer kind;
- reject or harmlessly ignore delayed callbacks created by the previous module generation;
- tolerate helper-state shapes from the previous supported 2.x version, or explicitly invalidate and rebuild incompatible transient state before it is used;
- avoid requiring a manual disable/enable cycle, device redefinition, `rereadcfg`, or FHEM restart merely to activate the new code;
- retain existing readings unless the scoped change intentionally replaces or removes them and documents that public-interface change.

Any change to callback registration, helper structures, timers, DevIo state, connection setup, authentication, request correlation, buffering, persistence, or cleanup must include an explicit reload-impact analysis. Tests must model the actual FHEM module-reload sequence from a pinned current FHEM source revision and must begin with a realistically active pre-reload device state, including an open or opening connection and pending timers where relevant. The post-reload assertions must cover stale-callback rejection, connection/timer uniqueness, preserved credentials and configuration, and successful return to a coherent lifecycle state.

A stub-only test does not prove real reload safety. PR and release notes must state whether a real FHEM 2.x-to-2.x reload test was performed. If a change cannot reasonably preserve reload safety, treat that as an explicit compatibility exception requiring maintainer approval, clear upgrade instructions, and consistent documentation before merge.

If FHEM retains a device after a callback error, the module must leave or restore that device to a coherent and usable runtime state. Tests that invoke only the final callback are insufficient.

### Callback return-value semantics

A callback return value is not error handling unless the real framework caller consumes and propagates that value.

- Inspect the command-level caller to determine whether the callback result is returned, transformed, logged, or discarded.
- Account for framework mutations that occur before the callback is invoked and remain in effect when its return value is ignored.
- A direct unit test that calls the callback and asserts its return value is insufficient when the real framework caller ignores or changes that result.
- If the framework does not propagate a callback failure, correctness must be achieved through coherent module state, durable retry information, rollback where possible, or a design that does not depend on the ignored return value.

For every new internal state value, explicitly classify its required lifetime:

- local operation only;
- current device-hash lifetime;
- current FHEM-process lifetime;
- persistent across `rereadcfg`, reload, rename, and restart.

Do not store information only in `$hash->{helper}` when correctness, retry, cleanup, rollback, or ownership depends on that information surviving recreation of the device hash or the FHEM process.

A retry promise must be tested across the longest lifetime claimed by the implementation and documentation. Where persistence is required, test recreation with a new device hash and the same FUUID rather than reusing the original hash.

### Stable ownership of persistent resources

Mutable identifiers such as device names are locators, not durable proof of ownership.

- Persistent migration, cleanup, rollback, overwrite, or deletion must use or verify a stable owner identity such as the FUUID.
- Remembering a former device name alone is not sufficient authorization to read, migrate, overwrite, or delete data found under that name.
- When ownership cannot be proven, do not modify the resource; preserve it and surface an explicit error or unresolved state.
- Ownership metadata must survive every lifecycle boundary for which later cleanup or retry is promised.
- Tests must cover reuse of the old identifier by a different object with a different stable identity.
- Test both recreation orders: the original object first and the replacement object first.
- Prove that getters, migration, credential updates, rollback, and deletion cannot adopt or destroy resources owned by the replacement object.

For the 2.0 clean-install line, Wattpilot credentials are FUUID-only. Runtime code must not read, claim, migrate, overwrite, or delete device-name-based password/hash keys, legacy owner-marker keys, or pending legacy-name metadata. Released 1.6.x versions are the final releases that support the old name-based upgrade path. Version 2.0 requires a fresh definition and a new password operation, and obsolete name-based resources are deliberately left untouched.

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
- External reads must distinguish success with a value, success without a value, and failure.
- Do not collapse an I/O, persistence, parsing, integrity, or permission error into an absent configuration value.
- Preserve the read-error distinction through caller return values, readings, logs, retry decisions, and control flow. A storage failure must not be reported as a missing password or other missing configuration.
- Add failure-injection tests at every relevant caller, not only at the low-level storage helper.
- Normal operation, tests, fixtures, issues, documentation, and releases must not expose sensitive credentials, authentication data, device identifiers, private endpoints, or unsanitized captures.
- The sole runtime exception is the explicitly enabled diagnostic mode requiring both device attributes `rawJSONLog=1` and `verbose=5`. It may log exact inbound and outbound JSON, including authentication and `securedMsg` frames, must warn when activated, must never activate automatically, and its output must be sanitized before reuse anywhere else.
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

## Requirement closure and external limitations

Separate module-controlled behavior from behavior owned by FHEM core or another dependency.

- Do not claim a requirement is fully satisfied when a relevant transitive framework path remains outside the module's control.
- Qualify statements precisely, for example “Wattpilot-generated logs are redacted” instead of “logs contain no private endpoints” when FHEM core may still expose them.
- Record unresolved external limitations in a dedicated issue when they affect a stated requirement.
- Do not use `Closes #<issue>` unless every acceptance criterion is satisfied or the issue has been explicitly narrowed by the maintainer.
- Changelog, README, commandref, tests, and PR text must describe the same limitation consistently.
- An adversarial review must search for contradictions between broad user-facing claims and narrower implementation guarantees.

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
