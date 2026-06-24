# Architecture

`72_Wattpilot.pm` is the authoritative FHEM module. It remains one installable
FHEM module file and owns the callbacks, DevIo WebSocket integration,
authentication, command handling, status parsing, readings, and the embedded
English and German command reference.

The implementation is divided into narrow internal responsibilities rather
than additional installable Perl modules:

- lifecycle generation, typed timers, stale-callback rejection, and guarded
  DevIo open/close handling;
- stable FUUID-based credential access and two-key transactions;
- structural JSON continuation, decoding, and message dispatch;
- authentication and signing-key generation;
- secured command correlation and response timeouts;
- local manual reconnect orchestration and pending-command termination;
- status normalization and public reading updates;
- idle-refresh and electrical-reading rate limiting.

## Credential model

Version 2.x reads and writes only these persistent resources:

```text
Wattpilot_<FUUID>_password
Wattpilot_<FUUID>_passwordhash
```

The FUUID is the durable owner. Rename therefore does not migrate or rewrite
credentials. Name-based 1.x password/hash keys, owner-marker keys, and pending
legacy-name metadata are neither read nor modified. Released 1.6.x versions are the final releases that contain the old
name-based upgrade machinery. A 2.0 setup
requires a fresh definition and a new password operation; obsolete 1.x key
resources are intentionally left untouched.

Password replacement and device deletion snapshot both stable keys before any
change. A partial failure rolls back earlier successful writes/deletes in
reverse order and reports an incomplete rollback explicitly. Credential reads
preserve the distinction between value present, value absent, and storage
failure.

## Lifecycle ownership

`Wattpilot_InvalidateSession` owns the common session invalidation sequence:
it increments the lifecycle generation, cancels typed module timers, clears
connection-scoped state, and closes the current or frozen DevIo context.
`Wattpilot_ApplyConfiguredState` then resolves disabled, credential-error,
password-missing, or reconnectable state and creates at most one module-owned
reconnect. Special transitions with different semantics, such as authentication
failure, idle-refresh fallback, manual reconnect, shutdown, and failed-Delete restoration, remain
explicit. The public `reconnect` command performs a credential preflight, terminates pending secured requests, resets manual-retry and idle-refresh episode state, and then reuses the common invalidation/configured-state path. It sends no Wattpilot protocol message and makes no `fullStatus`-request claim.
Current FHEM DevIo marks a successful asynchronous open as `opened` before invoking the module callback. An old callback may therefore arrive after manual reconnect, disable, or shutdown and temporarily carry framework-owned state from the invalidated attempt. The generation/ownership guard closes that transport and explicitly restores the configured terminal state; when a reconnect was waiting for the invalidated open, the callback hands off exactly one new scheduled connection instead. Stale callbacks cannot leave the device in `opened` or create a parallel session.

`pendingReconnectAfterOpen` is deliberately retained. It transfers ownership
from an invalidated asynchronous DevIo open callback to exactly one subsequent
module reconnect.

| State | Lifetime |
| --- | --- |
| `lifecycleGeneration` | current device-hash lifetime |
| `timers` | one active callback per timer kind |
| `openInFlight` | until the matching asynchronous DevIo callback completes or is rejected as stale |
| `pendingReconnectAfterOpen` | until the invalidated open callback hands off one reconnect |
| `timeoutRetryUsed` | current authentication/initialization timeout episode |
| `deviceType`, `protocol` | current connection/session |
| `authPending`, `authHashMode`, `authenticated` | current authentication/session |
| `pendingRequests` | current authenticated session |
| `jsonBuffer` | current logical JSON continuation/session |
| `car_state` | current device-hash runtime state |
| idle-refresh flags | current idle episode; the reconnect-awaiting flag deliberately survives the single automatic refresh reconnect, while a manual reconnect clears the episode state |
| `LAST_UPDATE` | current device-hash rate-limit history shared by all high-frequency measurement readings |
| `volatileTelemetryCache` | current connection/session cache for the latest valid stationary-PV-battery fields; published only by an admitted `nrg` cycle |
| `msg_id` | current device-hash request sequence |

## Status and reading pipeline

Incoming status data is copied and normalized once by
`Wattpilot_NormalizeStatus`. Invalid known fields are removed from the copy;
unknown fields are preserved, and the caller's structure is never mutated.

`Wattpilot_UpdateReadings` owns one FHEM bulk-reading transaction and delegates
to narrow helpers for immediate readings, stationary-battery caching, car
transitions, energy values, shared measurement gating, and `nrg` phase/total
readings. Energy counters are processed independently. `update_while_idle`
applies once to the shared high-frequency measurement cycle. Valid stationary-
PV-battery fields are cached per connection and are published only when a valid
`nrg` array is admitted. `interval` therefore has exactly one history,
`LAST_UPDATE`, for voltage, current, power, and stationary-battery telemetry.
Battery-only, configuration-only, invalid-`nrg`, and incomplete-`nrg` messages
cannot consume that interval. Complete `fullStatus` and matched `response`
messages without valid `nrg` may refresh the cache but do not bypass the shared
cadence. Missing partial-update fields never reset readings, and only real
device-supplied zero values create zero readings. `modelStatus` and `msi` each produce both an unmodified numeric code
and a lowerCamelCase text reading. The text table is a compatibility mapping
from the pinned go-e `modelStatus` enum; applying the same table to `msi` is
based on pinned Wattpilot-specific evidence that it is the internal variant of
the same decision. Unknown numeric values remain explicit as `unknown:<code>`. Configuration fields `fst`, `fup`, `fzf`, `frm`, `psm`, `spl3`, `mpwst`, `mptwt`, `fmt`, `fap`, `mcpd`, and `mci` are normalized independently of the electrical gate and exposed immediately through the public configuration readings. Read-only stationary-PV-battery fields use the shared cached measurement pipeline: `fbuf_akkuSOC` is accepted only as a finite percentage from 0 through 100, `fbuf_pAkku` is preserved as a signed finite watt value, formatted to two decimal places, without assigning an unverified sign direction, and `fbuf_akkuMode` is preserved as a non-negative integer code without inventing an enum. Booleans retain JSON-boolean semantics, `frm` and `psm` use explicit compatibility enums with `unknown:<value>` fallbacks, power values use watts, and protocol millisecond durations are exposed as seconds. All corresponding setters use the same secured command-correlation path as the other public commands; no reading is changed optimistically, and only returned status data confirms a value. Time setters accept only finite non-negative seconds that convert exactly to whole protocol milliseconds. No battery setter is present in version 2.0.6; candidate fields such as `fam` remain outside the public interface until their current Flex semantics and writability are independently verified.

The device Internal `VERSION` is module-owned. Define sets it from the central
module version, and Initialize refreshes it for existing Wattpilot hashes during
FHEM module reload without touching lifecycle state. Device firmware remains a
separate `firmwareVersion` reading populated from `hello.version`.

The message dispatcher recognizes `clearInverters`, `updateInverter`, and
`clearSmips` as empirically observed Flex startup notifications. Their payloads
are not consumed, stored, or logged; the type remains visible in the level-4
received-message trace, while the level-3 unsupported-type warning is reserved
for other unknown message types. This classification records observation only
and does not assign protocol semantics.

The clean public 2.0 reading, command, enum, and lifecycle values are collected
in one internal interface definition and exposed to tests through
`Wattpilot_InterfaceSnapshot`. Protocol keys remain internal and unchanged.

## Development infrastructure

- `t/` contains deterministic module-level tests, minimal FHEM/DevIo stubs, and
  synthetic or sanitized fixtures.
- `scripts/` contains repository, META, command-reference, release, and
  reproducibility checks.
- `.github/workflows/ci.yml` invokes the same CI entry point used locally.
- `docs/PROTOCOL-SOURCES.md` records protocol provenance and confidence without
  promoting guesses to documented behavior.
- Embedded META data and the central version in `72_Wattpilot.pm` are validated
  by `scripts/check_meta.pl`.
- Release tooling creates reproducible, verified artifacts only below ignored
  `dist/`.

The embedded META block is registered through `FHEM::Meta::InitMod`, following
the FHEM reference implementation and modules at `fhem/fhem-mirror` commit
`5354e001b55c323f457bd907434e46f284d9582c`.

The stubs are not an FHEM simulator. Automated checks do not establish real
FHEM, key-value backend, network, WebSocket, Wattpilot Flex, or predecessor
Wattpilot compatibility.
