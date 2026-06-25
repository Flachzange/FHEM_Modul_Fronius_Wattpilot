# Legacy Wattpilot protocol-2 compatibility

> This document records the compatibility contract for the original Fronius Wattpilot generation. It is based on pinned Wattpilot-specific third-party source evidence and the original module's reported device scope. It is not an official Fronius protocol specification and it is not a claim of generic go-eCharger compatibility.

## Device scope

The original module author reported development and testing for these predecessor models:

- Fronius Wattpilot Home 11 J 2.0
- Fronius Wattpilot Home 22 J 2.0
- Fronius Wattpilot Go 11 J 2.0
- Fronius Wattpilot Go 22 J 2.0

The compatibility profile is therefore called **legacy Wattpilot protocol 2**, not “all go-e chargers”.

## Pinned protocol evidence

The repository `joscha82/wattpilot` at commit `4712ba3b8409fda55303870c047038b1b221d7ff` describes the following flow:

- `hello.devicetype` is `wattpilot`;
- `hello.protocol` is `2`;
- the documented legacy example announces `secured:true`;
- `authRequired` contains `token1` and `token2` without a `hash` field;
- the password-derived value is generated with PBKDF2-HMAC-SHA512 using the serial as salt and 100000 iterations;
- writes are sent as `setValue` and, when `secured` is true, wrapped in `securedMsg` with an HMAC and an `sm`-suffixed request ID;
- `fullStatus.partial:true` may split initialization across multiple messages;
- the first twelve positions of `nrg` contain the electrical values used by the current FHEM readings.

These are reproducible implementation statements, not official documentation. The synthetic fixture [`../t/fixtures/legacy-protocol2-session.json`](../t/fixtures/legacy-protocol2-session.json) preserves the non-identifying protocol shape used by the regression test. The serial required for deterministic PBKDF2 testing exists only inside the test code, because repository privacy checks deliberately reject identifier fields in ordinary synthetic fixtures.

## Regression contract for the current module

A legacy `fullStatus` may be split across messages with top-level `partial:true`. Such messages update supplied fields but do not by themselves complete initialization. Completion requires the final non-partial full status; `deltaStatus` retains the established compatibility fallback. The `partial` member is envelope metadata and is not a status field.

Version 1.5.0 hardens authentication and input validation while the following behavior remains protected by automated tests:

1. `authHash=auto` continues to select PBKDF2 when the legacy `authRequired` message omits `hash`.
2. Explicit `pbkdf2` and `bcrypt` announcements remain supported.
3. Manual `authHash=pbkdf2|bcrypt` remains authoritative.
4. A 12-element legacy `nrg` array updates the existing voltage, current, phase-power, and total-power readings.
5. A 16-element Flex `nrg` array continues to use the same first twelve positions.
6. A later partial status message does not delete or reset readings for omitted keys.
7. Legacy writes retain the current secured `setValue`/`securedMsg` schema and request-response correlation.

Version 1.5.0 rejects an explicitly unknown authentication algorithm. It does not reject a missing `authRequired.hash` after `hello.devicetype=wattpilot` and `hello.protocol=2` identify this documented legacy profile.

## Deliberate limits

- No real legacy Wattpilot was contacted for this change.
- No real FHEM, network, WebSocket, authentication, charging, or command-response integration test was performed.
- The fixture is synthetic and confirms only the regression behavior of this repository.
- `secured:false` is not added as a new runtime path here. Although the pinned client contains a branch for unsigned writes, no applicable real legacy Wattpilot observation was supplied for this repository.
- The missing-hash fallback is gated by the evidenced `hello.devicetype=wattpilot` and protocol-2 profile. This identifies the compatibility branch; it does not turn the third-party evidence into an official Fronius specification.
