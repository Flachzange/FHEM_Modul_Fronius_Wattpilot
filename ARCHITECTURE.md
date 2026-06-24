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
failure, idle-refresh fallback, shutdown, and failed-Delete restoration, remain
explicit.

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
| idle-refresh flags | current idle episode; the reconnect-awaiting flag deliberately survives the single refresh reconnect |
| `LAST_UPDATE` | current device-hash rate-limit history |
| `msg_id` | current device-hash request sequence |

## Status and reading pipeline

Incoming status data is copied and normalized once by
`Wattpilot_NormalizeStatus`. Invalid known fields are removed from the copy;
unknown fields are preserved, and the caller's structure is never mutated.

`Wattpilot_UpdateReadings` owns one FHEM bulk-reading transaction and delegates
to narrow helpers for immediate readings, car transitions, energy values,
electrical-update gating, and `nrg` phase/total readings. Energy counters are
processed before the gate; `interval` and `update_while_idle` apply only to the
`nrg`-derived voltage, current, and power group. Missing partial-update fields
never reset readings, and only real device-supplied zero values create zero
readings. `modelStatus` and `msi` each produce both an unmodified numeric code
and a lowerCamelCase text reading. The text table is a compatibility mapping
from the pinned go-e `modelStatus` enum; applying the same table to `msi` is
based on pinned Wattpilot-specific evidence that it is the internal variant of
the same decision. Unknown numeric values remain explicit as `unknown:<code>`. The `fst` field is normalized separately as a non-negative finite number and exposed immediately as `pvSurplusStartPower` in watts. Its setter uses the same secured command-correlation path as the other public commands; no reading is changed optimistically, and only returned status data confirms a value.

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
