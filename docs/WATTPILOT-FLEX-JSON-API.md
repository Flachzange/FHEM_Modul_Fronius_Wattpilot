# Observed Wattpilot Flex JSON/WebSocket API

> This is an empirical, sanitized observation from one Wattpilot Flex installation. It is not a published Fronius API specification. Structure and JSON types are observed; meanings, units, enums, requiredness, and writability remain `unknown` unless a narrower confidence statement is shown.

## Scope and capture conditions

- Model/group: `Wattpilot Flex Home 22 C6`
- Device type: `wattpilot_flex`
- Firmware: `43.4`
- Protocol: `4`
- Authentication mode reported in status: `bcrypt`
- Capture date: 2026-06-21
- Source: maintainer-provided FHEM log capture, published only after sanitization in Issue #11
- Observed message: one `fullStatus` with `partial:false` and exactly 558 direct status keys
- Fixture: [`t/fixtures/fullStatus-flex-observed.json`](../t/fixtures/fullStatus-flex-observed.json)
- Fixture SHA-256 (UTF-8, Python `json.dumps(..., indent=2)`, final LF): `ca8f70cd954ebd70684744386660b80b4ce6a2cc0a5ab7751c27b59676b09d33`

The original raw capture is not published. Sanitization replaced identifiers, network coordinates, authentication material, exact operational counters, market data, and installation-specific labels while preserving the complete key set, object nesting, array lengths, null positions, JSON scalar types, and representative values. Therefore examples prove shape and type, not original live values.

No real protocol exchange was performed for this documentation change. The capture does not establish behavior on other models, firmware, protocol versions, configurations, or runtime states. A key name, value, historical alias, current implementation, or third-party library does not by itself prove meaning or writability.

## Evidence and confidence classes

| Class | Meaning in this document |
| --- | --- |
| Empirical structure/value | Present in the sanitized 2026-06-21 capture. Confirms location and JSON type for this one observation only. |
| Current implementation behavior | Directly visible in root `72_Wattpilot.pm`; describes what FHEM 1.x currently does, not what the device specification promises. |
| Historical compilation | Present in `API.md`; retained for research but not accepted as current protocol fact. |
| Planned interface | Naming requested in Issue #13; documentation only, not active runtime behavior. |
| Inferred | Plausible interpretation without sufficient Wattpilot-specific confirmation. |
| Unknown | Not established by the accepted evidence. |

No field in this document is classified as officially documented by Fronius. See [protocol sources](PROTOCOL-SOURCES.md).

## Message types

Examples in this section are minimal synthetic documentation values unless explicitly called the observed fixture. Tokens, hashes, HMACs, and request identifiers are placeholders.

### `hello`

- Direction: device → client in the historical flow.
- Observed/required fields: not present in the accepted capture. Current 1.x code handles `type`, reads `serial` if no serial is configured, and reads `version`.
- Example: `{"type":"hello","serial":"10000001","version":"43.4"}`
- Evidence: current implementation behavior plus historical compilation; not observed in the Issue #11 dataset.
- Open questions: actual Flex 43.4 field set, ordering, requiredness, `protocol`, `secured`, and relationship to status identity fields are unknown.

### `authRequired`

- Direction: device → client in the current implementation.
- Observed/required fields: current code consumes `token1`, `token2`, and optionally `hash`; automatic selection uses bcrypt only when `hash` equals `bcrypt`, otherwise PBKDF2.
- Example: `{"type":"authRequired","token1":"<TOKEN1>","token2":"<TOKEN2>","hash":"bcrypt"}`
- Evidence: current implementation behavior; the status capture independently contains `authhash:"bcrypt"`, but does not prove the challenge field.
- Open questions: exact Flex challenge shape, token format/length, whether `hash` is always present, and whether `authhash` and challenge `hash` are equivalent.

### `auth`

- Direction: client → device in the current implementation.
- Fields emitted by 1.x: `type`, random hexadecimal `token3`, and derived `hash`.
- Example: `{"type":"auth","token3":"<TOKEN3>","hash":"<AUTH_HASH>"}`
- Evidence: current implementation behavior; not observed in the accepted capture.
- Open questions: device-side validation rules and all protocol-version differences.

### `authSuccess`

- Direction: device → client in the current implementation.
- Fields used by 1.x: only `type`.
- Example: `{"type":"authSuccess"}`
- Evidence: current implementation behavior; not observed in the accepted capture.
- Open questions: additional Flex fields and requiredness.

### `authError`

- Direction: device → client in the current implementation.
- Fields used by 1.x: only `type`; the module marks authentication failed and closes DevIo.
- Example: `{"type":"authError","message":"<SANITIZED_ERROR>"}`
- Evidence: current implementation behavior; `message` is a historical candidate, not accepted as required.
- Open questions: actual Flex error fields, codes, and retry semantics.

### `fullStatus`

- Direction: device → client.
- Observed fields: `type:"fullStatus"`, `partial:false`, and `status` with 558 direct keys.
- Example: the complete observed example is the fixture linked above; it is not duplicated inline to avoid two independently editable copies.
- Evidence: direct empirical structure/value observation.
- Open questions: `partial:true` behavior is described historically but was not observed here; chunk ordering, completion rules, omissions, and behavior under other configurations are unknown.

### `deltaStatus`

- Direction: device → client in the current implementation/historical flow.
- Fields handled by 1.x: `type` and `status`.
- Example: `{"type":"deltaStatus","status":{"amp":16}}`
- Evidence: current implementation behavior and an explicitly synthetic existing fixture; not observed in the accepted capture.
- Repository invariant: an omitted key is an absent partial update and must not delete or reset an existing reading.
- Open questions: actual Flex 43.4 delta shapes, whether `partial` occurs, batching, and ordering.

### `setValue`

- Direction: client → device, nested as text in `securedMsg.data` by current 1.x.
- Fields emitted by 1.x: `type`, numeric `requestId`, `key`, and `value`.
- Example: `{"type":"setValue","requestId":1,"key":"amp","value":16}`
- Evidence: current implementation behavior only. This does not establish device acceptance or field writability.
- Open questions: accepted keys, values, units, validation errors, and whether unsigned forms exist.

### `securedMsg`

- Direction: client → device in current 1.x.
- Fields emitted by 1.x: `type`, JSON-text `data`, string `requestId` suffixed with `sm`, and hexadecimal `hmac`.
- Example: `{"type":"securedMsg","data":"{\"type\":\"setValue\",\"requestId\":1,\"key\":\"amp\",\"value\":16}","requestId":"1sm","hmac":"<HMAC>"}`
- Evidence: current implementation behavior; not observed in the accepted capture.
- Open questions: canonical serialization requirements, response correlation, replay behavior, and protocol-version differences.

### `response`

- Direction: device → client in the historical compilation.
- Candidate fields: `type`, `requestId`, `success`, and `status`.
- Example: `{"type":"response","requestId":"1","success":true,"status":{"amp":16}}`
- Evidence: historical compilation only; current 1.x parser does not handle this type and the accepted capture does not contain it.
- Open questions: complete Flex 43.4 schema, error shape, request-ID type, and whether status is always returned.

## Observed arrays

Every array below is present somewhere beneath `status`. Lengths, nesting, values, and null positions are empirical fixture structure; element semantics remain unknown unless separately stated.

| JSON path | Length | Null positions (zero-based) | Complete sanitized observed array |
| --- | ---: | --- | --- |
| `status.wifis` | 10 | none | `[{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"}]` |
| `status.scan` | 1 | none | `[{"ssid":"-","encryptionType":0,"rssi":0,"channel":0,"bssid":"00:00:00:00:00:00","f":[0,0,false,false,false,false,false,false,false,""]}]` |
| `status.scan[0].f` | 10 | none | `[0,0,false,false,false,false,false,false,false,""]` |
| `status.cce.ipv6` | 1 | none | `["2001:db8::33"]` |
| `status.dns.resolv` | 6 | none | `["# Generated by pynwm","# pynwm-wlan0","# pynwm-ap0","# pynwm-eth0","nameserver 192.0.2.1","# pynwm-enu1"]` |
| `status.led.ranges` | 1 | none | `[{"from":0,"to":63,"fade":"2048ms","colors0":["#0000FF"],"colors1":["#000000"]}]` |
| `status.led.ranges[0].colors0` | 1 | none | `["#0000FF"]` |
| `status.led.ranges[0].colors1` | 1 | none | `["#000000"]` |
| `status.clp` | 5 | none | `[10,16,20,24,32]` |
| `status.sch_week.ranges` | 2 | none | `[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]` |
| `status.sch_satur.ranges` | 2 | none | `[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]` |
| `status.sch_sund.ranges` | 2 | none | `[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]` |
| `status.pha` | 6 | none | `[false,false,false,true,true,true]` |
| `status.tma` | 6 | 0, 1 | `[null,null,39,41,40,38.5]` |
| `status.nrg` | 16 | none | `[230,230.1,229.9,0,0,0,0,0,0,0,0,0,0,0,0,0]` |
| `status.awpl.marketprice` | 14 | none | `[0.1,0,0.05,0.02,0.01,0.03,1.25,7.75,11.5,13.25,15,15,14.5,13.25]` |
| `status.map` | 3 | none | `[1,2,3]` |
| `status.ocu` | 1 | none | `["43.4"]` |
| `status.tpck` | 26 | none | `["chargectrl_v4","led","wifi","webserver","mdns","time","cloud","rfid","status","froniusinverter","froniussmartmeterip","fronius_hmi","tamper","delta_http","delta_cloud","ota_autoupdate","ota_cloud","cmdhandler","loadbalancing","modbus_slave","ocpp","remotehttp","remotemdns","offlinestorage","systemdwatchdog","cloud_send"]` |
| `status.tpcm` | 26 | none | `[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]` |
| `status.cc4rv` | 4 | none | `[60,229907,229932,230529]` |
| `status.cc4rc` | 4 | none | `[0,26,26,26]` |
| `status.cc4rp` | 4 | none | `[0,-12,43,225]` |
| `status.cc4ap` | 4 | none | `[0,5977,5978,5993]` |
| `status.cc4fm` | 4 | none | `[49936,49978,49978,49980]` |
| `status.cc4pm` | 4 | none | `[0,60455,180665,300425]` |
| `status.cc4re` | 4 | none | `[0,0,0,0]` |
| `status.cc4ae` | 4 | none | `[0,0,0,0]` |
| `status.fuzz` | 0 | none | `[]` |

### `nrg` interpretation boundary

The observed array has exactly 16 numeric elements: `[230,230.1,229.9,0,0,0,0,0,0,0,0,0,0,0,0,0]`. Current 1.x maps indices 0–2 to `Voltage_L1..3`, 4–6 to `Current_L1..3`, 7–9 to `Power_L1..3`, and 11 to `power`, formatting each to two decimals. Those index meanings and units are implementation interpretations, not confirmed by this capture. Indices 3, 10, and 12–15 remain unknown here.

## Enum candidates and phase state

| Key | Observed value | Candidate mapping | Evidence/confidence |
| --- | --- | --- | --- |
| `car` | `3` | Current 1.x candidates: 0 Unknown, 1 Idle, 2 Charging, 3 WaitCar, 4 Complete, 5 Error | Current implementation only; capture directly observes only numeric 3. |
| `frc` | `0` | Current 1.x candidates: 0 Start, 1 Stop | Current implementation only; capture directly observes only numeric 0; writability unverified. |
| `lmo` | `4` | Current 1.x candidates: 3 Default, 4 Eco, 5 NextTrip | Current implementation only; capture directly observes only numeric 4; writability unverified. |
| `modelStatus` | `23` | unknown | Numeric value directly observed; no enum meaning accepted. |
| `pha` | `[false,false,false,true,true,true]` | unknown phase-status flags | Shape and booleans observed; index meanings and phase-state semantics unknown. |

No go-e enum is promoted to Wattpilot fact here. Historical or third-party candidates require independent Wattpilot-specific evidence.

## Current FHEM mapping and planned 2.0 names

The current columns describe root `72_Wattpilot.pm` at the branch baseline. Planned names are copied from the Issue #11 comment that references Issue #13 and are not implemented by this change.

| Protocol key/path | Meaning/unit at supported confidence | Current 1.x FHEM name | Planned 2.0 FHEM name | Conversion/enum/rate limiting | Confidence |
| --- | --- | --- | --- | --- | --- |
| hello `version` | version string used by module | `version` | `firmwareVersion` | copied immediately | current implementation; actual Flex hello unobserved |
| `car` | inferred vehicle state | `CarState` | `carState` | 0 Unknown, 1 Idle, 2 Charging, 3 WaitCar, 4 Complete, 5 Error; immediate; also gates high-frequency updates | current implementation inference |
| `frc` | inferred forced state | `Laden_starten` | `forceState` | read: 0 Start, 1 Stop; write: Start→0, Stop→1; immediate | current implementation; device writability unverified |
| `amp` | inferred current limit/A | `Strom` | `chargingCurrent` | copied immediately; write accepts integer syntax and sends value | current implementation; device writability/range unverified by capture |
| `lmo` | inferred charging mode | `Modus` | `chargingMode` | 3 Default, 4 Eco, 5 NextTrip; immediate; same candidates sent | current implementation; device writability unverified |
| `ftt` | inferred seconds after midnight | `Zeit_NextTrip` | `nextTripTime` | read seconds→HH:MM; write HH:MM→seconds; immediate | current implementation; unit/writability unverified |
| `eto` | inferred total energy | `EnergyTotal` | `energyTotal` | divides by 1000 and formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `wh` | inferred energy since plug-in | `Energie_seit_Anstecken` | `energySincePlugIn` | formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `nrg[0..2]` | inferred phase voltages | `Voltage_L1..3` | `voltageL1..3` | formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `nrg[4..6]` | inferred phase currents | `Current_L1..3` | `currentL1..3` | formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `nrg[7..9]` | inferred phase powers | `Power_L1..3` | `powerL1..3` | formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `nrg[11]` | inferred total power | `power` | not specified in Issue #13 comment | formats 2 decimals; rate-limited and charging/idle gated | current implementation inference |
| `authRequired.hash` / status `authhash` | authentication mode candidate | `authHashMode` plus `authHash` attribute | not specified | auto chooses bcrypt only for challenge `hash:"bcrypt"`, else PBKDF2; status `authhash` is not consumed | current implementation plus separate observed status value; equivalence unknown |
| outbound `setValue` in `securedMsg` | authenticated command envelope | internal only | internal only | numeric request ID, JSON text, HMAC-SHA256, outer request ID with `sm` suffix | current implementation; protocol acceptance unverified |

The current module applies `interval` only to `eto`, `wh`, and `nrg`-derived readings. They update only after the interval and while the cached `car` state is Charging, unless `update_while_idle=1`. `car`, `frc`, `ftt`, `amp`, and `lmo` are updated immediately when present. Missing `deltaStatus` keys are untouched.

## Complete observed status-key reference

There is exactly one row for each of the 558 direct keys beneath `status`. “Observation only” never means writable.

| Key | Observed JSON type | Sanitized observed example | Meaning | Unit | R/W evidence | Confidence | Sources/conflicts |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `abm` | string | `"00:00:00:00:00:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `acl` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `acs` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `acu` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `acui` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `adi` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ado` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `al1` | number | `10` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `al2` | number | `16` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `al3` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `al4` | number | `24` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `al5` | number | `32` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `alw` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `alwt` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ama` | number | `32` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `amp` | number | `32` | Current 1.x implementation interprets this as configured charging current. | A (implementation interpretation) | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; value `32` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `amt` | number | `32` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ana` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `apd` | object | `{"project_name":"wattpilot_flex-secure-release","version":"43.4","secure_version":0,"timestamp":"Apr 28 2026 12:58:50","idf_ver":"43.4","sha256":"8154f5f8ffcfc41f428b355625604c86ffd158ac"}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `app` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `art` | string | `"4,240,187"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `arv` | string | `"1.2.1"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `asc` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `aup` | number | `6` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `aus` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `aut` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `authhash` | string | `"bcrypt"` | Authentication-mode identity value in the observed payload. | unknown | observation only; no writability evidence | empirical value bcrypt; relationship to authRequired.hash remains unverified | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `avgfhz` | number | `19.99413109` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `awc` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `awcp` | object | `{"start":1767268800,"end":1767272400,"marketprice":0.1}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `awp` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `awpl` | object | `{"marketprice":[0.1,0,0.05,0.02,0.01,0.03,1.25,7.75,11.5,13.25,15,15,14.5,13.25],"start":1767268800,"interval":3600}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `bam` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `bpwm0` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `bpwm1` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `bpwm2` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `bpwm3` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c0e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c0i` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c0n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c1e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c1i` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c1n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c2e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c2i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c2n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c3e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c3i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c3n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c4e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c4i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c4n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c5e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c5i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c5n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c6e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c6i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c6n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c7e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c7i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c7n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c8e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c8i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c8n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c9e` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c9i` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `c9n` | string | `"n/a"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cae` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cak` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `car` | number | `3` | Current 1.x implementation interprets this as vehicle/charging state. | unknown | read by 1.x; no write path | inferred from current implementation; only value `3` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cbdt` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cble` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cbm` | string | `"00:00:00:00:00:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cbtt` | number | `22` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4` | object | `{"firmware_version":"0.0.17-8","firmware_crc":"0x5CC8","firmware_integrity":"verified","stack_size":15464,"reset_reason":"\|por\|pin","mid_firmware_version":"BDDF3FF","hwid":"phnx-rts-rev6"}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc42l` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ae` | array | `[0,0,0,0]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ap` | array | `[0,5977,5978,5993]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ca` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4cd` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4cs` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4dc` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4fm` | array | `[49936,49978,49978,49980]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4fu` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4i1` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4is` | number | `4` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4lc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ld` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ls` | number | `32000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4lt` | number | `32000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4nl` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4pm` | array | `[0,60455,180665,300425]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4pp` | number | `240` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4rc` | array | `[0,26,26,26]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4re` | array | `[0,0,0,0]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4rf` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4rp` | array | `[0,-12,43,225]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4rv` | array | `[60,229907,229932,230529]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4sf` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4sp` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4ss` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4st` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4sv` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4tl` | number | `32000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4tm` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4tt` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4tv` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4vm` | number | `9031` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4vr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cc4vx` | number | `9059` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cca` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cce` | object | `{"speed":"100M","dup":"full","ip":"192.0.2.33","ipv6":["2001:db8::33"]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cch` | string | `"#FEFEFE"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cci` | object | `{"id":"<INVERTER_ID>","paired":true,"deviceFamily":"DataManager","label":"<PV_SYSTEM_LABEL>","model":"PILOT","commonName":"","ip":"192.0.2.30","connected":true,"reachableMdns":false,"reachableUdp":true,"reachableHttp":true,"status":0,"message":"ok"}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cco` | number | `22` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ccrv` | string | `"0"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ccsm` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ccu` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ccw` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cdci` | number | `2000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cdi` | object | `{"type":1,"value":0}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cert` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cfi` | string | `"#00FF00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cgc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `chr` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cid` | string | `"#0000FF"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cle` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `clea` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cll` | object | `{"cableCurrentLimit":32,"currentLimitMax":32,"loadLimit":0,"requestedCurrent":32,"temperatureCurrentLimit":32,"unsymetryCurrentLimit":32}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `clp` | array | `[10,16,20,24,32]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cnt` | number | `10000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cot` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cpe` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cpi` | number | `15` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cpr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cpt` | number | `15` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `csd` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ct` | string | `"<VEHICLE_TYPE>"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cup` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cwc` | string | `"#FFFF00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cwe` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cws` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cwsc` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cwsca` | number | `62057202` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `cy` | string | `"germany"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `data` | string | `"{\"i\":120,\"url\":\"https://example.invalid/wattpilot/data?e=<REDACTED_TOKEN>\"}"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dbm` | string | `"00:00:00:00:00:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dci` | number | `4000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dco` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `deb` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `demo` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dfam` | string | `"wattpilot"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `di1` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `die` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dii` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `din` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dll` | string | `"https://example.invalid/wattpilot/export?e=<REDACTED_TOKEN>"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dns` | object | `{"dns0":"192.0.2.1","resolv":["# Generated by pynwm","# pynwm-wlan0","# pynwm-ap0","# pynwm-eth0","nameserver 192.0.2.1","# pynwm-enu1"]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `dwo` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ebe` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ebo` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ebt` | number | `10` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ebv` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ee` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `eis` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `emx` | number | `30000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ens` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `err` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esd0` | string | `"192.0.2.1"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esd1` | string | `"0.0.0.0"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esd2` | string | `"0.0.0.0"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esg` | string | `"192.0.2.1"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esi` | string | `"192.0.2.33"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `esk` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ess` | string | `"255.255.255.0"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `eto` | number | `123456` | Current 1.x implementation interprets this as total energy and divides by 1000. | Wh raw / kWh displayed (implementation interpretation) | read by current 1.x implementation | inferred from current implementation; value `123456` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `eto_mid` | number | `123456` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `etop` | number | `123456` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `eusd` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `euse` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `evt` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `exp` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `facacs` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `faccak` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `facice` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `facpass` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `facwak` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fam` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fap` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_age` | number | `12345678` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_akkuMode` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_akkuSOC` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_ohmpilotState` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_ohmpilotTemperature` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_pAcTotal` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_pAkku` | number | `-1525` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_pGrid` | number | `125` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fbuf_pPv` | number | `1650` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fcc` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fck` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fdt` | number | `70000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ferm` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ffna` | string | `"Wattpilot_10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fhi` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fhz` | number | `49.97999954` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fhzo` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fi23` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fio23` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fit` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fldb` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fml` | string | `"grid"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fmmp` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fmt` | number | `300000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fna` | string | `"Wattpilot"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fntp` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `forsch` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fot` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `frc` | number | `0` | Current 1.x implementation interprets this as forced charging state. | unknown | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; only value `0` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `frci` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fre` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `frm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `frt` | number | `5000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fsp` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fsptws` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fst` | number | `1400` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fte` | number | `22000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ftlf` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ftls` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ftt` | number | `42600` | Current 1.x implementation interprets this as next-trip time from midnight. | s from midnight (implementation interpretation) | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; value `42600` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ful` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fup` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fuzz` | array | `[]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fwan` | string | `"Wattpilot_10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fwc` | string | `"0.0.17-8"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fwv` | string | `"43.4"` | Firmware identity value in the observed payload. | unknown | observation only; no writability evidence | empirical value; maintainer records firmware 43.4 | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `fzf` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `gme` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `gmk` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `gmtr` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `grp` | string | `"Wattpilot Flex Home 22 C6"` | Model/group identity value in the observed payload. | unknown | observation only; no writability evidence | empirical value; maintainer records Wattpilot Flex Home 22 C6 | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `gsa` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `host` | string | `"Wattpilot-10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `hsa` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `hsta` | string | `"Wattpilot-10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `hste` | string | `"Wattpilot-10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `hsts` | string | `"Wattpilot-10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `hws` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ice` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ido` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `imd` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `imi` | string | `"0"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `immr` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `imp` | string | `"_tcp"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ims` | string | `"_Fronius-SE-Inverter"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `imse` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ipw` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `iri` | number | `5000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `irs` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `isgo` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `isip` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `isml` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `iuse` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `la1` | number | `16` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `la3` | number | `16` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `las` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lbr` | number | `152` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lbs` | number | `2854` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lccfc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lccfi` | number | `62055385` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lcctc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lch` | number | `62055385` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ldb` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `led` | object | `{"id":17,"name":"Pulsate","norwayOverlay":true,"modeOverlay":true,"subtype":"renderCmds","ranges":[{"from":0,"to":63,"fade":"2048ms","colors0":["#0000FF"],"colors1":["#000000"]}]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ledo` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lfspt` | number | `62056514` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `llr` | number | `481` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lmo` | number | `4` | Current 1.x implementation interprets this as charging mode. | unknown | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; only value `4` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lmsc` | number | `62056514` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `loa` | number | `30` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `loc` | string | `"2026-01-01T12:59:58.000 +01:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `loe` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lof` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `log` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `loi` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lom` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lop` | number | `50` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lopr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `los` | string | `"{\"chg\":[[\"10000001\",true,30,50,0,[1,2,3],false,32]]}"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lot` | object | `{"amp":32,"dyn":32,"sta":32,"ts":0}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `loty` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lpc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lps` | number | `6` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lpsc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lrc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lri` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lrr` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lse` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lssfc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lsstc` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lto` | number | `7200000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `lwf` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `maca` | string | `"00:00:00:00:00:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mace` | string | `"02:00:00:00:00:5b"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `macp` | string | `"02:00:00:00:00:e8"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `macs` | string | `"00:00:00:00:00:00"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `map` | array | `[1,2,3]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mca` | number | `6` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mci` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mcpd` | number | `120000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mcpea` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `men` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mnt` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `modelStatus` | number | `23` | unknown | unknown | observation only; no writability evidence | empirical numeric value 23; enum meaning unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mptwt` | number | `600000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mpwst` | number | `120000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mro` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `msb` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `msca` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mscs` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `msi` | number | `27` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `msr` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mstr` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mstw` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `mwo` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `nif` | string | `"defroute N/A on this device"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `nld` | number | `64` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `nmo` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `npd` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `nrg` | array | `[230,230.1,229.9,0,0,0,0,0,0,0,0,0,0,0,0,0]` | Current 1.x implementation interprets selected array positions as voltage, current and power. | mixed; see array section | read by current 1.x implementation | array shape observed; index semantics inferred from current implementation | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `obm` | string | `"02:00:00:00:00:58"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `oca` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocl` | number | `100` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocm` | string | `"No events yet"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocp` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppa` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppaa` | number | `62057813` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppai` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppao` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppc` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppca` | number | `62056645` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppcc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppck` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppcm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppcn` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppcs` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppd` | string | `"no-card"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppdp` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppe` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppf` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfai` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfao` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfcm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfcn` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfd` | string | `"no-card"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfe` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppff` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfft` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfh` | number | `3600` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfla` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppflo` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfss` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppft` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppfu` | string | `"wss://ocpp.space.fronius.com/commissioning"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppg` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpph` | number | `14400` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppi` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppio` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppla` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpple` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpplea` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpplo` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppmp` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpprl` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpprv` | number | `-666` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpps` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppsc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppss` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppt` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppte` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpptf` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppti` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpptp` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocpptt` | string | `"no-tariff-text"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocppu` | string | `"ws://192.0.2.36:18180/steve/websocket/CentralSystemService/10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocs` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocu` | array | `["43.4"]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocuca` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ocugc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `oem` | string | `"fronius"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `onv` | string | `"43.4"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `opad` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `orsch` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `otaif` | string | `"-"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `otap` | object | `{"type":0,"subtype":0,"address":0,"size":0,"label":"kernel.1:booted","encrypted":false}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pass` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdi` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdle` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdlo` | number | `72000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdls` | number | `25200` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdt` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pdte` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pen` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pgr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pha` | array | `[false,false,false,true,true,true]` | unknown phase-status flags | unknown | observation only; no writability evidence | array values observed; index and enum semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pnp` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `po` | number | `-300` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `proto` | number | `4` | Protocol identity value in the observed payload. | unknown | observation only; no writability evidence | empirical value; maintainer records protocol 4 | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `psh` | number | `500` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `psm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `psmd` | number | `10000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_averagePAkku` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_averagePGrid` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_averagePOhmpilot` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_averagePPv` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_deltaA` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_deltaP` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pvopt_specialCase` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `pwm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `qsw` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rbc` | number | `104` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rbt` | number | `62068619` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rcd` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdbf` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdbfe` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdbs` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdbse` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rde` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdef` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdefe` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdes` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdese` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdpl` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdple` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdre` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rdree` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rfe` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rfide` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rial` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rill` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `riml` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `risl` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `riul` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rmaf` | number | `50.09999847` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rmav` | number | `250.6999969` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rmdns` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rmif` | number | `49.90000153` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rmiv` | number | `207` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rsa` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rsre` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rsrr` | number | `0.159999996` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `rssi` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sau` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sbc` | number | `2` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sbs` | number | `6` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `scaa` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `scan` | array | `[{"ssid":"-","encryptionType":0,"rssi":0,"channel":0,"bssid":"00:00:00:00:00:00","f":[0,0,false,false,false,false,false,false,false,""]}]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `scas` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sch_satur` | object | `{"control":0,"ranges":[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sch_sund` | object | `{"control":0,"ranges":[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sch_week` | object | `{"control":0,"ranges":[{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}},{"begin":{"hour":0,"minute":0,"second":0},"end":{"hour":0,"minute":0,"second":0}}]}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `scrp` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sh` | number | `200` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `shrm` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `shut` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sic` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sica` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sid` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sie` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sil` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sila` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `simo` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sis` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smd` | object | `{"ts":12345678,"I1":-1.85,"I2":1.94,"I3":1.69}` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smic` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smif` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smjh` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smmp` | string | `"_tcp"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smmr` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smms` | string | `"_Fronius-SE-SmartMeter"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smr` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `smrm` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sock` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `spl3` | number | `5200` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sqrm` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sse` | string | `"10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `stao` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `styp` | string | `"wattpilot_flex_c6"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `su` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sua` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `sumd` | number | `10000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `swc` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tab` | number | `1767268798000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tcl` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tds` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ten` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tma` | array | `[null,null,39,41,40,38.5]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tof` | number | `60` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tou` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tpa` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tpck` | array | `["chargectrl_v4","led","wifi","webserver","mdns","time","cloud","rfid","status","froniusinverter","froniussmartmeterip","fronius_hmi","tamper","delta_http","delta_cloud","ota_autoupdate","ota_cloud","cmdhandler","loadbalancing","modbus_slave","ocpp","remotehttp","remotemdns","offlinestorage","systemdwatchdog","cloud_send"]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tpcm` | array | `[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `trx` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tsi` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `typ` | string | `"wattpilot_flex"` | Device-type identity value in the observed payload. | unknown | observation only; no writability evidence | empirical value; maintainer records wattpilot_flex | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `tzt` | string | `""` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ufa` | number | `49.79999924` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ufe` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ufm` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ufs` | number | `49` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ula` | number | `20` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ule` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ulu` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `utc` | string | `"2026-01-01T11:59:58.000"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `uve` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `uvs` | number | `3000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `uvt` | number | `184` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `var` | number | `22` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `waap` | number | `3` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wae` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wak` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wan` | string | `"Wattpilot_10000001"` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wapc` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wb` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wbw` | number | `1` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wcch` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wccw` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wda` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wen` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wg` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wh` | number | `0` | Current 1.x implementation interprets this as energy since plug-in. | Wh (implementation interpretation) | read by current 1.x implementation | inferred from current implementation; value `0` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wh_mid` | number | `1234` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `whb` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `whg` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `who` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `whs` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wifis` | array | `[{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"},{"ssid":"","key":false,"useStaticIp":false,"staticIp":"0.0.0.0","staticSubnet":"0.0.0.0","staticGateway":"0.0.0.0","useStaticDns":false,"staticDns0":"0.0.0.0","staticDns1":"0.0.0.0","staticDns2":"0.0.0.0"}]` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wo` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wpk` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `ws` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsa` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsc` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsh` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsi` | number | `60000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsk` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsl` | null | `null` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsma` | number | `400` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsmi` | number | `200` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsmr` | number | `-90` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsms` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wspc` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wspr` | boolean | `false` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wssc` | number | `0` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wst` | number | `6` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wsw` | boolean | `true` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `wswd` | number | `2000` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |
| `zfo` | number | `200` | unknown | unknown | observation only; no writability evidence | empirical structure/value only; semantics unknown | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |

## Remaining limitations

All fields marked `unknown`, and every unit, enum, or write claim described as inferred/current implementation, remain unverified. In particular, this capture cannot prove set-command acceptance, authentication exchange details, response handling, `partial:true`, delta behavior, array index semantics, or behavior outside one Flex Home 22 C6 on firmware 43.4/protocol 4. Real FHEM, Wattpilot, network, WebSocket, authentication, persistence, rename, reload, delete, reconnect, command-response, and live-reading integration tests were not performed.
