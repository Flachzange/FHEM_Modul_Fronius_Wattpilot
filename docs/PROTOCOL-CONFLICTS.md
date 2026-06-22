# Known Wattpilot protocol evidence conflicts

This document preserves conflicts between the observed Wattpilot Flex 43.4 payload, current FHEM 1.x behavior, pinned Wattpilot-specific third-party implementations, and planned corrections. None of the third-party sources is an official Fronius specification.

## `frc` force-state enum

- The Flex Home 22 C6 capture proves only JSON type `number` and observed value `0`.
- Current FHEM 1.x interprets `0` as Start and `1` as Stop, and sends `0` for Start.
- `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff` and `ruaan-deysel/wattpilot-api` commit `498aa8709f198fcde2b41159ad99dc02e57accc9` both describe `0=Neutral`, `1=Off`, `2=On` and mark the field R/W.
- Issue #8 records the current FHEM mapping as a functional defect and targets Start=`2`, Stop=`1`.
- Actual Flex 43.4 enum and write behavior remain unverified by a reproducible device test.

## `amp` range and writability

- The Flex 43.4 capture contains `amp=32`, `cll.currentLimitMax=32`, and `cll.requestedCurrent=32`.
- Current FHEM 1.x treats `amp` as amperes and sends any unsigned integer.
- `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff` describes an older or incompletely scoped R/W range of 6–16 A.
- Issue #8 targets validation of the current public command to 6–32 A.
- The accepted Flex 43.4 write range and error behavior remain unverified by applicable documentation or a reproducible device test.
