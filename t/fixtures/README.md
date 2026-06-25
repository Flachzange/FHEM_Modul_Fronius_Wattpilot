# Protocol fixtures

- `fullStatus-flex-observed.json` is the sanitized empirical observation published in Issue #11. It preserves the complete observed Wattpilot Flex key set, structure, JSON types, array lengths, and null positions; representative values are sanitized and are not the original live values.
- `fullStatus-flex-43.4.json` and `deltaStatus-flex-43.4.json` are explicitly synthetic parser fixtures. They are not device observations or protocol evidence.
- `pv-battery-settings-flex-43.4.json` is a minimal sanitized evidence fixture derived from a maintainer-provided simultaneous Solar.wattpilot app view and Flex Home 22 C6 firmware-43.4 `fullStatus`. It contains only the six correlated configuration fields and no device, network, account, or installation identifiers.
