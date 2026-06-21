# Wattpilot protocol sources

Checked on 2026-06-21. This inventory records provenance; it does not turn third-party observations into official API documentation.

## Confidence classes

- **Officially documented:** stated in documentation published by Fronius for the applicable device and firmware.
- **Confirmed by source comparison or reproducible measurements:** independently agrees across inspectable implementations or repeatable, recorded device observations.
- **Inferred but not yet documented:** a plausible interpretation that still needs authoritative documentation or reproducible confirmation.
- **Unknown:** no sufficiently reliable meaning is established.

Only the first two classes may support implemented field semantics, and writable fields additionally require unambiguous write documentation. Missing keys in `deltaStatus` mean “not changed”; they do not justify deleting readings.

## Sources

| Source | Reference checked | Class | Device / firmware scope | Limitations and conflicts |
| --- | --- | --- | --- | --- |
| Fronius public documentation | No public local WebSocket API V2 specification is stored or cited in this repository | Official | None established here | The absence of a cited official specification means no field meaning in this repository may be labelled official solely from the sources below. |
| `joscha82/wattpilot` | https://github.com/joscha82/wattpilot, default branch checked 2026-06-21 | Third-party source comparison | Project describes Fronius Wattpilot protocol handling; exact coverage varies by its revisions | Not a Fronius specification. Names and enum interpretations require comparison or measurements before adoption. |
| `ioBroker.fronius-wattpilot` | https://github.com/tim2zg/ioBroker.fronius-wattpilot, default branch checked 2026-06-21 | Third-party source comparison | ioBroker adapter for Wattpilot devices; exact firmware coverage is not guaranteed for this FHEM module | Adapter behavior is implementation evidence, not official documentation. Conflicts must remain unresolved until independently verified. |
| FHEM WebSocket wiki | https://wiki.fhem.de/wiki/Websocket, page checked 2026-06-21 | Third-party platform documentation | FHEM WebSocket/DevIo integration, not Wattpilot field semantics | Useful for transport integration only. It provides no authority for Wattpilot status or command fields. |
| Repository `API.md` | Commit `a83f25a10cc6924dd72f18faad3ec83cb15efe60`, file last touched 2026-01-26; checked 2026-06-21 | Historical third-party compilation | Contains examples associated with older Wattpilot observations; no complete device/firmware applicability is established | It is not current authoritative documentation. Entries mix source-derived names, examples, and unknowns. Every field meaning and write claim must be re-verified before implementation. |
| Repository module behavior and synthetic tests | `72_Wattpilot.pm` and `t/`, checked 2026-06-21 | Empirical repository baseline only | Existing behavior and synthetic Flex 43.4-shaped fixtures | Tests use stubs and synthetic values. They do not prove real FHEM or device behavior and must not be used to promote guesses to documented semantics. |

## Use in future changes

For every proposed protocol-field change, record the source revision, applicable device and firmware, confidence class, and any conflicting evidence. If evidence is incomplete, preserve the field as inferred or unknown and do not add a set command. Real captures must be sanitized before they enter tests, logs, issues, or fixtures.
