# Wattpilot protocol sources

Checked on 2026-06-21. This inventory pins online sources to reproducible revisions. It records provenance; it does not turn third-party observations into official API documentation.

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
| `joscha82/wattpilot` | Commit [`4712ba3b8409fda55303870c047038b1b221d7ff`](https://github.com/joscha82/wattpilot/tree/4712ba3b8409fda55303870c047038b1b221d7ff), checked 2026-06-21 | Third-party source comparison | Project describes Wattpilot protocol handling; exact device and firmware coverage is not established here | Not a Fronius specification. Names, enums, and write behavior remain implementation evidence only. |
| `tim2zg/ioBroker.fronius-wattpilot` | Commit [`1510d51b52724417e81d58b1d1a1ef80e9fb3db1`](https://github.com/tim2zg/ioBroker.fronius-wattpilot/tree/1510d51b52724417e81d58b1d1a1ef80e9fb3db1), checked 2026-06-21 | Third-party source comparison | ioBroker adapter for Wattpilot devices; exact firmware coverage is not guaranteed for this FHEM module | Adapter behavior is implementation evidence, not official documentation. It cannot establish writability. |
| `goecharger/go-eCharger-API-v2` | Commit [`6a12380798b24e8f40d8fbb260a4ae24c3ce42fb`](https://github.com/goecharger/go-eCharger-API-v2/tree/6a12380798b24e8f40d8fbb260a4ae24c3ce42fb), checked 2026-06-21 | Officially documented by go-e for its API; **not automatically official Fronius documentation** | go-eCharger API V2 scope stated by that project; Wattpilot applicability is not assumed | May be used only where independent evidence establishes applicability. It does not by itself justify Wattpilot field meanings or set commands. |
| `ruaan-deysel/wattpilot-api` | Commit [`498aa8709f198fcde2b41159ad99dc02e57accc9`](https://github.com/ruaan-deysel/wattpilot-api/tree/498aa8709f198fcde2b41159ad99dc02e57accc9), checked 2026-06-21 | Third-party source comparison | Project targets Wattpilot API usage; exact device and firmware coverage is not established here | Implementation evidence only; inferred meanings and write operations require independent documentation or reproducible confirmation. |
| FHEM WebSocket wiki | https://wiki.fhem.de/wiki/Websocket, page checked 2026-06-21 | Third-party platform documentation | FHEM WebSocket/DevIo integration, not Wattpilot field semantics | Useful for transport integration only. It provides no authority for Wattpilot status or command fields. |
| Repository `API.md` | Commit [`a83f25a10cc6924dd72f18faad3ec83cb15efe60`](https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot/blob/a83f25a10cc6924dd72f18faad3ec83cb15efe60/API.md), file last changed 2026-01-26; checked 2026-06-21 | Historical third-party compilation | Contains examples associated with older Wattpilot observations; no complete device/firmware applicability is established | Not current authoritative documentation. Every field meaning and write claim must be re-verified before implementation. |
| Synthetic fixtures | Commit [`1aaf1a1833261292e0f6ff25b5b188c6651d2097`](https://github.com/Flachzange/FHEM_Modul_Fronius_Wattpilot/tree/1aaf1a1833261292e0f6ff25b5b188c6651d2097/t/fixtures), checked 2026-06-21 | Synthetic test input, not protocol evidence | Structurally shaped examples labelled Flex 43.4 | Values are deliberately synthetic and sanitized. They test parsing structure only and cannot confirm field meaning, device behavior, or writability. |
| Empirical device observations | No sanitized capture, measurement procedure, device model, firmware version, or repeatable observation record is currently committed; checked 2026-06-21 | **Unknown / evidence gap** | None reproducibly established in this repository | Existing module behavior is not a substitute for a recorded measurement. Future observations must be sanitized and reproducible before they can raise confidence. |

## Use in future changes

For every proposed protocol-field change, record the source revision, applicable device and firmware, confidence class, and any conflicting evidence. If evidence is incomplete, preserve the field as inferred or unknown and do not add a set command. Real captures must be sanitized before they enter tests, logs, issues, or fixtures.
