# Public reading categories

Version 2.1.0 classifies every public reading explicitly. Readings that expose stored or user-selectable configuration use the exact camel-case prefix `config`. The same rule applies to writable and read-only configuration values. Set-command names do not use the prefix. Related PV-battery writes are grouped below the single top-level command `pvBattery`.

There are no compatibility aliases, duplicate old/new readings, automatic reading migration, or DbLog migration. Existing automations and history queries must be adapted explicitly.

Set-command discovery is independent of reading classification. The command list is generated centrally, marks `reconnect` as `reconnect:noArg`, and remains available for `set <name> ?` while `disable=1`; actual commands remain blocked in that state.

| Internal key | Public reading | Category | Reason |
|---|---|---|---|
| `state` | `state` | lifecycle | Module connection/authentication lifecycle. |
| `firmware_version` | `firmwareVersion` | identity | Device firmware identity, not a user setting. |
| `auth_hash_mode` | `authHashMode` | diagnostic | Effective authentication method selected for the current session. |
| `car_state` | `carState` | status | Current vehicle/charging-port state. |
| `force_state` | `configForceState` | configuration | User-selectable force-state setting; Set command remains `forceState`. |
| `charging_current` | `configChargingCurrent` | configuration | Requested/configured charging current; Set command remains `chargingCurrent`. |
| `charging_mode` | `configChargingMode` | configuration | User-selectable charging mode; Set command remains `chargingMode`. |
| `charging_allowed` | `chargingAllowed` | status | Current device decision whether charging is allowed. |
| `charging_decision_code` | `chargingDecisionCode` | diagnostic | Raw current charging-decision code. |
| `charging_decision` | `chargingDecision` | diagnostic | Compatibility text for the current charging-decision code. |
| `charging_decision_internal_code` | `chargingDecisionInternalCode` | diagnostic | Raw internal charging-decision code. |
| `charging_decision_internal` | `chargingDecisionInternal` | diagnostic | Compatibility text for the internal decision code. |
| `error_code` | `errorCode` | diagnostic | Current raw device error code. |
| `maximum_current_limit` | `configMaximumCurrentLimit` | configuration | Stored maximum-current limit exposed read-only by the module. |
| `temperature_current_limit` | `temperatureCurrentLimit` | status | Effective temperature-dependent current limit. |
| `minimum_charging_current` | `configMinimumChargingCurrent` | configuration | Stored minimum charging-current setting exposed read-only. |
| `pv_surplus_start_power` | `configPvSurplusStartPower` | configuration | PV-surplus start-power setting; Set command remains `pvSurplusStartPower`. |
| `pv_surplus_enabled` | `configPvSurplusEnabled` | configuration | PV-surplus enable setting; Set command remains `pvSurplusEnabled`. |
| `zero_feed_in_enabled` | `configZeroFeedInEnabled` | configuration | Zero-feed-in setting; Set command remains `zeroFeedInEnabled`. |
| `pv_control_preference` | `configPvControlPreference` | configuration | PV/grid control preference; Set command remains `pvControlPreference`. |
| `phase_switch_mode` | `configPhaseSwitchMode` | configuration | Phase-switch mode setting; Set command remains `phaseSwitchMode`. |
| `three_phase_switch_power` | `configThreePhaseSwitchPower` | configuration | Three-phase switching threshold; Set command remains `threePhaseSwitchPower`. |
| `phase_switch_delay` | `configPhaseSwitchDelay` | configuration | Phase-switch delay; Set command remains `phaseSwitchDelay`. |
| `minimum_phase_switch_interval` | `configMinimumPhaseSwitchInterval` | configuration | Minimum phase-switch interval; Set command remains `minimumPhaseSwitchInterval`. |
| `minimum_charge_time` | `configMinimumChargeTime` | configuration | Minimum charging time; Set command remains `minimumChargeTime`. |
| `charging_pause_allowed` | `configChargingPauseAllowed` | configuration | Charging-pause setting; Set command remains `chargingPauseAllowed`. |
| `minimum_charging_pause_duration` | `configMinimumChargingPauseDuration` | configuration | Minimum charging-pause duration; Set command remains `minimumChargingPauseDuration`. |
| `minimum_charging_interval` | `configMinimumChargingInterval` | configuration | Forced/minimum charging interval; Set command remains `minimumChargingInterval`. |
| `pv_battery_soc` | `pvBatterySoC` | telemetry | Current stationary PV-battery SOC. |
| `pv_battery_power` | `pvBatteryPower` | telemetry | Current stationary PV-battery power. |
| `pv_battery_mode_code` | `pvBatteryModeCode` | status | Current raw stationary-battery mode code. |
| `pv_battery_charge_above_soc` | `configPvBatteryChargeAboveSoC` | configuration | App setting “Charge above”; stationary PV-battery SOC threshold above which vehicle charging may start. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_enabled` | `configPvBatteryDischargeEnabled` | configuration | App switch “Discharge until”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_until_soc` | `configPvBatteryDischargeUntilSoC` | configuration | App setting “State of charge SoC” belonging to “Discharge until”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_time_limit_enabled` | `configPvBatteryDischargeTimeLimitEnabled` | configuration | App switch “Limit discharging time”. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_start_time` | `configPvBatteryDischargeStartTime` | configuration | App start time for the discharge window. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `pv_battery_discharge_stop_time` | `configPvBatteryDischargeStopTime` | configuration | App end time for the discharge window. Writable through the grouped `pvBattery` verification command; live device verification remains pending. |
| `next_trip_time` | `configNextTripTime` | configuration | Configured next-trip target time; Set command remains `nextTripTime`. |
| `energy_total` | `energyTotal` | telemetry | Total measured energy. |
| `energy_since_plug_in` | `energySincePlugIn` | telemetry | Measured energy since plug-in. |
| `voltage_l1` | `voltageL1` | telemetry | Current L1 voltage. |
| `voltage_l2` | `voltageL2` | telemetry | Current L2 voltage. |
| `voltage_l3` | `voltageL3` | telemetry | Current L3 voltage. |
| `current_l1` | `currentL1` | telemetry | Current L1 current. |
| `current_l2` | `currentL2` | telemetry | Current L2 current. |
| `current_l3` | `currentL3` | telemetry | Current L3 current. |
| `power_l1` | `powerL1` | telemetry | Current L1 power. |
| `power_l2` | `powerL2` | telemetry | Current L2 power. |
| `power_l3` | `powerL3` | telemetry | Current L3 power. |
| `power` | `power` | telemetry | Current total charging power. |
| `last_command_request_id` | `lastCommandRequestId` | command_diagnostic | Correlation ID of the latest secured command. |
| `last_command_status` | `lastCommandStatus` | command_diagnostic | State of the latest secured command. |
| `last_command_error` | `lastCommandError` | command_diagnostic | Redacted result/error text of the latest secured command. |

`authHashMode` is deliberately not a configuration reading: it reports the authentication method actually selected for the current session, which may be derived from `authHash=auto` and the device challenge. `temperatureCurrentLimit` is also deliberately not prefixed because it is an effective runtime limit rather than a stored user setting. `pvBatteryModeCode` is a current status code, not a configuration enum.
