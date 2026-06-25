# Public reading policy

Version 2.1.4 retains the authoritative publication policy for every public
reading. The runtime source is `%WATTPILOT_READING_POLICY` in
[`72_Wattpilot.pm`](../72_Wattpilot.pm); `Wattpilot_InterfaceSnapshot` exposes
the same inventory for automated completeness checks. Reading categories,
publication behavior, idle gating, cache/history ownership, formatting, and
invalid-input handling must not be duplicated in unrelated hard-coded lists.

Stored or user-selectable configuration uses the exact camel-case prefix
`config`. Set-command names do not use that prefix. Configuration readings are
published immediately only from valid device-confirmed status values; Set
commands never update them optimistically.

Publication policies:

- `immediate`: publish every valid event or device-confirmed status value;
- `immediate-on-change`: publish a valid status value only when its formatted
  public value changed, so identical snapshots do not renew timestamps or
  create events;
- `interval`: cache the newest valid value for that telemetry owner and publish
  all eligible dirty owners on one shared interval clock. `interval=0` disables
  rate limiting and publishes eligible dirty values immediately.

The data owners `energy`, `nrg`, and `battery` keep separate caches and dirty
fields but share one flush timer and one FHEM reading transaction. Input from
one owner neither publishes cached values nor changes dirty state for another.
The `electrical` and `battery` idle gates are controlled by
`update_while_idle`. Energy has no artificial idle gate, but it becomes dirty
only when its formatted public value differs from the published reading;
identical snapshots therefore renew neither timestamps nor events. Missing,
`null`, wrong-type, malformed, out-of-range, or incomplete input preserves the
previous reading and does not move the shared clock.

Public measured and calculated physical values use `decimal2`, retaining trailing zeroes and normalizing rounded negative zero to positive zero. Explicit exceptions remain visible in the same inventory: `pvBatterySoC` uses `decimal1`; booleans, integer codes and intentionally integral settings use `boolean` or `integer`; percentages use `percentage`; clocks and durations use `clock` or `seconds`; text and enums retain their documented form. Validation always precedes formatting.

There are no compatibility aliases, duplicate old/new readings, automatic
reading migration, or DbLog migration. Existing automations and history
queries must be adapted explicitly.

| Internal key | Public reading | Category | Source | Publication | Idle gate | Owner | Formatter | Invalid input | Reason |
|---|---|---|---|---|---|---|---|---|---|
| `state` | `state` | `lifecycle` | `event:connection` | `immediate` | `none` | `connection` | `lifecycle` | `preserve` | Module connection/authentication lifecycle. |
| `firmware_version` | `firmwareVersion` | `identity` | `event:hello` | `immediate` | `none` | `identity` | `text` | `preserve` | Device firmware identity, not a user setting. |
| `auth_hash_mode` | `authHashMode` | `diagnostic` | `event:authentication` | `immediate` | `none` | `authentication` | `enum` | `preserve` | Effective authentication method selected for the current session. |
| `car_state` | `carState` | `status` | `status:car` | `immediate-on-change` | `none` | `car` | `enum` | `preserve` | Current vehicle/charging-port state. |
| `force_state` | `configForceState` | `configuration` | `status:frc` | `immediate` | `none` | `frc` | `enum` | `preserve` | User-selectable force-state setting; Set command remains `forceState`. |
| `charging_current` | `configChargingCurrent` | `configuration` | `status:amp` | `immediate` | `none` | `amp` | `integer` | `preserve` | Requested/configured charging current; Set command remains `chargingCurrent`. |
| `charging_mode` | `configChargingMode` | `configuration` | `status:lmo` | `immediate` | `none` | `lmo` | `enum` | `preserve` | User-selectable charging mode; Set command remains `chargingMode`. |
| `charging_allowed` | `chargingAllowed` | `status` | `status:alw` | `immediate-on-change` | `none` | `alw` | `boolean` | `preserve` | Current device decision whether charging is allowed. |
| `charging_decision_code` | `chargingDecisionCode` | `diagnostic` | `status:modelStatus` | `immediate-on-change` | `none` | `modelStatus` | `integer` | `preserve` | Raw current charging-decision code. |
| `charging_decision` | `chargingDecision` | `diagnostic` | `status:modelStatus` | `immediate-on-change` | `none` | `modelStatus` | `enum` | `preserve` | Compatibility text for the current charging-decision code. |
| `charging_decision_internal_code` | `chargingDecisionInternalCode` | `diagnostic` | `status:msi` | `immediate-on-change` | `none` | `msi` | `integer` | `preserve` | Raw internal charging-decision code. |
| `charging_decision_internal` | `chargingDecisionInternal` | `diagnostic` | `status:msi` | `immediate-on-change` | `none` | `msi` | `enum` | `preserve` | Compatibility text for the internal decision code. |
| `error_code` | `errorCode` | `diagnostic` | `status:err` | `immediate-on-change` | `none` | `err` | `integer` | `preserve` | Current raw device error code. |
| `maximum_current_limit` | `configMaximumCurrentLimit` | `configuration` | `status:ama` | `immediate` | `none` | `ama` | `integer` | `preserve` | Stored maximum-current limit exposed read-only by the module. |
| `temperature_current_limit` | `temperatureCurrentLimit` | `status` | `status:amt` | `immediate-on-change` | `none` | `amt` | `integer` | `preserve` | Effective temperature-dependent current limit. |
| `minimum_charging_current` | `configMinimumChargingCurrent` | `configuration` | `status:mca` | `immediate` | `none` | `mca` | `integer` | `preserve` | Stored minimum charging-current setting exposed read-only. |
| `pv_surplus_start_power` | `configPvSurplusStartPower` | `configuration` | `status:fst` | `immediate` | `none` | `fst` | `decimal2` | `preserve` | PV-surplus start-power setting; Set command remains `pvSurplusStartPower`. |
| `pv_surplus_enabled` | `configPvSurplusEnabled` | `configuration` | `status:fup` | `immediate` | `none` | `fup` | `boolean` | `preserve` | PV-surplus enable setting; Set command remains `pvSurplusEnabled`. |
| `zero_feed_in_enabled` | `configZeroFeedInEnabled` | `configuration` | `status:fzf` | `immediate` | `none` | `fzf` | `boolean` | `preserve` | Zero-feed-in setting; Set command remains `zeroFeedInEnabled`. |
| `pv_control_preference` | `configPvControlPreference` | `configuration` | `status:frm` | `immediate` | `none` | `frm` | `enum` | `preserve` | PV/grid control preference; Set command remains `pvControlPreference`. |
| `phase_switch_mode` | `configPhaseSwitchMode` | `configuration` | `status:psm` | `immediate` | `none` | `psm` | `enum` | `preserve` | Phase-switch mode setting; writable through `phaseSwitch mode`. |
| `three_phase_switch_power` | `configThreePhaseSwitchPower` | `configuration` | `status:spl3` | `immediate` | `none` | `spl3` | `decimal2` | `preserve` | Three-phase switching threshold; Set command remains `threePhaseSwitchPower`. |
| `phase_switch_delay` | `configPhaseSwitchDelay` | `configuration` | `status:mpwst` | `immediate` | `none` | `mpwst` | `seconds` | `preserve` | Phase-switch delay; writable through `phaseSwitch delay`. |
| `minimum_phase_switch_interval` | `configMinimumPhaseSwitchInterval` | `configuration` | `status:mptwt` | `immediate` | `none` | `mptwt` | `seconds` | `preserve` | Minimum phase-switch interval; writable through `phaseSwitch minInterval`. |
| `minimum_charge_time` | `configMinimumChargeTime` | `configuration` | `status:fmt` | `immediate` | `none` | `fmt` | `seconds` | `preserve` | Minimum charging time; writable through `minimumCharging duration`. |
| `charging_pause_allowed` | `configChargingPauseAllowed` | `configuration` | `status:fap` | `immediate` | `none` | `fap` | `boolean` | `preserve` | Charging-pause setting; Set command remains `chargingPauseAllowed`. |
| `minimum_charging_pause_duration` | `configMinimumChargingPauseDuration` | `configuration` | `status:mcpd` | `immediate` | `none` | `mcpd` | `seconds` | `preserve` | Minimum charging-pause duration; writable through `minimumCharging pauseDuration`. |
| `minimum_charging_interval` | `configMinimumChargingInterval` | `configuration` | `status:mci` | `immediate` | `none` | `mci` | `seconds` | `preserve` | Forced/minimum charging interval; writable through `minimumCharging interval`. |
| `pv_battery_soc` | `pvBatterySoC` | `telemetry` | `status:fbuf_akkuSOC` | `interval` | `battery` | `battery` | `decimal1` | `preserve` | Current stationary PV-battery SOC. |
| `pv_battery_power` | `pvBatteryPower` | `telemetry` | `status:fbuf_pAkku` | `interval` | `battery` | `battery` | `decimal2` | `preserve` | Current stationary PV-battery power. |
| `pv_battery_mode_code` | `pvBatteryModeCode` | `status` | `status:fbuf_akkuMode` | `immediate-on-change` | `none` | `fbuf_akkuMode` | `integer` | `preserve` | Current raw stationary-battery mode code. |
| `pv_battery_charge_above_soc` | `configPvBatteryChargeAboveSoC` | `configuration` | `status:fam` | `immediate` | `none` | `fam` | `percentage` | `preserve` | App setting “Charge above”; stationary PV-battery SOC threshold above which vehicle charging may start. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_enabled` | `configPvBatteryDischargeEnabled` | `configuration` | `status:pdte` | `immediate` | `none` | `pdte` | `boolean` | `preserve` | App switch “Discharge until”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_until_soc` | `configPvBatteryDischargeUntilSoC` | `configuration` | `status:pdt` | `immediate` | `none` | `pdt` | `percentage` | `preserve` | App setting “State of charge SoC” belonging to “Discharge until”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_time_limit_enabled` | `configPvBatteryDischargeTimeLimitEnabled` | `configuration` | `status:pdle` | `immediate` | `none` | `pdle` | `boolean` | `preserve` | App switch “Limit discharging time”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_start_time` | `configPvBatteryDischargeStartTime` | `configuration` | `status:pdls` | `immediate` | `none` | `pdls` | `clock` | `preserve` | App start time for the discharge window. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_stop_time` | `configPvBatteryDischargeStopTime` | `configuration` | `status:pdlo` | `immediate` | `none` | `pdlo` | `clock` | `preserve` | App end time for the discharge window. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `next_trip_time` | `configNextTripTime` | `configuration` | `status:ftt` | `immediate` | `none` | `ftt` | `clock` | `preserve` | Configured next-trip target time; Set command remains `nextTripTime`. |
| `energy_total` | `energyTotal` | `telemetry` | `status:eto` | `interval` | `none` | `energy` | `decimal2` | `preserve` | Total measured energy; queued only when the formatted public value changes, then published on the shared telemetry tick. |
| `energy_since_plug_in` | `energySincePlugIn` | `telemetry` | `status:wh` | `interval` | `none` | `energy` | `decimal2` | `preserve` | Measured energy since plug-in; queued only when the formatted public value changes, then published on the shared telemetry tick. |
| `voltage_l1` | `voltageL1` | `telemetry` | `status:nrg[0]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L1 voltage. |
| `voltage_l2` | `voltageL2` | `telemetry` | `status:nrg[1]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L2 voltage. |
| `voltage_l3` | `voltageL3` | `telemetry` | `status:nrg[2]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L3 voltage. |
| `current_l1` | `currentL1` | `telemetry` | `status:nrg[4]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L1 current. |
| `current_l2` | `currentL2` | `telemetry` | `status:nrg[5]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L2 current. |
| `current_l3` | `currentL3` | `telemetry` | `status:nrg[6]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L3 current. |
| `power_l1` | `powerL1` | `telemetry` | `status:nrg[7]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L1 power. |
| `power_l2` | `powerL2` | `telemetry` | `status:nrg[8]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L2 power. |
| `power_l3` | `powerL3` | `telemetry` | `status:nrg[9]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current L3 power. |
| `power` | `power` | `telemetry` | `status:nrg[11]` | `interval` | `electrical` | `nrg` | `decimal2` | `preserve` | Current total charging power. |
| `last_command_request_id` | `lastCommandRequestId` | `command_diagnostic` | `event:response` | `immediate` | `none` | `command` | `integer` | `preserve` | Correlation ID of the latest secured command. |
| `last_command_status` | `lastCommandStatus` | `command_diagnostic` | `event:response` | `immediate` | `none` | `command` | `enum` | `preserve` | State of the latest secured command. |
| `last_command_error` | `lastCommandError` | `command_diagnostic` | `event:response` | `immediate` | `none` | `command` | `text` | `preserve` | Redacted result/error text of the latest secured command. |

`authHashMode` is deliberately not a configuration reading: it reports the
authentication method actually selected for the current session, which may be
derived from `authHash=auto` and the device challenge.
`temperatureCurrentLimit` is an effective runtime limit rather than a stored
user setting. `pvBatteryModeCode` is a discrete current status code, not a
configuration enum and not part of the interval-controlled battery telemetry.
Paired decision code/text readings share one source and are updated in the same
FHEM reading transaction.
