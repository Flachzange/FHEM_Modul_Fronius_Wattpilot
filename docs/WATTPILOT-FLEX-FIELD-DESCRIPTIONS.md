# Wattpilot Flex field-description candidates

> This document is a companion to the [empirical Wattpilot Flex JSON/WebSocket reference](WATTPILOT-FLEX-JSON-API.md). Every alias, meaning, unit, enum, range, and read/write statement below is an **evidence-qualified candidate**, not an official or confirmed Wattpilot Flex specification.

## How to use this catalog

1. Use [`WATTPILOT-FLEX-JSON-API.md`](WATTPILOT-FLEX-JSON-API.md) to establish whether a key was observed on the documented Flex 43.4 device, its location, JSON type, array shape, and sanitized representative value.
2. Use this catalog for a readable alias and semantic candidate.
3. Check [`PROTOCOL-SOURCES.md`](PROTOCOL-SOURCES.md), field-specific conflict notes, and current module behavior before relying on a unit, enum, range, or write claim.
4. Keep a field `unknown` when applicable evidence is missing. A plausible alias is not a protocol guarantee.

Root [`API.md`](../API.md) is the stable entry point linking the empirical reference and this description catalog.

## Confidence labels

| Label | Meaning |
|---|---|
| `implementation` | Used this way by the current FHEM module; this does not prove device specification semantics. |
| `historical candidate` | Retained from the former `API.md` compilation; applicability to Flex 43.4 is unverified. |
| `pinned third party` | Supported by an identified Wattpilot-specific implementation at a pinned revision, but not official Fronius documentation. |
| `observed structure` | Key/type/value shape was present in the sanitized Flex capture; semantics may still be unknown. |

## Cross-reading examples

### `amp`

- Observed as a number with representative value `32` in the Flex capture.
- Historical alias and meaning candidate: `chargingCurrent`, requested charging current in amperes. The current public reading is `configChargingCurrent`; the Set command remains `chargingCurrent`.
- The current module exposes `amp` as `configChargingCurrent`, accepts integer values 6–32 A through the unchanged `chargingCurrent` Set command, and sends `amp` through `setValue`.
- Actual Flex 43.4 writability, full accepted range, and device-side validation were not established by a real command test.

### `frc`

- Observed as a number with representative value `0`.
- Pinned Wattpilot-specific evidence gives `0=Neutral`, `1=Off`, `2=On`.
- The current module exposes `frc` as `configForceState`; the unchanged `forceState` Set command sends `0`, `1`, and `2` for `neutral`, `off`, and `on` respectively.
- The enum and write behavior have not been reproduced on the documented Flex device.

### `nrg`

- Observed as an array with exactly 16 numeric elements.
- Historical and implementation candidates assign voltage, current, phase power, total power, and power-factor positions.
- The capture confirms the shape, not the index meanings or units.

## Version 2.0.1 FHEM exposure boundary

Version 2.0.3 exposes `alw`, `modelStatus`, `msi`, `err`, `ama`, `amt`, and `mca` as public FHEM readings. This does not promote the historical aliases or units to official Flex facts. `chargingAllowed` is emitted as `0|1`; `modelStatus` and `msi` retain raw integer readings and additionally receive compatibility text readings from the pinned go-e enum, with `unknown:<code>` for unmapped values. The `msi` internal-decision role remains pinned Wattpilot-specific third-party evidence. Error and current-limit fields remain raw integers. No write command is added for these fields.

## Charging, vehicle, and access fields

| Key | Alias / readable name | Meaning, unit, or enum candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `acs` | `accessState` | Access-control user setting; candidate enum `Open=0`, `Wait=1` | R/W | historical candidate |
| `acu` | `allowedCurrent` | Current presently allowed for the vehicle, candidate unit A | R | historical candidate |
| `adi` | `adapterLimit` | Adapter-current limitation active | R | historical candidate |
| `al1`…`al5` | `adapterLimit1`…`adapterLimit5` | Adapter/current-limit preset candidates | unknown | historical candidate |
| `alw` | `allowCharging` | Whether charging is currently allowed | R | historical candidate |
| `ama` | `maxCurrentLimit` | Maximum-current limit candidate, unit A | R/W | historical candidate |
| `amp` | `configChargingCurrent` / Set `chargingCurrent` | Requested charging current; current FHEM public range 6–32 A | R/W | implementation plus conflicting historical/pinned evidence |
| `amt` | `temperatureCurrentLimit` | Current limit caused by temperature, candidate unit A | R | historical candidate |
| `bac` | `buttonAllowCurrentChange` | Whether the hardware button may change current | R/W | historical candidate |
| `car` | `carState` | Current module mapping: `0 unknown`, `1 idle`, `2 charging`, `3 waitingForCar`, `4 complete`, `5 error`; only observed numeric values are evidence | R | implementation/historical candidate |
| `cbl` | `cableCurrentLimit` | Cable current limit, candidate unit A | R | historical candidate |
| `cdi` | `chargingDurationInfo` | Charging-duration object; candidate `type=0` counter, `type=1` duration in ms | R | historical candidate |
| `cpe` | `cpEnable` | Charge-controller request for CP signal enablement | R | historical candidate |
| `cpr` | `cpEnableRequest` | CP-enable request candidate | R | historical candidate |
| `cus` | `cableUnlockStatus` | Candidate enum: `Unknown=0`, `Unlocked=1`, `UnlockFailed=2`, `Locked=3`, `LockFailed=4`, `LockUnlockPowerout=5` | R | historical candidate |
| `dwo` | `chargingEnergyLimit` | Charging-energy limit candidate in Wh; `null` may mean disabled | R/W | historical candidate |
| `err` | `errorState` | Charger error-state enum candidate | R | historical candidate |
| `ffb` | `lockFeedback` | Candidate enum: `NoProblem=0`, `ProblemLock=1`, `ProblemUnlock=2` | R | historical candidate |
| `ffba` | `lockFeedbackAge` | Age of lock feedback, candidate unit ms | R | historical candidate |
| `frc` | `configForceState` / Set `forceState` | Current module mapping: `0 neutral`, `1 off`, `2 on` | R/W candidate | pinned third party plus implementation; Flex write unverified |
| `fsp` | `forceSinglePhase` | Force or report single-phase operation | R/W candidate | historical candidate |
| `fsptws` | `forceSinglePhaseToggleWishedSince` | Time since a phase-toggle request, candidate unit ms | R | historical candidate |
| `lccfc` | `lastCarStateChangedFromCharging` | Time marker for leaving Charging, candidate unit ms | R | historical candidate |
| `lccfi` | `lastCarStateChangedFromIdle` | Time marker for leaving Idle, candidate unit ms | R | historical candidate |
| `lcctc` | `lastCarStateChangedToCharging` | Time marker for entering Charging, candidate unit ms | R | historical candidate |
| `lck` | `effectiveLockSetting` | Candidate enum: `Normal=0`, `AutoUnlock=1`, `AlwaysLock=2`, `ForceUnlock=3` | R | historical candidate |
| `mca` | `minChargingCurrent` | Minimum charging current, candidate unit A | R/W | historical candidate |
| `mci` | `configMinimumChargingInterval` / Set `minimumChargingInterval` | The module exposes protocol milliseconds as public seconds and provides a secured setter. The current Fronius Flex manual labels the user behavior “Forced charging interval”. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation, pinned official go-e R/W/unit metadata, and pinned Wattpilot-specific alias; not official Fronius WebSocket documentation |
| `mcpd` | `configMinimumChargingPauseDuration` / Set `minimumChargingPauseDuration`; historical `minChargePauseDuration` | The module exposes protocol milliseconds as public seconds and provides a secured setter for the vehicle charge-pause duration. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation, pinned official go-e R/W/unit metadata, and pinned Wattpilot-specific alias |
| `mcpea` | `minChargePauseEndsAt` | End of current minimum pause; `null` may abort it | R/W candidate | historical candidate |
| `modelStatus` | `modelStatus` | Reason charging is or is not allowed; large historical enum exists but is not accepted as Flex fact | R | historical candidate |
| `msi` | `modelStatusInternal` | Internal charging-decision reason candidate | R | historical candidate |
| `nmo` | `norwayMode` | Norway-mode / ground-check setting candidate | R/W | historical candidate |
| `pnp` | `numberOfPhases` | Number of active charging phases candidate | R | historical candidate |
| `psm` | `configPhaseSwitchMode` / Set `phaseSwitchMode` | The module maps `0 auto`, `1 force1`, `2 force3`; unknown numeric values remain explicit. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius Automatic/Only 1-phase/Only 3-phase behavior documentation and pinned API enum/R/W evidence |
| `psmd` | `forceSinglePhaseDuration` | Force-single-phase duration, candidate unit ms | R/W | historical candidate |
| `pwm` | `phaseWishMode` | Candidate enum: `Force_3=0`, `Wish_1=1`, `Wish_3=2` | R | historical candidate |
| `su` | `simulateUnplugging` | Simulate vehicle unplugging | R/W | historical candidate |
| `sua` | `simulateUnpluggingAlways` | Always simulate unplugging candidate | R/W | historical candidate |
| `sumd` | `simulateUnpluggingDuration` | Simulated-unplugging duration, candidate unit ms | R/W | historical candidate |
| `trx` | `transaction` | Candidate: `null` no transaction, `0` without card, otherwise card index + 1 | R/W candidate | historical candidate |
| `upo` | `unlockPowerOutage` | Unlock after power outage candidate | R/W | historical candidate |
| `ust` | `cableLock` | Candidate enum: `Normal=0`, `AutoUnlock=1`, `AlwaysLock=2` | R/W | historical candidate |

## Energy and electrical fields

| Key | Alias / readable name | Meaning, unit, or layout candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `eto` | `energyTotal` | Total energy candidate; the current module divides the raw value by 1000, with Wh-to-kWh meaning still an implementation interpretation | R | implementation/historical candidate |
| `etop` | `energyTotalPersisted` | Persisted total energy, candidate unit Wh | R | historical candidate |
| `fhz` | `frequency` | Grid frequency, candidate unit Hz | R | historical candidate |
| `nrg` | `voltageL1..3`, `currentL1..3`, `powerL1..3`, `power` | 16-element electrical array; current public readings use selected indices, while index meanings and units remain implementation interpretations | R | observed structure plus implementation/historical interpretation |
| `pakku` | `pAkku` | Battery power, candidate unit W | R | historical candidate |
| `pgrid` | `pGrid` | Grid power, candidate unit W | R | historical candidate |
| `ppv` | `pPv` | PV power, candidate unit W | R | historical candidate |
| `tpa` | `totalPowerAverage` | Candidate 30-second total-power average | R | historical candidate |
| `wh` | `energySincePlugIn` | Energy since vehicle connection; the current module interprets the raw value as Wh | R | implementation/historical candidate |

### Candidate `nrg` layout

The former compilation proposed the following 16-element layout. Treat it as a candidate only:

| Index | Candidate meaning |
|---:|---|
| 0–3 | Voltage L1, L2, L3, N |
| 4–6 | Current L1, L2, L3 |
| 7–11 | Power L1, L2, L3, N, total |
| 12–15 | Power factor L1, L2, L3, N |

Current FHEM uses indices 0–2, 4–6, 7–9, and 11. The documented capture does not independently confirm those meanings or units.

## PV surplus, inverter, and phase-control fields

| Key | Alias / readable name | Meaning or unit candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `fam` | `configPvBatteryChargeAboveStateOfCharge`; app `Charge above` | Version 2.0.8 exposes the observed finite 0–100 value read-only. The exact app/status pair was 60/60 on one Flex 43.4. | Read-only compatibility implementation; writability unverified | simultaneous Solar.wattpilot app and `fullStatus` evidence; historical `pvBatteryLimit` alias is secondary |
| `fap` | `configChargingPauseAllowed` / Set `chargingPauseAllowed`; historical `froniusAllowPause` | The module exposes the JSON boolean as `0`/`1` and provides a secured setter for the documented Allow charging pause behavior. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex boolean plus official Fronius behavior documentation and pinned API/Wattpilot R/W evidence |
| `fbuf_age` | `fbufAge` | Age of Fronius inverter buffer data | unknown | historical candidate |
| `fbuf_akkuMode` | `pvBatteryModeCode` / historical `akkuMode` | Version 2.0.6 exposes the observed non-negative integer unchanged. No text enum is claimed. All message types follow the same shared module-side `interval` gate and `update_while_idle` policy. | R compatibility implementation; no setter | sanitized Flex 43.4 field/type/value plus pinned Wattpilot-specific alias; rate limiting is module policy, not protocol semantics |
| `fbuf_akkuSOC` | `pvBatteryStateOfCharge` / historical `akkuSoc` | Version 2.0.6 exposes the stationary PV-battery state of charge as a finite value from 0 through 100 percent with exactly one decimal place. All message types follow the same shared module-side `interval` gate and `update_while_idle` policy. | R compatibility implementation; no setter | sanitized Flex 43.4 field/type/value plus pinned Wattpilot-specific meaning; one observation does not establish broader firmware scope |
| `fbuf_pAkku` | `pvBatteryPower` / historical `powerAkku` | Version 2.0.6 exposes the signed finite value in W, formatted to two decimal places. A historical source suggests a sign convention, but controlled Flex confirmation is still missing, so no charge/discharge direction is assigned. All message types follow the same shared module-side `interval` gate and `update_while_idle` policy. | R compatibility implementation; no setter | sanitized Flex 43.4 field/type/value plus pinned Wattpilot-specific power/W candidate; sign semantics remain unconfirmed |
| `fbuf_pGrid` | `powerGrid` | Grid power; historical sign convention says negative means feed-in | unknown | historical candidate |
| `fbuf_pPv` | `powerPv` | PV production power candidate | unknown | historical candidate |
| `frm` | `configPvControlPreference` / Set `pvControlPreference`; historical `roundingMode` | The module maps `0 preferFromGrid`, `1 default`, `2 preferToGrid`; unknown numeric values remain explicit. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius control-behavior labels and pinned API/Wattpilot enum/R/W evidence |
| `fst` | `configPvSurplusStartPower` / Set `pvSurplusStartPower`; historical `startingPower` | The module exposes a non-negative finite start-power value in W and provides a secured setter. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex value, official Fronius behavior documentation, pinned official go-e metadata, pinned Wattpilot-specific evidence, and maintainer live test; not official Fronius Flex WebSocket documentation |
| `fte` | `froniusTripEnergy` | Minimum next-trip energy, candidate unit Wh | R/W | historical candidate |
| `ftt` | `configNextTripTime` / Set `nextTripTime` | Current module renders seconds after local midnight as `HH:MM`; Flex writability remains unverified | R/W candidate | implementation/historical candidate |
| `ful` | `useDynamicPricing` | Dynamic-price charging enabled candidate | unknown | historical candidate |
| `fup` | `configPvSurplusEnabled` / Set `pvSurplusEnabled`; historical `usePvSurplus` | The module exposes the JSON boolean as `0`/`1` and provides a secured setter for Use PV surplus. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex boolean plus official Fronius behavior documentation and pinned API/Wattpilot R/W evidence |
| `fzf` | `configZeroFeedInEnabled` / Set `zeroFeedInEnabled`; historical `zeroFeedin` | The module exposes the JSON boolean as `0`/`1` and provides a secured setter for Zero feed-in. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex boolean plus official Fronius behavior documentation and pinned API/Wattpilot R/W evidence |
| `inva` | `inverterDataAge` | Age of inverter data, candidate unit ms | R | historical candidate |
| `mptwt` | `configMinimumPhaseSwitchInterval` / Set `minimumPhaseSwitchInterval`; historical `minPhaseToggleWaitTime` | The module exposes protocol milliseconds as public seconds and provides a secured setter for the minimum interval between phase switches. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation and pinned API/Wattpilot R/W/unit evidence |
| `mpwst` | `configPhaseSwitchDelay` / Set `phaseSwitchDelay`; historical `minPhaseWishSwitchTime` | The module exposes protocol milliseconds as public seconds and provides a secured setter for the phase-switch delay. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation and pinned API/Wattpilot R/W/unit evidence |
| `pdte` | `configPvBatteryDischargeEnabled`; app `Discharge until` | Version 2.0.8 exposes the observed boolean as `0`/`1` read-only. | Read-only compatibility implementation; writability unverified | simultaneous app `off` and status `false` on one Flex 43.4 |
| `pdt` | `configPvBatteryDischargeUntilStateOfCharge`; app `State of charge SoC` | Version 2.0.8 exposes the observed finite 0–100 value read-only. | Read-only compatibility implementation; writability unverified | simultaneous app/status value `57` on one Flex 43.4 |
| `pdle` | `configPvBatteryDischargeTimeLimitEnabled`; app `Limit discharging time` | Version 2.0.8 exposes the observed boolean as `0`/`1` read-only. | Read-only compatibility implementation; writability unverified | simultaneous app `on` and status `true` on one Flex 43.4 |
| `pdls` | `configPvBatteryDischargeStartTime`; app `Start` | Whole seconds after midnight rendered as `HH:MM`; observed `25200` = `07:00`. | Read-only compatibility implementation; writability unverified | simultaneous app/status evidence on one Flex 43.4 |
| `pdlo` | `configPvBatteryDischargeEndTime`; app `End` | Whole seconds after midnight rendered as `HH:MM`; observed `72000` = `20:00`. | Read-only compatibility implementation; writability unverified | simultaneous app/status evidence on one Flex 43.4 |
| `po` | `prioOffset` | Priority offset, candidate unit W | R/W | historical candidate |
| `psh` | `phaseSwitchHysteresis` | Phase-switch hysteresis, candidate unit W | R/W | historical candidate |
| `pvopt_averagePAkku` | `averagePAkku` | Average battery power candidate | R | historical candidate |
| `pvopt_averagePGrid` | `averagePGrid` | Average grid power candidate | R | historical candidate |
| `pvopt_averagePOhmpilot` | `avgPowerOhmpilot` | Average Ohmpilot power candidate | R | historical candidate |
| `pvopt_averagePPv` | `averagePPv` | Average PV power candidate | R | historical candidate |
| `pvopt_deltaA` | `deltaCurrent` | PV-control current difference candidate | R | historical candidate |
| `pvopt_deltaP` | `deltaPower` | PV-control power difference candidate | R | historical candidate |
| `pvopt_specialCase` | `pvOptSpecialCase` | PV-optimization special-case code candidate | R | historical candidate |
| `sh` | `stopHysteresis` | Stop hysteresis, candidate unit W | R/W | historical candidate |
| `spl3` | `configThreePhaseSwitchPower` / Set `threePhaseSwitchPower`; historical `threePhaseSwitchLevel` | The module exposes a non-negative finite value in W and provides a secured setter for the documented 3-phase power level. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation and pinned API/Wattpilot R/W/W-unit evidence |
| `zfo` | `zeroFeedinOffset` | Zero-feed-in offset, candidate unit W | R/W | historical candidate |

## Charging modes, limits, and scheduling

| Key | Alias / readable name | Meaning, range, or enum candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `awc` | `awattarCountry` | Candidate country enum: `Austria=0`, `Germany=1` | R/W | historical candidate |
| `awcp` | `awattarCurrentPrice` | Current dynamic-market price object candidate | R | historical candidate |
| `awp` | `awattarMaxPrice` | Maximum dynamic price candidate | R/W | historical candidate |
| `awpl` | `awattarPriceList` | Dynamic price list with Unix timestamps candidate | R/W candidate | historical candidate |
| `clp` | `currentLimitPresets` | Current-limit presets; historical maximum five entries | R/W | historical candidate |
| `fmt` | `configMinimumChargeTime` / Set `minimumChargeTime`; historical `minChargeTime` | The module exposes protocol milliseconds as public seconds and provides a secured setter for the documented minimum charging time. | R/W compatibility implementation; read/write/readback/restore verified on one Flex 43.4 | observed Flex number plus official Fronius behavior documentation and pinned API/Wattpilot R/W/unit evidence |
| `lmo` | `configChargingMode` / Set `chargingMode` | Current module mapping: `3 default`, `4 eco`, `5 nextTrip`; historical labels conflict (`Awattar`, `AutomaticStop`) | R/W candidate | implementation with explicit historical conflict |
| `sch_week` | `schedulerWeekday` | Weekday schedule; candidate control `Disabled=0`, `Inside=1`, `Outside=2` | R/W | historical candidate |
| `sch_satur` | `schedulerSaturday` | Saturday schedule; same control candidate | R/W | historical candidate |
| `sch_sund` | `schedulerSunday` | Sunday schedule; same control candidate | R/W | historical candidate |

## Load balancing fields

| Key | Alias / readable name | Meaning or enum candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `loa` | `loadBalancingAmpere` | Current assigned by load balancing | R | historical candidate |
| `loe` | `loadBalancingEnabled` | Load balancing enabled | R/W | historical candidate |
| `lof` | `loadFallback` | Load-balancing fallback mode candidate | R/W | historical candidate |
| `log` | `loadGroupId` | Load-balancing group identifier | R/W | historical candidate |
| `lom` | `loadBalancingMembers` | Load-balancing member list candidate | R | historical candidate |
| `lop` | `loadPriority` | Load-balancing priority candidate | R/W | historical candidate |
| `los` | `loadBalancingStatus` | Load-balancing status candidate | R | historical candidate |
| `lot` | `loadBalancingTotalAmpere` | Total current available to load balancing, candidate unit A | R/W | historical candidate |
| `loty` | `loadBalancingType` | Candidate enum: `Static=0`, `Dynamic=1` | R/W | historical candidate |
| `map` | `loadMapping` | Three-value load/phase mapping candidate | R/W | historical candidate |

## Firmware and device identity fields

| Key | Alias / readable name | Meaning candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `apd` | `firmwareDescription` | Firmware build-description object | R | historical candidate plus observed object shape |
| `arv` | `appRecommendedVersion` | Recommended app version candidate | R | historical candidate |
| `ccrv` | `chargeControllerRecommendedVersion` | Recommended charge-controller version candidate | R | historical candidate |
| `fwc` | `firmwareCarControl` | CarControl firmware version candidate | R | historical candidate |
| `fwv` | `firmwareVersion` | Wattpilot firmware version candidate | R | historical candidate |
| `mod` | `moduleHwPcbVersion` | Hardware PCB revision candidate | R | historical candidate |
| `oem` | `oemManufacturer` | OEM manufacturer candidate | R | historical candidate |
| `onv` | `otaNewestVersion` | Newest available OTA version candidate | R | historical candidate |
| `sbe` | `secureBootEnabled` | Secure boot active candidate | R | historical candidate |
| `sse` | `serialNumber` | Device serial-number field; treat as sensitive identifier | R | historical candidate |
| `typ` | `deviceType` | Device-type string candidate | R | historical candidate |
| `var` | `variant` | Candidate hardware power class: `11` for 11 kW/16 A, `22` for 22 kW/32 A | R | historical candidate |

## Time and diagnostic fields

| Key | Alias / readable name | Meaning, unit, or enum candidate | R/W candidate | Evidence |
|---|---|---|---|---|
| `loc` | `localTime` | Local device time candidate | R | historical candidate |
| `rbc` | `rebootCounter` | Device reboot count candidate | R | historical candidate |
| `rbt` | `timeSinceBoot` | Time since boot, candidate unit ms | R | historical candidate |
| `rr` | `espResetReason` | ESP reset-reason enum candidate | R | historical candidate |
| `tds` | `timezoneDaylightSavingMode` | Candidate enum: `None=0`, `EuropeanSummerTime=1`, `UsDaylightTime=2` | R/W | historical candidate |
| `tma` | `temperatureSensors` | Temperature-sensor array candidate; element mapping and unit remain unverified | R | historical candidate plus observed array shape |
| `tof` | `timezoneOffset` | Timezone offset, candidate unit minutes | R/W | historical candidate |
| `ts` | `timeServer` | Time-server hostname candidate | R candidate | historical candidate |
| `tse` | `timeServerEnabled` | NTP time synchronization enabled | R/W | historical candidate |
| `tsom` | `timeServerOperatingMode` | Candidate enum: `POLL=0`, `LISTENONLY=1` | R | historical candidate |
| `tssi` | `timeServerSyncInterval` | Time-server synchronization interval, candidate unit ms | R | historical candidate |
| `tssm` | `timeServerSyncMode` | Candidate enum: `IMMED=0`, `SMOOTH=1` | R | historical candidate |
| `tsss` | `timeServerSyncStatus` | Candidate enum: `RESET=0`, `COMPLETED=1`, `IN_PROGRESS=2` | R | historical candidate |
| `utc` | `utcTime` | UTC device time candidate | R/W candidate | historical candidate |

## Network, credential, and internal fields

The former `API.md` also contained aliases and examples for Wi-Fi configuration, cloud credentials, authentication material, network endpoints, MAC addresses, internal queues, memory statistics, OTA internals, and undocumented diagnostic keys. This companion deliberately does **not** reproduce credential-like examples or imply that those historical write claims are safe or valid for Flex.

Their observed key presence and JSON shape remain available in the sanitized empirical reference. Semantic descriptions for those fields should be added only with an explicit source, scope, sensitivity classification, and evidence level.

## Coverage limits

This catalog provides readable candidates for the operational fields that were useful in the former compilation. The empirical Flex document contains 558 direct status keys, so many observed fields still have no accepted meaning. Those remain `unknown` by design.

A future description change should update the applicable empirical field row or add a source/conflict note. Never silently promote a historical alias, go-e statement, current implementation, or third-party behavior to an official Fronius Flex guarantee.
