# Known Wattpilot protocol evidence conflicts

This document preserves conflicts between the observed Wattpilot Flex 43.4 payload, current FHEM behavior, pinned Wattpilot-specific third-party implementations, and implemented compatibility mappings. None of the third-party sources is an official Fronius specification.

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

## `modelStatus` and `msi` charging-decision mapping

The current module exposes the raw integer fields as `chargingDecisionCode` (`modelStatus`) and `chargingDecisionInternalCode` (`msi`). It also maps both fields to the text readings `chargingDecision` and `chargingDecisionInternal` using the `modelStatus` enum from pinned official go-e API revision `6a12380798b24e8f40d8fbb260a4ae24c3ce42fb`, file `API_KEYS_FIRMWARE/apikeys-de.md`. The module normalizes the source names to lower camel case.

| Code | FHEM text value |
| ---: | --- |
| 0 | `notChargingBecauseNoChargeCtrlData` |
| 1 | `notChargingBecauseOvertemperature` |
| 2 | `notChargingBecauseAccessControlWait` |
| 3 | `chargingBecauseForceStateOn` |
| 4 | `notChargingBecauseForceStateOff` |
| 5 | `notChargingBecauseScheduler` |
| 6 | `notChargingBecauseEnergyLimit` |
| 7 | `chargingBecauseAwattarPriceLow` |
| 8 | `chargingBecauseAutomaticStopTestLadung` |
| 9 | `chargingBecauseAutomaticStopNotEnoughTime` |
| 10 | `chargingBecauseAutomaticStop` |
| 11 | `chargingBecauseAutomaticStopNoClock` |
| 12 | `chargingBecausePvSurplus` |
| 13 | `chargingBecauseFallbackGoEDefault` |
| 14 | `chargingBecauseFallbackGoEScheduler` |
| 15 | `chargingBecauseFallbackDefault` |
| 16 | `notChargingBecauseFallbackGoEAwattar` |
| 17 | `notChargingBecauseFallbackAwattar` |
| 18 | `notChargingBecauseFallbackAutomaticStop` |
| 19 | `chargingBecauseCarCompatibilityKeepAlive` |
| 20 | `chargingBecauseChargePauseNotAllowed` |
| 22 | `notChargingBecauseSimulateUnplugging` |
| 23 | `notChargingBecausePhaseSwitch` |
| 24 | `notChargingBecauseMinPauseDuration` |
| 26 | `notChargingBecauseError` |
| 27 | `notChargingBecauseLoadManagementDoesntWant` |
| 28 | `notChargingBecauseOcppDoesntWant` |
| 29 | `notChargingBecauseReconnectDelay` |
| 30 | `notChargingBecauseAdapterBlocking` |
| 31 | `notChargingBecauseUnderfrequencyControl` |
| 32 | `notChargingBecauseUnbalancedLoad` |
| 33 | `chargingBecauseDischargingPvBattery` |
| 34 | `notChargingBecauseGridMonitoring` |
| 35 | `notChargingBecauseOcppFallback` |

Codes `21` and `25` are absent from the pinned enum and from the module mapping; this document does not assign them a meaning. Any other unmapped integer remains visible as `unknown:<code>` in the text reading while the corresponding raw-code reading keeps the original integer.

The mapping is official documentation for go-e devices, not an official Fronius Wattpilot Flex specification. Its use for Wattpilot is a compatibility mapping supported only in part by observations: the sanitized Flex 43.4 capture contains `modelStatus=23` and `msi=27`, and one live PV-surplus charging observation produced `modelStatus=12` and `msi=12`. These observations do not validate the complete enum.

The exact relationship, evaluation order, precedence, and any role of `cpDisabledRequest` remain unconfirmed. In particular, the repository does not claim that `modelStatus` is necessarily the final effective decision, that `msi` is necessarily an earlier internal decision, or that the numeric order describes a state-machine sequence or priority. When the values differ, they remain two independent device-supplied diagnostics.
