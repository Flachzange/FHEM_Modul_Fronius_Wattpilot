# FHEM Module: 72_Wattpilot.pm - User Guide

This document describes the installation and configuration of the Fronius Wattpilot module for FHEM. The module allows control of the Wallbox over the local network via WebSocket.

Current module version: **2.1.7**. Dennis Gramespacher remains the original author. The version-2.x redesign and implementation are authored by Flachzange and were developed with AI assistance from OpenAI ChatGPT; technical decisions and release responsibility remain with Flachzange. See [`AUTHORS.md`](AUTHORS.md) for details. The change history is maintained exclusively in [`CHANGELOG.md`](CHANGELOG.md). Protocol sources and confidence boundaries are documented in [`docs/PROTOCOL-SOURCES.md`](docs/PROTOCOL-SOURCES.md).

## Differences from the original module

Version 2.x is a substantial redesign rather than a small extension of the original module.

| Area | Original module state | Current version 2.x |
| :--- | :--- | :--- |
| Definition and password | Password included in the FHEM definition | Definition without password; storage through `set <Name> password <secret>` under stable FUUID-based keys |
| Devices and authentication | Predecessor Wattpilot with PBKDF2 | Legacy profile retained; Wattpilot Flex authenticates exclusively with bcrypt |
| FHEM interface | A small set of German-named readings and Set commands | Consistent public names, 73 readings, confirmed configuration readings, and grouped Set commands |
| Protocol handling | Basic `hello`, authentication, and status handling | Strict JSON type validation, partial status handling, robust message continuation, secured commands, and response correlation |
| Runtime behavior | Basic interval and idle filtering | Controlled lifecycle behavior for reload, rename, `modify`, disable, reconnect, and delete, plus separate telemetry caches on one publication clock |
| Quality assurance | Original functional scope | Extensive regression tests, pinned FHEM-core integration, documentation checks, and reproducible release verification |

Version 2.x is not a drop-in replacement for existing definitions of the original module. It provides no aliases, automatic reading cleanup, or migration of automations and database queries. A migration should use a fresh FHEM device and deliberately adapt dependent configuration.

## Supported device generations

| Feature | Legacy Wattpilot | Wattpilot Flex |
| :--- | :--- | :--- |
| Evidenced device scope | Wattpilot Home 11/22 J 2.0 and Wattpilot Go 11/22 J 2.0 as the original device scope | Real-device tested with Wattpilot Flex Home 22 C6, firmware 43.4 |
| Authentication | PBKDF2; in the evidenced legacy profile with `devicetype=wattpilot` and `hello.protocol=2`, `authRequired.hash` may be absent | bcrypt only; `Crypt::Bcrypt` is mandatory for Wattpilot Flex |
| `authHash=auto` | Selects PBKDF2 for the evidenced missing-hash legacy profile | Expects and selects bcrypt; PBKDF2 is not a supported Flex profile |
| Extended fields | Core charging, energy, and electrical values are protected by regression tests | Additional configuration, diagnostic, and stationary-PV-battery fields are documented or real-device tested for Flex 43.4 |
| Verification status | Automated compatibility test based on a pinned Wattpilot implementation; no current real-device test | Multiple real FHEM, authentication, reading, and Set-command tests on one Flex 43.4; other Flex models and firmware versions are not fully verified |

The module does not claim generic compatibility with arbitrary go-eChargers. Fields not sent by a device do not create or change readings. For combinations without real-device testing, support remains limited to the documented compatibility contract.

## 1. Prerequisites (System & Perl Modules)

For the module to work, some additional Perl modules must be installed on the FHEM server.

### Perl packages required for all devices

* `JSON`
* `Crypt::PBKDF2`
* `Crypt::URandom`
* `Digest::SHA`
* `MIME::Base64`

`Crypt::PBKDF2` is loaded when the module starts and is therefore required even when a Wattpilot Flex later selects bcrypt.

### Additional package required for Wattpilot Flex

* `Crypt::Bcrypt`

`Crypt::Bcrypt` is mandatory for Wattpilot Flex because Flex uses bcrypt exclusively. The evidenced legacy Wattpilot profile uses PBKDF2 instead.

### Installing Packages (Debian/Raspbian/Ubuntu)

Run the following commands in the terminal:

```bash
sudo apt-get update
sudo apt-get install libjson-perl libdigest-sha-perl libmime-base64-perl
```

Use cpanminus for the additional cryptography modules:

```bash
sudo apt-get install cpanminus
sudo cpanm Crypt::PBKDF2 Crypt::URandom
```

For Wattpilot Flex, also install this mandatory package:

```bash
sudo cpanm Crypt::Bcrypt
```

## 2. Installing the Module

1. Download the file `72_Wattpilot.pm`.
2. Copy the file to the FHEM installation directory, specifically into the `FHEM` folder.
    * Default path (Linux): `/opt/fhem/FHEM/`
    * Example command: `cp 72_Wattpilot.pm /opt/fhem/FHEM/`
3. Set the correct permissions (optional, but recommended):

    ```bash
    sudo chown fhem:dialout /opt/fhem/FHEM/72_Wattpilot.pm
    sudo chmod 644 /opt/fhem/FHEM/72_Wattpilot.pm
    ```

4. Restart FHEM (enter `shutdown restart` in FHEM) or reload the module with `reload 72_Wattpilot`.

## 3. Setup in FHEM (Definition)

To integrate the Wallbox into FHEM, create a new "Device".

### Syntax

```text
define <Name> Wattpilot <IP-Address> [Serial]
```

* **<Name>**: A name for the device in FHEM (e.g., `wallbox` or `myWattpilot`).
* **<IP-Address>**: The local IP address of the Wattpilot on the network (e.g., `192.0.2.10`, reserved for documentation).
* **[Serial]** (Optional): A digits-only serial number. It is normally omitted and obtained from the device `hello` message.

### Why is the serial number needed?

The serial is not another FHEM device identifier. It is a cryptographic input: both PBKDF2 and bcrypt derive the device-specific password hash using the serial number. This applies to legacy Wattpilot devices and Wattpilot Flex.

Normally the Wattpilot sends its serial in the `hello` message before authentication, so it does not need to be part of the definition. Supplying it explicitly pins the value and is useful only when automatic acquisition does not work. A wrong serial produces the wrong derived hash and causes authentication to fail. If neither the definition nor `hello` provides a valid numeric serial, authentication ends with `authConfigMissing`.

Set the password separately with `set <Name> password <secret>`; it is not stored in the definition.

**Version display:** The Internal `VERSION` reports the module version. Firmware reported by the Wattpilot remains separate in the `deviceFirmwareVersion` reading.

### Example

Enter this into the FHEM command line:

```text
define testWallbox Wattpilot 192.0.2.10
set testWallbox password documentation-value-only
```

## 4. Functions & Commands (Control)

After defining the device, set the password first:

```text
set wallbox password <YourPassword>
```

The password is stored only under stable FUUID-based keys. Rename, reload, `rereadcfg`, disable, and normal undefine preserve those values. Only actually deleting the FHEM device removes its two stable credential keys. Password replacement and deletion are transactional and report an incomplete rollback explicitly.

Once `state` is `connected`, the following commands are available:

### Set charging current

```text
set wallbox chargingCurrent 16
```

Only integer values from 6 A upward are accepted. Once the device has confirmed a usable `configMaximumCurrentLimit`, that value becomes the dynamic upper bound, capped at 32 A; FHEMWEB adjusts the slider accordingly. Before the first confirmation, or when the reading is missing or unusable, the compatibility range remains 6 through 32 A. Internally the module sends `amp`. The `configChargingCurrent` reading changes only after device confirmation.

### Set force state

```text
set wallbox forceState neutral
set wallbox forceState off
set wallbox forceState on
```

The mapping is `neutral -> frc=0`, `off -> frc=1`, and `on -> frc=2`.

### Set charging mode

```text
set wallbox chargingMode default
set wallbox chargingMode eco
set wallbox chargingMode nextTrip
```

The mapping is `default -> lmo=3`, `eco -> lmo=4`, and `nextTrip -> lmo=5`.

### Set PV-surplus start power

```text
set wallbox pvSurplusStartPower 1400
```

The non-negative finite numeric value is sent in watts through `fst`; the confirmed reading is formatted with exactly two decimal places. The module applies no unverified upper bound. Device rejection is exposed through `lastCommandStatus` and `lastCommandError`; the reading changes only when a device-confirmed status value is received. Reading, writing, device readback, and restoration of the original value were verified with FHEM and a Wattpilot Flex running firmware 43.4.

### PV and grid control

```text
set wallbox pvSurplusEnabled 1
set wallbox zeroFeedInEnabled 0
set wallbox pvControlPreference preferFromGrid
```

These commands write `fup`, `fzf`, and `frm`. `pvControlPreference` accepts `preferFromGrid`, `default`, and `preferToGrid`, mapped to protocol values `0`, `1`, and `2`.

### Phase switching

```text
set wallbox phaseSwitch mode auto
set wallbox phaseSwitch threePhasePower 5200
set wallbox phaseSwitch delay 120
set wallbox phaseSwitch minInterval 600
```

The grouped `phaseSwitch` command writes `psm` with `auto=0`, `force1=1`, or `force3=2`, converts `delay` to `mpwst`, converts `minInterval` to `mptwt`, and writes `threePhasePower` through `spl3`. The two public time values use seconds and are sent as exact whole milliseconds. The threshold uses watts; its confirmed reading is formatted with exactly two decimal places.

### Charging and pause behavior

```text
set wallbox minimumCharging duration 300
set wallbox chargingPauseAllowed 1
set wallbox minimumCharging pauseDuration 120
set wallbox minimumCharging interval 0
```

The grouped `minimumCharging` command converts the public seconds to exact whole milliseconds and writes `duration` through `fmt`, `pauseDuration` through `mcpd`, and `interval` through `mci`. `chargingPauseAllowed` remains a separate command and writes the boolean field `fap`. The `minimumCharging interval` setting follows the pinned API alias for `mci`; the current Fronius Flex operating instructions label the vehicle setting “Forced charging interval”.

These additional setters use the existing secured `setValue` path. No reading is changed optimistically; only a device response or later status confirms the value. Field assignments use the documented combination of current Fronius operating documentation, pinned API sources, and the sanitized Flex 43.4 observation. The extended energy and phase parameters described here were changed individually on a Wattpilot Flex Home 22 C6 with firmware 43.4, confirmed through device readback, and restored to their original values.

### PV battery diagnostics

The fields `fbuf_akkuMode`, `fbuf_akkuSOC`, and `fbuf_pAkku` are published only with `diagnosticReadings=1` as the raw readings `diag_fbuf_akkuMode`, `diag_fbuf_akkuSOC`, and `diag_fbuf_pAkku`. They belong to the shared diagnostic owner; numeric values are rounded to exactly two decimal places without scaling and receive no unit or sign interpretation. `diag_fbuf_pAkku` and `diag_pvopt_averagePAkku` come from two different protocol fields; their exact distinction, aggregation, unit, and sign convention remain unconfirmed. The module deliberately provides no setters and invents no mode enum.

The module also exposes the stationary-PV-battery settings observed simultaneously in the app and `fullStatus`: `fam` as `configPvBatteryChargeAboveSoC`, `pdte` as `configPvBatteryDischargeEnabled`, `pdt` as `configPvBatteryDischargeUntilSoC`, `pdle` as `configPvBatteryDischargeTimeLimitEnabled`, `pdls` as `configPvBatteryDischargeStartTime`, and `pdlo` as `configPvBatteryDischargeStopTime`. The two clock values are rendered from whole seconds after midnight as `HH:MM`. The mapping is evidenced on one Wattpilot Flex Home 22 C6 running firmware 43.4 by exact agreement between the app values and the simultaneous status.

One grouped top-level setter is available for those fields:

```text
set wallbox pvBattery chargeAboveSoC 60
set wallbox pvBattery dischargeEnabled 1
set wallbox pvBattery dischargeUntilSoC 57
set wallbox pvBattery dischargeTimeLimitEnabled 1
set wallbox pvBattery dischargeStartTime 07:00
set wallbox pvBattery dischargeStopTime 20:00
```

`chargeAboveSoC` and `dischargeUntilSoC` accept whole values from `0` through `100`. The switches accept `0` or `1` and are sent as JSON booleans. `dischargeStartTime` accepts `00:00` through `23:59`; `dischargeStopTime` additionally accepts `24:00`. The times are sent through `pdls` and `pdlo` as seconds after midnight. No reading is updated optimistically; only a device response or later status confirms the value. All six setters were changed individually on a Wattpilot Flex Home 22 C6 running firmware 43.4, confirmed through device-supplied status/readback, and restored to their original values. Deliberate device rejection, persistence across reboot, and other firmware/model variants remain unverified.

### Rebuild the connection deliberately

```text
set wallbox reconnect
```

This local lifecycle command closes the WebSocket session, invalidates session-owned timers, authentication, and partial-JSON state, and starts exactly one new connection/authentication cycle. Existing operational readings and configuration remain intact. Pending secured commands terminate with `lastCommandStatus=failed` and `lastCommandError=reconnect requested`. The same terminal diagnostic contract applies to session loss, disable, credential changes, authentication abort, and lifecycle timeout; undefine and shutdown clear internal state without creating new reading events. The FHEMWEB Set list uses `reconnect:noArg`, so no unnecessary value field is shown. This is explicitly **not** a verified `fullStatus` request; any initial status received after login remains server-pushed by the device.

### Set next-trip time

```text
set wallbox nextTripTime 07:30
```

The format must be exactly `HH:MM`. A one-digit hour such as `7:30` is rejected. Internally the value is sent as seconds after midnight through `ftt`.

## 5. Configuration (Attributes)

You can adjust the module's behavior via "Attributes".

### `interval` (in seconds)

Controls publication of all interval readings: energy, electrical telemetry, `deviceRebootCount`, `uptime`, and enabled optional `diag_...` readings.

* Default: `0` (no rate limit).
* Recommendation: `10` or `60`.
* Energy, electrical `nrg` telemetry, device-health values, `uptime`, and optional diagnostics keep separate latest-value caches and dirty fields but use one shared interval clock. A tick publishes all eligible dirty groups in the same FHEM reading transaction and with the same timestamp. No group can block another group or refresh its reading timestamps with stale cached values.
* Inside the interval, each group retains only its latest valid state. Energy becomes dirty only when its formatted public value actually changes; identical `eto`/`wh` values renew neither timestamps nor events. Missing, `null`, wrong-type, or incomplete values do not become dirty and do not move the shared clock.
* All 24 `config...` readings remain immediate after valid device confirmation. Identity readings, `carState`, `chargingAllowed`, `temperatureCurrentLimit`, the four charging-decision readings, and `errorCode` publish immediately, but only when their public value changes.
* `fullStatus`, partial `fullStatus`, `deltaStatus`, and matched response `status` use the same policy. The first valid authenticated `fullStatus` or `deltaStatus` input completes initialization; `partial=true` describes snapshot completeness only. `interval=0` disables rate limiting. Changing a positive value to `0`, or deleting the attribute, immediately publishes already queued dirty owners that are currently eligible.
* `deltaStatus` supplies only fields sent by the device and therefore provides device-side change filtering. The repository does not infer an official per-field Flex update frequency from this; no public Fronius specification for it is evidenced.

### `update_while_idle` (0 or 1)

Controls electrical `nrg`, `uptime`, and enabled optional diagnostics while the car is **not** charging.

* `0` (Default): the gated owners (`nrg`, `uptime`, and enabled optional diagnostics) remain passive while idle, **except** for the bounded one-time Charging-to-Idle electrical refresh.
* `1`: real incoming idle values from all gated owners (`nrg`, `uptime`, and enabled optional diagnostics) are additionally processed on the shared telemetry clock.
* With either attribute value, after `car=2` changes to a valid non-charging state, one real `nrg` in the same message or within 30 seconds may bypass the clock once so only device-supplied values can correct stale readings. Changing the attribute during that episode neither creates a second timer nor cancels the existing refresh.
* No evidenced explicit Wattpilot WebSocket status request is known; the module therefore sends no `getAllValues` and invents no polling command. If no valid `nrg` arrives in the 30-second window, at most one controlled reconnect is scheduled for that idle episode. With `0`, later ordinary Idle values remain passive afterwards.
* Missing values are never interpreted as zero. Real zero values are processed only when supplied validly by the device.
* This attribute does not control energy. `energyTotal` and `energySincePlugIn` are queued for the shared clock only when their formatted value actually changes; identical status values cause no timestamp or event update. The repository does not claim in which state or at what frequency the Wattpilot sends `eto`/`wh`. Discrete status/diagnostic readings remain immediate-on-change.

### `diagnosticReadings` (0 or 1)

Controls the fifteen optional raw field-research readings whose names begin with `diag_`.

* `0` (Default): diagnostic fields are not evaluated or cached. Existing `diag_...` readings are deleted immediately and their dirty/cache state is cleared. Deleting the attribute has the same effect.
* `1`: valid scalar values from the fifteen selected protocol fields are published through the normal `interval` mechanism. They are eligible while the vehicle is charging or when `update_while_idle=1`.
* The protocol wording is retained exactly after the `diag_` prefix. JSON numbers are rounded to exactly two decimal places without scaling or conversion; strings remain unchanged and JSON booleans become `0` or `1`. No unit, meaning, or sign convention is inferred from that formatting. Missing fields, `null`, objects, arrays, and invalid values preserve the previous reading.

### `disable` (0 or 1)

Completely disables the module.

* `0` (Default): Module is active and connects.
* `1`: Module is deactivated, connection is closed, and no new connection attempts are made. Useful during maintenance.

### `verbose` (0 to 5)

Controls the verbosity of log entries in the FHEM log file.

* `1`: Errors only.
* `2`: Important events (e.g., login successful).
* `3`: Logs sent commands.
* `4`: Logs received data from Wattpilot.
* `5`: Debugging. Complete JSON messages remain suppressed unless `rawJsonLog=1` is also set.

### `rawJsonLog` (0 or 1)

The default is `0`. Complete inbound and outbound JSON messages are logged only when both `rawJsonLog=1` and `verbose=5` are set. This includes authentication and `securedMsg` frames. Enabling the attribute emits a security warning: raw data can contain authentication, network, device, and operational data. Enable it only briefly for targeted diagnostics and never share raw output without sanitizing it first.

The module uses a central write path for outbound JSON. It suppresses DevIo's own level-5 payload log only for the synchronous write call without changing the FHEM `verbose` attribute globally or persistently. `DevIo_SimpleWrite(..., 2)` receives unpacked text; DevIo determines the WebSocket opcode from its connection and `$hash->{binary}`. Complete clear-text output from Wattpilot-owned logging is produced only by the explicit raw mode described above.

Technical limit: in inspected FHEM revision `0ae38bf79d19d8d598c065bf84b3990b33063c4b`, DevIo `privacy=1` masks only the initial opening line. For WebSockets, `DevIo_OpenDev` creates an internal HttpUtils hash without `hideurl` and without inheriting `devioLoglevel`; HttpUtils can log URLs, DNS/IP results, timeouts, and connection errors at levels 4 or 5. Wattpilot preserves correct DevIo semantics for initial connection (`reopen=0`) and reconnect (`reopen=1`) and redacts its own messages. Ordinary EOF remains owned by DevIo ReadyFn; a WebSocket Close frame that removes ReadyFn and `NEXT_OPEN` receives exactly one module-owned reconnect. Authentication never starts without an actually open transport. The module cannot reliably suppress those transitive core logs through the public DevIo interface. Reliable full suppression requires an upstream FHEM change that passes privacy to HttpUtils as `hideurl` and provides suitable log/error redaction. Until then, high-verbose logs must not be treated as endpoint-free and must be protected and sanitized before sharing.

At this revision, `DevIo_DecodeWS` owns incomplete raw WebSocket-frame buffering in `.WSBUF`, but it does not use the `FIN` bit as a logical message boundary. Wattpilot therefore has no second raw-frame buffer and instead keeps a separate JSON continuation buffer bounded to 1 MiB in total. It structurally processes multiple complete concatenated JSON values, waits for the next decoded payload when a top-level object is syntactically incomplete, and atomically rejects malformed or oversized sequences. Status messages require an object; known scalar fields and the first twelve `nrg` elements are type-checked before use. Omitted `deltaStatus` fields remain unchanged.

### `authHash` (auto, pbkdf2, bcrypt)

Selects the password hashing method.

* `auto` (Default and recommended): Uses the method explicitly announced by the device. For the evidenced legacy profile `devicetype=wattpilot`, protocol 2, a missing `authRequired.hash` remains compatible and selects PBKDF2. Wattpilot Flex is supported exclusively with bcrypt. An unknown mode, or a missing mode outside the legacy profile, is rejected.
* `pbkdf2`: Forces PBKDF2. This is intended only for the evidenced legacy Wattpilot profile and is not a supported Flex method.
* `bcrypt`: Forces bcrypt. This method is mandatory for Wattpilot Flex.

## 6. Readings (Values)

The module exposes exactly these 73 public readings:

| Reading | Description |
| :--- | :--- |
| `state` | Lifecycle state: `disabled`, `passwordMissing`, `credentialError`, `connecting`, `authenticating`, `initializing`, `connected`, `disconnected`, `connectionFailed`, `authFailed`, `authTimeout`, `initializationTimeout`, `authSequenceInvalid`, `authConfigMissing`, `authChallengeInvalid`, `authHashUnsupported`, `authHashFailed`, `authHashStoreFailed`, or `authNonceFailed`. |
| `deviceFirmwareVersion` | Firmware/version string from the device `hello` message. Identical reconnect values do not renew the reading. |
| `deviceType` | Exact string from status field `typ`. |
| `deviceModel` | Exact device-reported model/group string from `grp`; no model mapping is invented. |
| `deviceSubType` | Exact subtype string from `styp`. |
| `deviceVariant` | Raw non-negative integer from `var`. |
| `deviceHelloProtocol` | Raw integer from `hello.protocol`. |
| `deviceStatusProtocol` | Raw integer from `status.proto`; no relationship to `deviceHelloProtocol` is assumed. |
| `authHashMode` | Effective mode: `pbkdf2` or `bcrypt`. |
| `carState` | `unknown`, `idle`, `charging`, `waitingForCar`, `complete`, `error`, or `unknown:<raw-value>`. |
| `configForceState` | `neutral`, `off`, `on`, or `unknown:<raw-value>`. |
| `configChargingCurrent` | Configured/requested charging current, interpreted as amperes. |
| `configChargingMode` | `default`, `eco`, `nextTrip`, or `unknown:<raw-value>`. |
| `chargingAllowed` | Boolean field `alw`, exposed as `0` or `1`. Its meaning as the current charging permission comes from pinned Wattpilot-specific third-party evidence; the Flex capture confirms the field and type. |
| `chargingDecisionCode` | Unmodified integer from `modelStatus`. |
| `chargingDecision` | Text mapping for `chargingDecisionCode`; unknown codes are exposed as `unknown:<code>`. |
| `chargingDecisionInternalCode` | Unmodified integer from `msi`. |
| `chargingDecisionInternal` | Text mapping for `chargingDecisionInternalCode`; unknown codes are exposed as `unknown:<code>`. |
| `errorCode` | Raw integer from `err`; no unconfirmed error enum is applied. |
| `configMaximumCurrentLimit` | Raw integer from `ama`; interpreted as an ampere current limit only from pinned third-party evidence. |
| `temperatureCurrentLimit` | Raw integer from `amt`; interpreted as a temperature-related ampere limit only from pinned third-party evidence. |
| `configMinimumChargingCurrent` | Raw integer from `mca`; interpreted as a minimum charging current in amperes only from pinned third-party evidence. |
| `configPvSurplusStartPower` | Non-negative finite numeric value from `fst`, exposed in watts. Pinned go-e API metadata and Wattpilot-specific evidence describe it as writable PV-surplus start power; reading and writing were confirmed on one Flex 43.4. This is not an official Fronius Flex WebSocket specification. |
| `configPvSurplusEnabled` | Boolean field `fup`, exposed as `0` or `1`. |
| `configZeroFeedInEnabled` | Boolean field `fzf`, exposed as `0` or `1`. |
| `configPvControlPreference` | `preferFromGrid`, `default`, `preferToGrid`, or `unknown:<raw-value>` from `frm`. |
| `configPhaseSwitchMode` | `auto`, `force1`, `force3`, or `unknown:<raw-value>` from `psm`. |
| `configThreePhaseSwitchPower` | Non-negative numeric value from `spl3`, exposed in watts. |
| `configPhaseSwitchDelay` | `mpwst` converted from milliseconds to seconds. |
| `configMinimumPhaseSwitchInterval` | `mptwt` converted from milliseconds to seconds. |
| `configMinimumChargeTime` | `fmt` converted from milliseconds to seconds. |
| `configChargingPauseAllowed` | Boolean field `fap`, exposed as `0` or `1`. |
| `configMinimumChargingPauseDuration` | `mcpd` converted from milliseconds to seconds. |
| `configMinimumChargingInterval` | `mci` converted from milliseconds to seconds. The name follows the API alias; the Fronius Flex manual calls the behavior Forced charging interval. |
| `diag_fbuf_akkuSOC` | Optional raw scalar from `fbuf_akkuSOC`; no percentage range, unit, or scaling is claimed. |
| `diag_fbuf_pAkku` | Optional raw scalar from `fbuf_pAkku`; distinction from `diag_pvopt_averagePAkku`, aggregation, unit, and sign remain unconfirmed. |
| `diag_fbuf_akkuMode` | Optional raw scalar from `fbuf_akkuMode`; numeric values use two decimal places and no mode enum is invented. |
| `deviceRebootCount` | Raw non-negative integer from `rbc`, published on the normal interval without idle gating. The exact protocol meaning remains unverified. |
| `uptime` | Non-negative millisecond value from `rbt`, interpreted from the live-device observation as time since device start and divided by 1,000 before rendering cumulative hours and minutes in `H:MM`. Remaining seconds and milliseconds are discarded; publication uses the normal interval while charging or with `update_while_idle=1`. |
| `diag_fbuf_pGrid` | Optional raw scalar from `fbuf_pGrid`; no meaning, unit, or sign convention is claimed. |
| `diag_fbuf_pPv` | Optional raw scalar from `fbuf_pPv`; no meaning or unit is claimed. |
| `diag_pvopt_averagePGrid` | Optional raw scalar from `pvopt_averagePGrid`; aggregation and semantics remain unknown. |
| `diag_pvopt_averagePPv` | Optional raw scalar from `pvopt_averagePPv`; aggregation and semantics remain unknown. |
| `diag_pvopt_averagePAkku` | Optional raw scalar from `pvopt_averagePAkku`; aggregation, distinction, and sign remain unknown. |
| `diag_pvopt_averagePOhmpilot` | Optional raw scalar from `pvopt_averagePOhmpilot`; aggregation and semantics remain unknown. |
| `diag_pvopt_deltaP` | Optional raw scalar from `pvopt_deltaP`; compared quantities and unit remain unknown. |
| `diag_pvopt_deltaA` | Optional raw scalar from `pvopt_deltaA`; compared quantities and unit remain unknown. |
| `diag_pvopt_specialCase` | Optional raw code from `pvopt_specialCase`; no enum is claimed. |
| `diag_fbuf_pAcTotal` | Optional raw scalar from `fbuf_pAcTotal`; the retained capture contains `null`, so type and semantics remain unknown. |
| `diag_fbuf_ohmpilotState` | Optional raw scalar from `fbuf_ohmpilotState`; the retained capture contains `null`, so type and semantics remain unknown. |
| `diag_fbuf_ohmpilotTemperature` | Optional raw scalar from `fbuf_ohmpilotTemperature`; the retained capture contains `null`, so type, unit, and semantics remain unknown. |
| `configPvBatteryChargeAboveSoC` | App setting “Charge above” from `fam`, accepted as a percentage from `0` through `100`; writable through `set <name> pvBattery chargeAboveSoC <0-100>`. |
| `configPvBatteryDischargeEnabled` | App switch “Discharge until” from `pdte`, exposed as `0` or `1`; writable through `set <name> pvBattery dischargeEnabled` with `0` or `1`. |
| `configPvBatteryDischargeUntilSoC` | Associated app setting “State of charge SoC” from `pdt`, accepted as a percentage from `0` through `100`; writable through `set <name> pvBattery dischargeUntilSoC <0-100>`. |
| `configPvBatteryDischargeTimeLimitEnabled` | App switch “Limit discharging time” from `pdle`, exposed as `0` or `1`; writable through `set <name> pvBattery dischargeTimeLimitEnabled` with `0` or `1`. |
| `configPvBatteryDischargeStartTime` | App start time from `pdls`, converted from seconds after midnight to `HH:MM`; writable through `set <name> pvBattery dischargeStartTime <HH:MM>`. |
| `configPvBatteryDischargeStopTime` | App stop time from `pdlo`, converted from seconds after midnight to `HH:MM`; writable through `set <name> pvBattery dischargeStopTime` with `HH:MM` or `24:00`. |
| `configNextTripTime` | Protocol value rendered as `HH:MM`, interpreted as seconds after midnight. |
| `energyTotal` | `eto / 1000`, formatted with two decimals. The Wh-to-kWh interpretation is implementation evidence and is not proven by the sanitized Flex capture. |
| `energySincePlugIn` | `wh`, formatted with two decimals and interpreted as Wh. |
| `voltageL1`, `voltageL2`, `voltageL3` | `nrg[0..2]`, interpreted as volts. |
| `currentL1`, `currentL2`, `currentL3` | `nrg[4..6]`, interpreted as amperes. |
| `powerL1`, `powerL2`, `powerL3` | `nrg[7..9]`, interpreted as watts. |
| `power` | `nrg[11]`, interpreted as total watts. |
| `lastCommandRequestId` | Correlation ID of the most recent secured command. |
| `lastCommandStatus` | `pending`, `success`, `failed`, or `timeout`. |
| `lastCommandError` | Concise redacted error or result text. Session termination uses stable reasons such as `connection lost`, `device disabled`, `credentials changed`, `authentication aborted`, `lifecycle timeout`, `reconnect requested`, `definition changed`, or `session replaced`. |

All 24 `config...` readings publish immediately after valid device confirmation. Identity readings and the discrete status/diagnostic readings `carState`, `chargingAllowed`, `temperatureCurrentLimit`, `chargingDecisionCode`, `chargingDecision`, `chargingDecisionInternalCode`, `chargingDecisionInternal`, and `errorCode` also publish immediately, but only on actual change; identical repetitions refresh neither timestamp nor event. Energy, electrical `nrg`, device-health values, `uptime`, and enabled raw diagnostics are limited by `interval`. They keep separate latest-value caches and dirty fields but publish on the same clock and in the same FHEM reading transaction. Energy becomes dirty only when its formatted public value changes. Missing, `null`, wrong-type, or incomplete fields preserve readings and do not move the clock.

The text values use a compatibility mapping from the pinned official go-e `modelStatus` enum. The same value table is applied to `msi` because the pinned Wattpilot-specific source describes it as an internal decision variant. This is not an official Fronius Flex specification; both raw codes therefore remain available and unmapped values stay explicit. The exact relationship, evaluation order, precedence, and any role of `cpDisabledRequest` are not confirmed for Wattpilot Flex. In particular, the module does not claim that `modelStatus` is necessarily the final/effective decision or that `msi` is necessarily a pre-CP decision. If the values differ, treat them as two device-supplied diagnostic values and do not infer a causal chain from this documentation.

**Note on aWATTar:** aWATTar is a provider or tariff name associated with dynamic electricity prices, not a technical abbreviation introduced by this module. Names containing `Awattar` in the imported go-e enum refer to price-controlled charging decisions. `Fallback` denotes the default outcome of a decision branch when no more specific charging reason applies; it does not automatically indicate a technical fault. The exact trigger and full semantics of these codes are not confirmed for Wattpilot Flex. In particular, a value such as `notChargingBecauseFallbackAwattar` alone does not prove that an aWATTar tariff is enabled.

| Code | Text value |
| :--- | :--- |
| `0` | `notChargingBecauseNoChargeCtrlData` |
| `1` | `notChargingBecauseOvertemperature` |
| `2` | `notChargingBecauseAccessControlWait` |
| `3` | `chargingBecauseForceStateOn` |
| `4` | `notChargingBecauseForceStateOff` |
| `5` | `notChargingBecauseScheduler` |
| `6` | `notChargingBecauseEnergyLimit` |
| `7` | `chargingBecauseAwattarPriceLow` |
| `8` | `chargingBecauseAutomaticStopTestLadung` |
| `9` | `chargingBecauseAutomaticStopNotEnoughTime` |
| `10` | `chargingBecauseAutomaticStop` |
| `11` | `chargingBecauseAutomaticStopNoClock` |
| `12` | `chargingBecausePvSurplus` |
| `13` | `chargingBecauseFallbackGoEDefault` |
| `14` | `chargingBecauseFallbackGoEScheduler` |
| `15` | `chargingBecauseFallbackDefault` |
| `16` | `notChargingBecauseFallbackGoEAwattar` |
| `17` | `notChargingBecauseFallbackAwattar` |
| `18` | `notChargingBecauseFallbackAutomaticStop` |
| `19` | `chargingBecauseCarCompatibilityKeepAlive` |
| `20` | `chargingBecauseChargePauseNotAllowed` |
| `22` | `notChargingBecauseSimulateUnplugging` |
| `23` | `notChargingBecausePhaseSwitch` |
| `24` | `notChargingBecauseMinPauseDuration` |
| `26` | `notChargingBecauseError` |
| `27` | `notChargingBecauseLoadManagementDoesntWant` |
| `28` | `notChargingBecauseOcppDoesntWant` |
| `29` | `notChargingBecauseReconnectDelay` |
| `30` | `notChargingBecauseAdapterBlocking` |
| `31` | `notChargingBecauseUnderfrequencyControl` |
| `32` | `notChargingBecauseUnbalancedLoad` |
| `33` | `chargingBecauseDischargingPvBattery` |
| `34` | `notChargingBecauseGridMonitoring` |
| `35` | `notChargingBecauseOcppFallback` |

The meanings and units assigned to the used `nrg` positions and to `eto`/`wh` remain implementation or historical interpretations. The documented Flex capture confirms structure and data types, but not every unit, enum meaning, or write capability independently.

## 7. Troubleshooting

* **Status remains `disconnected`, `connecting`, `connectionFailed`, `authTimeout`, or `initializationTimeout`**:
  * Check the IP address. Can the FHEM server ping the IP?
  * Are FHEM and Wattpilot on the same network? (Often issues with Guest networks).
* **Log shows "Authentication Failed"**:
  * Check the password with `set <Name> password ...`.
  * Check the device generation: legacy Wattpilot uses PBKDF2, while Wattpilot Flex uses bcrypt exclusively. Any manual override must match the device generation.
* **Perl Error in Log (`Can't locate Crypt/PBKDF2.pm`)**:
  * The prerequisites (Step 1) were not met. Install the missing Perl module.
