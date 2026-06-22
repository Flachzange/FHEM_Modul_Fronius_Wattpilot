# Wattpilot protocol sources

Checked on 2026-06-22. This inventory pins online sources to reproducible revisions. It records provenance; it does not turn third-party observations into official API documentation.

## Confidence classes

- **Officially documented:** stated in documentation published by Fronius for the applicable device and firmware.
- **Confirmed by source comparison or reproducible measurements:** independently agrees across inspectable implementations or repeatable, recorded device observations.
- **Inferred but not yet documented:** a plausible interpretation that still needs authoritative documentation or reproducible confirmation.
- **Unknown:** no sufficiently reliable meaning is established.

Only the first two classes may support implemented field semantics, and writable fields additionally require unambiguous write documentation. Missing keys in `deltaStatus` mean “not changed”; they do not justify deleting readings.

## Sources

| Source | Reference checked | Class | Device / firmware scope | Limitations and conflicts |
| --- | --- | --- | --- | --- |
| Public Fronius local WebSocket API V2 specification | No public specification located; search gap recorded 2026-06-21 | **Source gap / unknown**, not an official source | None established | No field meaning in this repository may be labelled officially documented by Fronius on the basis of this gap. |
| Original FHEM module author statement | FHEM forum post checked 2026-06-22 | Maintainer report, not protocol specification | Development and testing reported for Wattpilot Home 11 J 2.0, Home 22 J 2.0, Go 11 J 2.0, and Go 22 J 2.0 | Establishes the intended predecessor-model scope of the original module, not the exact protocol schema or current firmware behavior. |
| `joscha82/wattpilot` | Commit [`4712ba3b8409fda55303870c047038b1b221d7ff`](https://github.com/joscha82/wattpilot/tree/4712ba3b8409fda55303870c047038b1b221d7ff), checked 2026-06-22 | Third-party source comparison | Describes a legacy `wattpilot` hello with protocol 2 and secured writes; exact device and firmware coverage is not established here | Not a Fronius specification. It is the pinned source for the synthetic legacy regression contract: `authRequired` may omit `hash`, PBKDF2 is used, `fullStatus.partial` may split initialization, and the first twelve `nrg` positions are consumed. |
| `tim2zg/ioBroker.fronius-wattpilot` | Commit [`1510d51b52724417e81d58b1d1a1ef80e9fb3db1`](https://github.com/tim2zg/ioBroker.fronius-wattpilot/tree/1510d51b52724417e81d58b1d1a1ef80e9fb3db1), checked 2026-06-21 | Third-party source comparison | ioBroker adapter for Wattpilot devices; exact firmware coverage is not guaranteed for this FHEM module | Adapter behavior is implementation evidence, not official documentation. It cannot establish writability. |
| `goecharger/go-eCharger-API-v2` | Commit [`6a12380798b24e8f40d8fbb260a4ae24c3ce42fb`](https://github.com/goecharger/go-eCharger-API-v2/tree/6a12380798b24e8f40d8fbb260a4ae24c3ce42fb), checked 2026-06-21 | Officially documented by go-e for its API; **not automatically official Fronius documentation** | go-eCharger API V2 scope stated by that project; Wattpilot applicability is not assumed | May be used only where independent evidence establishes applicability. It does not by itself justify Wattpilot field meanings or set commands. |
| `ruaan-deysel/wattpilot-api` | Commit [`498aa8709f198fcde2b41159ad99dc02e57accc9`](https://github.com/ruaan-deysel/wattpilot-api/tree/498aa8709f198fcde2b41159ad99dc02e57accc9), checked 2026-06-21 | Third-party source comparison | Project targets Wattpilot API usage; exact device and firmware coverage is not established here | Implementation evidence only; inferred meanings and write operations require independent documentation or reproducible confirmation. |
| FHEM WebSocket wiki | https://wiki.fhem.de/wiki/Websocket, page checked 2026-06-21 | Third-party platform documentation | FHEM WebSocket/DevIo integration, not Wattpilot field semantics | Useful for transport integration only. It provides no authority for Wattpilot status or command fields. |
| Repository `API.md` history | Commit [`a83f25a10cc6924dd72f18faad3ec83cb15efe60`](https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot/blob/a83f25a10cc6924dd72f18faad3ec83cb15efe60/API.md), file last changed 2026-01-26; checked 2026-06-21 | Historical third-party compilation | Contains examples associated with older Wattpilot observations; no complete device/firmware applicability is established | Not current authoritative documentation. Every field meaning and write claim must be re-verified before implementation. |
| Synthetic fixtures | Repository `t/fixtures`, checked 2026-06-22 | Synthetic test input, not protocol evidence | Flex-shaped examples and a protocol-2 legacy regression session | Values are deliberately synthetic and sanitized. They test repository behavior only and cannot confirm device behavior, field meaning, or writability. |
| Sanitized observed Wattpilot Flex `fullStatus` | Maintainer-provided capture published in Issue #11 and committed as [`t/fixtures/fullStatus-flex-observed.json`](../t/fixtures/fullStatus-flex-observed.json), captured/checked 2026-06-21; SHA-256 `ca8f70cd954ebd70684744386660b80b4ce6a2cc0a5ab7751c27b59676b09d33` | **Empirical structure/value observation** | Wattpilot Flex Home 22 C6; `wattpilot_flex`; firmware 43.4; protocol 4; reported authentication mode bcrypt | One sanitized `fullStatus` with `partial:false` and 558 status keys. It confirms observed structure, JSON types, array lengths, null positions, and representative sanitized values only. It is not an official Fronius specification and does not by itself establish meanings, units, enums, requiredness, writability, other messages, other configurations, or other firmware/models. See [`WATTPILOT-FLEX-JSON-API.md`](WATTPILOT-FLEX-JSON-API.md). |

## Compatibility contracts

- [`WATTPILOT-LEGACY-PROTOCOL2.md`](WATTPILOT-LEGACY-PROTOCOL2.md) defines the regression contract for the original Wattpilot generation. In particular, Issue #10 must preserve the evidenced PBKDF2 behavior when the legacy protocol-2 `authRequired` message omits `hash`.
- [`WATTPILOT-FLEX-JSON-API.md`](WATTPILOT-FLEX-JSON-API.md) remains the empirical structural reference for the documented Flex capture.

## Known field-level conflicts

The authoritative empirical reference and [`PROTOCOL-CONFLICTS.md`](PROTOCOL-CONFLICTS.md) preserve the known contradictions instead of silently resolving them:

- **`frc`:** the Flex 43.4 capture proves only numeric value `0`. Version 1.4.0 maps `0=Neutral`, `1=Stop`, and `2=Start`, matching the two pinned Wattpilot-specific implementations. These remain third-party claims until reproduced or officially documented for Flex 43.4.
- **`amp`:** the Flex 43.4 capture contains `amp=32` and `cll.currentLimitMax=32`. The pinned older Wattpilot-specific source states R/W amperes with range 6–16. Version 1.4.0 validates the established public FHEM command to 6–32 A; the exact Flex 43.4 device-side rejection behavior remains unverified.
- **Authentication selection:** current 1.4.0 automatically falls back to PBKDF2 for every non-bcrypt or missing `authRequired.hash`. The missing-field case is required for the pinned legacy protocol-2 flow. Treating an explicitly unknown algorithm as PBKDF2 is not part of the compatibility contract and remains scheduled for hardening in Issue #10.
- **Secured commands and `response`:** the pinned older implementation emits numeric request IDs inside `setValue`, wraps secured writes with an `sm`-suffixed outer ID and HMAC, and correlates incoming `response.requestId`. Version 1.4.0 accepts numeric IDs and their `sm` form, suppresses untrusted device messages in normal diagnostics, and bounds pending state to 32 requests/30 seconds.

## Use in future changes

For every proposed protocol-field change, record the source revision, applicable device and firmware, confidence class, and any conflicting evidence. If evidence is incomplete, preserve the field as inferred or unknown and do not add a set command. Real captures must be sanitized before they enter tests, logs, issues, or fixtures.
