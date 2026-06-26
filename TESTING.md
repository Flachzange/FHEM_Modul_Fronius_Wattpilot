# Testing

Development and release checks require Perl, `IO::Compress::Zip`, `CPAN::Meta`, `JSON`, `Crypt::PBKDF2`, `Crypt::URandom`, and `Crypt::Bcrypt`, plus the standard `prove`, `sha256sum`, `zip`/`unzip`, and POSIX shell tools. On Debian or Ubuntu, `IO::Compress::Zip` is provided by `libio-compress-perl` when it is not already included with the Perl installation. `Crypt::Bcrypt` remains optional at runtime for installations that use only PBKDF2, but its deterministic vector runs whenever it is installed.

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with controlled FHEM/DevIo stubs, validates callback registration and global subroutine structure, and models the audited FHEM `CommandRename` mutation sequence including the discarded `RenameFn` reply. Credential tests cover stable FUUID-only reads, tri-state storage results, two-key password replacement, transactional deletion and rollback, the real `UndefFn`→`DeleteFn` failure sequence, retained-device runtime restoration, and preservation across undefine, reload, rename, disable, and restart. Negative controls seed old name-based, owner-marker, and pending-list resources and prove through the key-value operation log that Define, getters, Rename, password changes, and Delete never read or modify them. The suite also reproduces DevIo level-5 payload logging and transitive HttpUtils URL, DNS/IP, error, timeout, callback, initial-connect, and reconnect effects; exercises redacted and explicitly enabled raw JSON logging; parses META and both command-reference languages; validates fixtures; and checks repository structure.

`t/legacy_protocol2.t` and `t/fixtures/legacy-protocol2-session.json` additionally protect the established predecessor-device behavior: the historical PBKDF2 selection when the challenge has no algorithm field, split status initialization, unchanged readings for omitted partial fields, the twelve-value electrical array, continued processing of the sixteen-value Flex array, secured command wrapping, and response correlation. The fixture is synthetic and is not device evidence.

`t/protocol_input_hardening.t` adds deterministic synthetic PBKDF2, bcrypt serial-salt, authentication-response, canonical secured-JSON, and HMAC vectors. It rejects scalar/array top levels, missing or invalid message fields, wrong decoded JSON kinds, numeric-string and boolean-surrogate coercion, unsafe clock values, malformed status data, invalid electrical arrays, malformed/oversized decoded input, and mixed valid/malformed batches. It verifies bounded completion of syntactically incomplete JSON across decoded returns, strings containing braces, `}{`, escapes, and newlines, multiple concatenated JSON objects, redacted unknown messages, persistence failures, and transient-auth cleanup across disconnect, partial raw-frame returns, disable, password change, authentication error, undefine, delete, and reconnect. `t/pr29_review_fixes.t` additionally enforces the 256-document batch limit with atomic rejection, distinguishes actual JSON strings from numbers, booleans, nulls, arrays, and objects, requires explicit hash-mode selection before derivation, and verifies that changing or deleting `authHash` closes and invalidates the old session, removes stale timers, leaves exactly one controlled reconnect, and blocks stale secured commands.

`t/public_interface_2_0.t` exercises one complete runtime reading scenario and requires exactly the 73 public 2.x readings, no old reading events, every known enum mapping, and explicit `unknown:<raw-value>` fallbacks. `t/public_interface_guard.t` rejects exact old public reading, command, enum, and lifecycle strings in executable runtime, active tests, both READMEs, and both embedded commandref languages. Historical 1.x names are permitted only inside balanced, explicitly marked migration blocks or the marked negative-control block that proves the old Set commands are rejected. The same guard requires every active user document to contain all 73 readings and all 15 set commands, and requires each marked migration matrix to contain exactly the 23 historical reading mappings and five Set-command mappings.

`t/architecture_characterization.t` also guards the version-2.0.7 reading classification. It requires every public reading to have exactly one category, every `configuration` reading to use `^config[A-Z]`, every non-configuration reading to remain outside that prefix, and the Set-command surface to retain its unprefixed names. `docs/READING-CATEGORIES.md` is the human-readable audit corresponding to that executable contract.

`t/pv_battery_settings.t` protects the version-2.0.9 grouped setter implementation for issue #52. It loads a minimal sanitized fixture derived from one simultaneous Flex 43.4 app/status observation, verifies the six exact `configPvBattery...` names, checks fullStatus and deltaStatus updates, preserves existing readings for missing, null, type-invalid, out-of-range, and non-minute clock values, and covers `00:00` and `24:00` read boundaries. It additionally proves that exactly one top-level `pvBattery` command is exposed, validates all six subcommands, exact protocol keys and JSON types, strict percentage and clock syntax, no write for invalid input, no optimistic reading update, successful status confirmation, and unchanged confirmed readings after a failed response.

`t/idle_connection_lifecycle.t` covers the lifecycle behavior introduced in version 1.6.0 and tightened in version 2.1.5, using deterministic synthetic time. It verifies both `update_while_idle` values, the bounded Charging-to-Idle refresh even when ordinary idle telemetry is disabled, transition-message and grace-window `nrg`, one rate-limit bypass, authoritative zero values, unchanged readings for missing `nrg`, exactly one refresh reconnect per idle episode, attribute changes that neither duplicate nor cancel an active episode, and re-arming only after a later charging phase. It also covers authentication and initialization timeouts, the first valid authenticated partial `fullStatus` as initialization completion, malformed and pre-authentication status rejection, stale timeout suppression, ordinary EOF with DevIo ReadyFn/`DevIoJustClosed` ownership, ownerless WebSocket Close with one module reconnect, repeated-close deduplication, stale reconnect suppression after disable, asynchronous-open ownership, and synchronous ShutdownFn cleanup.

`t/nrg_rate_limit_regression.t` protects charging and idle electrical telemetry on the shared telemetry clock. It covers both `update_while_idle` values, exact interval boundaries, `interval=0`, current car-state ordering, fullStatus, deltaStatus, matched-response paths, invalid/incomplete arrays, and the bounded one-shot charging-to-idle refresh plus reconnect fallback. It explicitly proves that diagnostic or configuration input neither republishes cached electrical values nor starves the next fresh `nrg` publication.

`t/operational_status_readings.t` covers the operational status readings introduced through version 2.0.4, including the two text decisions added in version 2.0.3 and the `fst`-backed configuration reading now named `configPvSurplusStartPower`. It exercises the sanitized observed Flex fullStatus fixture, device-supplied false and zero values, partial delta updates, `null` omission semantics, field-by-field type rejection, and updates while electrical readings are rate-limited or idle-suppressed. It requires raw integer preservation for `modelStatus`, `msi`, and `err`, complete known decision mappings, stable `unknown:<code>` fallbacks, and preservation of both code and text readings across omitted, `null`, and type-invalid deltas.

`t/pv_battery_diagnostics.t` covers the version-2.1.7 raw diagnostic publication of `fbuf_akkuSOC` and `fbuf_pAkku`. It verifies fullStatus, deltaStatus, and matched-response handling; two-decimal numeric formatting plus unchanged string and `0|1` boolean publication; rejection of `null`, objects, and arrays; the common diagnostic idle gate and interval owner; immediate cleanup when diagnostics are disabled; the deliberate absence of the former standalone SOC/power readings; and continued immediate-on-change publication of `pvBatteryModeCode`. It also proves that the diagnostic owner cannot republish cached electrical values and that `interval=0` disables rate limiting for eligible diagnostics.


`t/reading_update_policy.t` is the authoritative publication-policy regression. It verifies one shared `telemetry_flush` timer, one common interval boundary, same-transaction timestamps across eligible dirty owners, separate caches/dirty fields without cross-owner starvation, change-only energy publication, both idle-gate settings, exact-boundary and `interval=0` behavior, positive-to-zero and deleted-attribute immediate flushes, positive-to-positive timer replacement for dirty telemetry, publication at the new boundary without further status input, repeated-change timer uniqueness, lazy no-dirty behavior, preservation of ineligible idle `nrg`/uptime/diagnostic dirty state, stale-callback rejection, session cleanup, immediate-on-change discrete readings, immediate device-confirmed configuration, and complete policy-inventory exposure.

`t/pv_surplus_start_power.t` covers issue #43 end to end: `fullStatus` and `deltaStatus` parsing, missing/`null`/negative/wrong-type/overflow preservation, finite non-negative setter validation, secured `fst` request encoding, no optimistic reading update, successful device-confirmed updates, failed responses, successful responses without `fst`, and type-invalid response status.

`t/energy_controls.t` covers issue #44 end to end for `fup`, `fzf`, `frm`, `psm`, `spl3`, `mpwst`, `mptwt`, `fmt`, `fap`, `mcpd`, and `mci`: full and partial status parsing, strict JSON-boolean handling, enum fallbacks, watt and millisecond/second conversions, secured setter encoding, invalid/negative/non-finite input rejection, no optimistic updates, device-confirmed responses, rejection handling, and public command discovery.

`t/manual_reconnect.t` covers issue #47 as a local lifecycle operation: connected, disconnected, failed, connecting/open-in-flight, and authenticating states; typed-timer cleanup; pending-command termination; partial-JSON/authentication cleanup; preserved operational readings and configuration; repeated rapid commands; disabled, missing-credential, storage-error, undefined, deleting, and shutdown states; stale asynchronous DevIo callbacks; exactly one replacement connection; and the device-supplied initial-status path after re-authentication. The test does not claim a Wattpilot `fullStatus` request exists.

`t/command_semantics.t` additionally protects the version-2.0.10 Set-list cleanup from issue #56. It verifies one central option list, the exact `reconnect:noArg` widget metadata, identical discovery output for enabled and `disable=1` devices, absence of the former spurious FHEMWEB entries `module`, `disabled`, and `is`, continued rejection of actual commands while disabled, and exact argument counts for every previously permissive single-value Set command.

`t/runtime_fixes_2_0_3.t` protects the version-2.0.3 corrections. It proves that `eto` and `wh` update while an idle `nrg` group is suppressed, that enabling `update_while_idle` still admits the real measurement array, that Define and reload-style Initialize expose the module version without lifecycle side effects, that a device `hello.version` updates only `firmwareVersion`, that `hello.protocol` remains distinct from `status.proto`, that the empirically observed startup types `clearInverters`, `updateInverter`, and `clearSmips` remain level-4-visible but produce no level-3 unsupported warning, and that all other unsupported message types produce useful but bounded/redacted diagnostics without payload logging.

The reload test models `CommandReload` from FHEM mirror revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b`: FHEM executes the module file and invokes the module Initialize function while existing device hashes remain in `%defs`. The test therefore begins with existing Wattpilot and unrelated device hashes and requires Initialize to refresh only the Wattpilot `VERSION` Internal, without maintaining an unused module `defptr` registry.

A real-device reproduction was performed on 2026-06-24 before implementation of the fix: a fresh FHEM definition using module 2.0.2 authenticated via bcrypt to a Wattpilot Flex with firmware 43.4. At `carState=complete`, setting `update_while_idle=1` and reconnecting caused the initial status to populate `energyTotal=780.60`, `energySincePlugIn=6730.00`, approximately 231 V on all phases, and zero current/power. With the default idle setting, those energy readings had been absent. The helper showed `protocol=2` while the sanitized fullStatus reference contains `status.proto=4`. This reproduces the old gating defect and the field distinction.

A post-fix real-device test on the same date loaded module 2.0.3, exposed Internal `VERSION=2.0.3` and reading `firmwareVersion=43.4`, authenticated via bcrypt, processed live charging values, and logged the startup type sequence `fullStatus`, `clearInverters`, `updateInverter`, `updateInverter`, `clearSmips`, followed by `deltaStatus`. No payloads for the three unused startup messages were retained, so only their type names and observed order/count are evidence. The post-fix test did not yet exercise the corrected idle-energy path with `update_while_idle=0`.

`t/fhem_interface_validation.t` protects the release-facing FHEM interface. Its command-level doubles are pinned to FHEM mirror revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b`. They model `CommandAttr`, where `AttrFn` runs before framework storage, and `CommandModify`, where FHEM sets `OLDDEF`, replaces `DEF`, and invokes `DefFn` on the existing hash. The tests require the absence of an empty `GetFn` and the removed no-op attributes, exercise all remaining attribute boundaries, and prove side-effect-free rejection. They cover connected, unchanged, invalid, disabled, and deferred-open definition changes, exact old-context closure, pending-command termination, stale-callback rejection, and one resulting reconnect.

State lifetime is explicit and documented in `ARCHITECTURE.md`. Connection-scoped protocol, authentication, command, and JSON state is cleared at session boundaries; lifecycle generation and request sequencing remain device-hash state. Idle-refresh state is handled separately because its reconnect-awaiting flag deliberately survives the single refresh reconnect. The password and derived signing key remain FUUID-owned persistent values.

Framework-derived DevIo, reading, and command/timer stub behavior was re-audited against FHEM mirror revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b`. The inspected paths include `CommandSet`, `DoSet`, `readingsBeginUpdate`, `readingsBulkUpdate`, `readingsBulkUpdateIfChanged`, `readingsEndUpdate`, `InternalTimer`, `RemoveInternalTimer`, `DevIo_DoSimpleRead`, `DevIo_SimpleRead`, `DevIo_DecodeWS`, `DevIo_OpenDev`, `DevIo_SimpleWrite`, `DevIo_CloseDev`, and `DevIo_Disconnected`, including the asynchronous `HttpUtils_Connect` path. The reading double models the pinned transaction timestamp and event behavior; an unchanged `readingsBulkUpdateIfChanged` value returns before timestamp or event mutation. `CommandSet` propagates SetFn errors and otherwise performs the normal set trigger unless the module already generated an event. `DevIo_DecodeWS` appends raw bytes to `.WSBUF`, returns an empty string until a complete frame exists, removes complete frames from that buffer, and concatenates payloads from further complete frames before returning. It records `FIN` but does not use it to accumulate a logical message across separately returned complete frames. A successful asynchronous `DevIo_OpenDev` updates the framework state to `opened` and triggers `CONNECTED` before invoking the module callback; the Wattpilot lifecycle guard must therefore close stale transports and explicitly restore `disabled`, `disconnected`, or the single pending-reconnect handoff instead of allowing a stale callback to overwrite the configured state. `DevIo_CloseDev` removes `.WSBUF`, the WebSocket marker, transport handles, file descriptors, partial state, ReadyFn/select registration, and reconnect timing. Disconnect closes, marks the device disconnected, registers ReadyFn polling, and triggers `DISCONNECTED`. The Wattpilot doubles model these relevant side effects, while module tests distinguish DevIo's raw-frame buffer from the bounded logical JSON continuation required when a fragmented message is returned across calls. The endpoint tests also retain the negative control demonstrating that DevIo `privacy=1` does not suppress the internal HttpUtils URL and DNS/IP logs.

Build and verify the release artifacts with:

```sh
scripts/build-release.sh
```

A direct build runs the source CI suite once, builds the artifact, and invokes artifact verification without recursively rerunning source CI. The authoritative maintained-file list is `scripts/release-files.txt`; build and verification both consume it and compare every listed file between the repository, package directory, and ZIP. Generated files remain below ignored `dist/`. Callers that have already completed source CI may set `WATTPILOT_SKIP_SOURCE_CI=1` explicitly.

Verify deterministic output with two builds from the same commit and the same `SOURCE_DATE_EPOCH`:

```sh
scripts/check_reproducible_release.sh
```

The check runs source CI once unless explicitly prevalidated, performs two build-only artifact generations with the same epoch, verifies both artifacts, and fails unless their ZIP SHA-256 digests are identical.

For the version-2.1.0 audit batch, the complete local suite passed with 22 test files and 2,867 tests. It adds exact FHEM modify/defmod lifecycle coverage, top-level fullStatus partial handling, exact JSON-kind validation, defensive clock validation, removal guards for the no-op attributes, bilingual commandref inventory checks, and release-manifest/CI checks. The isolated container used temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom`; they are not repository or release files. These tests remain deterministic stubs and sanitized fixtures; a pinned real-FHEM-core integration harness remains tracked separately.

Version 2.1.1 adds `t/reading_update_policy.t` and timestamp/event-aware FHEM reading stubs. The regression matrix covers separate `energy`, `nrg`, and `battery` caches/dirty fields on one shared clock, exact boundaries, `interval=0`, repeated battery-before-nrg ordering, same-transaction timestamps, no cross-owner stale-cache publication, change-only energy, immediate-on-change discrete readings, immediate internal `car`, immediate device-confirmed configuration, all four status-envelope paths, invalid/incomplete input, timer reset, and stale-callback rejection. The complete local suite passes with 23 test files and 2,880 tests. A real Wattpilot Flex charging test for the version-2.1.1 behavior remains mandatory before merge/release.

Version 2.1.2 adds `t/reading_precision.t`. It checks the central formatter inventory, exact trailing-zero strings, positive and negative rounding, negative-zero normalization, scientific numeric input, explicit percentage/integer/duration exceptions, all status-envelope paths, fresh initialization, and invalid-input preservation. The complete local suite passes with 24 test files and 2,886 tests. No real FHEM reload or real-device test was performed for this display-only formatting change; setter payloads and protocol values are unchanged.

Issue #67 is covered by `t/fhem_core_lifecycle_integration.t` and
`t/lib/FHEMCorePinned.pm`. The helper pins FHEM mirror revision
`0ae38bf79d19d8d598c065bf84b3990b33063c4b`, `fhem.pl` blob
`0c03b2989d2e5be6f019cfb07a6a3e53db62050b`, and `DevIo.pm` blob
`ce94276bb9d3e4963ebc514a93a86b442984e72f`. It executes the unchanged pinned
`DoSet`, `CommandDefine`, `CommandModify`, `CommandDefMod`, `CommandRename`,
`CommandDelete`, `CommandAttr`, `CommandDeleteAttr`, and `CommandReload`
function bodies. External network, timer, credential, reading, and log effects
remain deterministic adapters; a small namespace bridge is required because
the extracted functions live in the test helper rather than FHEM's `main`
package. Coverage includes define success and veto cleanup, defmod creation and
replacement, modify rollback, rename mutation order, UndefFn-before-DeleteFn,
attribute callback ordering and veto behavior, disabled-device Set discovery,
and an actual reload from a temporary `FHEM/72_Wattpilot.pm` path while an
existing device hash, endpoint, transport state, helper state, and stable
credential remain intact. No production-module line changes are required. The
complete local suite passes with 25 test files and 2,951 tests. This remains a
bounded core-path integration test, not a live FHEM process, real network, or
physical Wattpilot test.

Version 2.1.3 adds `t/declarative_schemas.t`. It checks that all 55 consumed
status fields derive their validators and reading mappings from the authoritative
reading inventory, that every immediate status reading executes its declared
formatter, and that the then-current public Set commands have one schema entry.
Ordinary one-value commands are exercised through schema-derived parser,
protocol-key, JSON-type, and exact-arity behavior; special handlers remain
explicit negative boundaries. Version 2.1.4 extends the same test with the two
ordered grouped-command schemas. It verifies the six exact subcommands,
protocol keys, millisecond conversion, enum mapping, strict arity, invalid-input
rejection, Set discovery, and removal of the seven former individual Set names.
No real device is required to establish the grouping itself because protocol
keys, payload values, and secured request handling are unchanged; a real-device
smoke test remains useful before release. The complete local suite passes with
26 test files and 3,060 tests. Complete CI and release checks remain required
before merge.

A documentation-only cleanup after the 2.1.4 implementation removes the
version-by-version changelog and the two migration matrices from the German and
English READMEs. The commandref retains the explicit historical migration
matrix. `t/public_interface_guard.t` now verifies the compact original-module
comparison, the legacy/Flex authentication distinction, the cryptographic role
of the serial number, and the absence of unescaped pipe characters inside code
spans in Markdown table rows. Both READMEs were additionally parsed with a GFM
table parser; all four tables in each file have consistent column counts. The
complete local suite passes with 26 test files and 3,006 tests. This is
documentation and test-guard work only; the module version remains 2.1.4.

Version 2.1.5 adds `t/charging_current_limit.t`. It verifies the dynamic
`chargingCurrent` upper bound from a device-confirmed
`configMaximumCurrentLimit`: 16 A accepts 16 and rejects 17/32 without an
outgoing frame, 32 A preserves the established range, and missing,
not-yet-confirmed, malformed, non-integer, below-range, and above-range values
fall back to 32. The test also checks the FHEMWEB slider, exact dynamic Usage
text, definition-session invalidation, and the absence of optimistic
`configChargingCurrent` updates.

The same version adds `t/session_command_finalization.t` and extends the
lifecycle, DevIo, and publication regressions for issues #80 through #84. The
DevIo stub is aligned with FHEM mirror revision
`0ae38bf79d19d8d598c065bf84b3990b33063c4b`: ordinary EOF invokes the
DevIo-owned disconnected/ReadyFn path and sets `DevIoJustClosed`, while a
WebSocket Close frame directly closes the transport and leaves no ReadyFn or
`NEXT_OPEN` owner. Tests prove that only the ownerless path gets a module timer,
that no closed callback enters authentication, and that stale or repeated
callbacks cannot create parallel opens. Pending commands are finalized for
connection loss, disable, credential changes, authentication abort, lifecycle
timeout, manual reconnect, and session replacement; late responses are ignored,
while undefine/shutdown suppress new diagnostics. Partial authenticated status,
the bounded Idle refresh with both attribute values, and immediate eligible
telemetry flush on effective `interval=0` are covered independently.

The complete local regression suite passes with 28 test files and 3,154 tests.
No running-FHEM, live-network fault-injection, or physical-device test was
performed for these 2.1.5 lifecycle/publication changes. They alter local FHEM
ownership and timing only and add no Wattpilot protocol field or writability
claim.

Version 2.1.6 extends the same deterministic attribute/timer regression for the
remaining positive-to-positive transition. It proves a replacement boundary
without later status input, exactly one timer across repeated changes, harmless
obsolete callbacks, preserved Idle gating, and lazy behavior when no owner is
dirty. This is local FHEM timer ownership only and adds no protocol claim. A
running-FHEM reload test and physical-device test were not performed for this
follow-up. The complete local suite passes with 28 test files and 3,154
tests, followed by META, command-reference, repository, UTF-8,
release-verification, and reproducibility checks. The isolated container used
temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and
`Crypt::URandom`; the fixed PBKDF2 vector passed, while the optional bcrypt
vector was skipped because `Crypt::Bcrypt` was unavailable. GitHub CI with the
declared dependencies remains required before merge.

For the version-2.0.5 development run, the complete suite passed with 18 test files and 2,498 tests. The isolated container did not contain the CPAN `JSON`, `Crypt::PBKDF2`, `Crypt::URandom`, or `Crypt::Bcrypt` packages, so that local run used temporary, external compatibility modules outside the repository. Those compatibility modules used `JSON::PP`, a real PBKDF2-HMAC-SHA512 implementation, `/dev/urandom`, and the system bcrypt implementation and passed the repository's fixed cryptographic vectors. They are not release files and do not replace the GitHub CI run with the declared dependencies.

For the version-2.0.6 development run after the issue-#51 correction, the complete suite passed with 20 test files and 2,650 tests. The isolated container again used temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom`; the fixed PBKDF2 vector passed. `Crypt::Bcrypt` was unavailable in this local environment, so the test suite skipped its one optional fixed bcrypt vector. The external modules are not repository or release files, and GitHub CI with the declared real dependencies remains required before release.

For the version-2.0.7 issue-#54 development run, the complete suite passed with 20 test files and 2,624 tests. The run used the same temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom` as earlier isolated-container runs; they are not repository or release files. The new category guard verified all 47 public readings, including 18 configuration readings with the exact `config` prefix and unchanged Set-command names.

For the version-2.0.8 issue-#52 read-only discovery stage, the complete suite passed with 21 test files and 2,727 tests. The isolated container used temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom`; the fixed PBKDF2 vector passed and the optional bcrypt vector remained skipped because `Crypt::Bcrypt` was unavailable. The interface guard covers 53 public readings, including 24 configuration readings, and the six new battery settings remain deliberately read-only. The external compatibility modules are not repository or release files.

For the version-2.0.9 grouped PV-battery setter implementation, the complete suite passed with 21 test files and 2,820 tests. The isolated container used the same temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom`; they are not repository or release files. The suite verifies one grouped top-level `pvBattery` command, six subcommands, exact secured payload keys and JSON types, strict integer/boolean/clock validation, no optimistic reading changes, successful status confirmation, failed-response preservation, and the final `SoC`/`StopTime` names. The automated result itself does not establish hardware acceptance; the separate maintainer real-device verification is recorded below.

For the version-2.0.10 Set-list cleanup, the complete suite passed with 21 test files and 2,839 tests. The isolated container used temporary external compatibility modules for `JSON`, `Crypt::PBKDF2`, and `Crypt::URandom`; they are not repository or release files. The regression coverage is purely FHEM interface behavior: it verifies Set-list discovery, the no-argument reconnect metadata, disabled-device behavior, and exact argument counts for all public Set commands. No Wattpilot protocol or real-device change is required.

These automated tests use revision-aligned stubs and synthetic fixtures. The pre-fix and post-fix observations above used real FHEM, WebSocket, bcrypt authentication, reconnect, and live readings on one Wattpilot Flex. Version 2.0.3 was exercised for connection, authentication, version separation, live charging readings, and startup message-type diagnostics, but not yet for the corrected idle-energy path with `update_while_idle=0`. No real post-fix predecessor-device, rename, `rereadcfg`, delete, secured-command, or command-response integration test was performed.

Version 2.0.4 was tested with real FHEM and a Wattpilot Flex running firmware 43.4: the `fst`-backed configuration value (then exposed as `pvSurplusStartPower`, now `configPvSurplusStartPower`) was read, changed in both directions through the unchanged `pvSurplusStartPower` Set command, confirmed by device readback, and restored successfully. Version 2.0.5 was tested on a Wattpilot Flex Home 22 C6 running firmware 43.4: all eleven issue-#44 setters were changed individually, confirmed by device readback, and restored; `set reconnect` rebuilt the WebSocket session, authenticated, returned to `connected`, received a new device-pushed initial status, and preserved configuration and operational readings. Rapid repeated reconnect, stale in-flight callbacks, pending-command aborts, and failure paths remain deterministic automated-test coverage rather than controlled live fault-injection coverage. Version 2.0.6 battery telemetry was subsequently confirmed on the real Flex 43.4 device; its then-shared measurement cadence was superseded by the independent version-2.1.1 policy, but controlled charging/discharging comparison is still required before any battery-power sign meaning or mode enum can be promoted. Version 2.0.7 changes only public reading names and classification; no separate real-device behavior test is required to establish protocol behavior, but installation consumers must be updated manually because no migration layer exists. Version 2.0.8 uses the maintainer-provided Solar.wattpilot app screenshot and simultaneous Flex 43.4 fullStatus to establish read semantics for `fam`, `pdte`, `pdt`, `pdle`, `pdls`, and `pdlo`. Version 2.0.9 adds the grouped setter implementation and automated secured-payload/response tests. The maintainer then exercised all six setters on a Wattpilot Flex Home 22 C6 running firmware 43.4: each requested change was accepted, reflected in device-supplied status/readback, and restored to the original value. Deliberate device rejection, persistence across reboot, and other firmware/model variants were not tested.

Version 2.1.7 adds `t/identity_diagnostic_readings.t` and replaces the former battery-telemetry regression with `t/pv_battery_diagnostics.t`. The coverage includes source-separated identity publication, immediate-on-change reconnect behavior, raw interval-controlled `rbc`, `rbt` conversion from empirically observed milliseconds to cumulative `H:MM`, the independent uptime idle gate, all fourteen optional raw diagnostics, two-decimal JSON-number formatting, unchanged strings, and `0|1` booleans, rejection of `null`/objects/arrays, attribute validation, immediate reading/cache cleanup on disable or attribute deletion, and reload cleanup when diagnostics are effectively off. The suite explicitly keeps `fbuf_pAkku` and `pvopt_averagePAkku` as separate uninterpreted fields and makes no unverified meaning, unit, sign, aggregation, or enum claim.

The same version also guards the architecture cleanup around those readings: scalar interval mappings and ordinary scalar-owner order must be derived from the authoritative reading inventory, the former device-health/uptime/diagnostic side tables must remain absent, and all status publication must use the single strict formatter dispatcher. Tests reject unknown reading keys, protect explicit formatter classifications, and ensure the removed second status formatter and obsolete `decimal1` classification are not reintroduced. The complete local suite passes with 29 test files and 3,288 tests.
