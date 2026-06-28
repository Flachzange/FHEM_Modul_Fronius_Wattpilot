# Wattpilot Flex firmware update observations

Checked on 2026-06-28. This document records sanitized empirical observations of the Solar.wattpilot app, the vendor services involved in firmware updates, and one Wattpilot Flex Home 22 C6 while switching between firmware 43.4 and 43.3-rc2.

The observations are **not an official Fronius API specification**. They establish only the message names, field shapes, endpoints, application mappings, and sequences seen in the described device and software versions. They do not establish a stable public contract, accepted version ranges, cross-model behavior, image-verification details, or suitability for implementation in this FHEM module.

Related diagnostic record: Issue #98.

## Evidence and privacy boundary

The retained evidence consists of sanitized network observations, certificate-chain inspection, HTTP response metadata, device status messages, a controlled temporary interruption of update-server reachability, and a static analysis of a maintainer-provided Android application package.

Raw traffic captures and the APK are deliberately **not committed**. They may contain authentication challenges, HMAC-protected messages, device identifiers, local network details, tokens, configuration data, or third-party copyrighted application code. Examples below remove request IDs, HMAC values, the real serial number, tokens, addresses, and unrelated status fields.

Only the minimum facts needed for future protocol research are retained here.

## Firmware changelog service

The app requests the vendor service endpoint:

```text
GET https://data.v3.go-e.io/firmware_changelog
```

One observed request used this shape:

```text
sse=<serial>
apd=wattpilot_flex-secure-release
fwv=43.3-rc2
lang=de
format=2
```

Static analysis of Android app version 1.10.24 independently confirms construction of the same endpoint with these values:

| Parameter | App-side source |
| --- | --- |
| `sse` | connected-device serial number |
| `apd` | `connectedDeviceDescription.project_name` |
| `fwv` | `connectedDeviceDescription.version` |
| `lang` | selected application language |
| `format` | requested response format |

The analyzed Android version uses `format=1`; the separately observed app request used `format=2`. This is recorded as a version or platform difference, not as a protocol guarantee.

For the observed transition from 43.3-rc2 to 43.4, the service returned version `43.4` with these German release notes:

- `Wechselrichter Verbindungsverlust behoben`
- `PV-Batterie Entladetimer gefixt, bei Startzeit > Endzeit`

This is a response from a vendor-operated service observed through the app, not a separately published Fronius firmware changelog document.

## Firmware selection and channels

Static application analysis maps these device fields:

| Protocol field | App-side alias |
| --- | --- |
| `onv` | `newFirmwareVersion` |
| `ocu` | `newFirmwareChannels` |
| `ocp` | `otaUpdateProgress` |
| `ocl` | `otaUpdateSize` |
| `oct` | `triggerUpdate` |
| `opad` | `otherFirmwareAppPartition` |
| `ocs` | `overTheAirCloudStatus` |

The application also contains the firmware-channel labels:

- `OUTDATED`
- `RECOMMENDED`
- `BETA`

The exact `ocu` data structure, ordering guarantees, and server-side channel policy remain unconfirmed.

## Explicit cloud OTA request

Starting from firmware 43.3-rc2, the app requested firmware 43.4 with the sanitized inner message:

```json
{
  "type": "otaCloud",
  "firmware": "43.4"
}
```

On the observed bcrypt-authenticated Flex device, the command was transported inside the established `securedMsg` envelope and acknowledged with a correlated response containing `success: true`.

Static application analysis independently confirms that selecting a concrete firmware version constructs `otaCloud` with the selected version string.

The app did **not** upload the firmware image to the device. It supplied the requested version, after which the Wattpilot performed the external download itself.

## Standard or legacy update trigger

The analyzed app contains a second update path for its internal default selection. Instead of `otaCloud`, it writes the app-side field:

```text
triggerUpdate = true
```

The field mapping encodes this as:

```text
oct = 1
```

This confirms a second app-side update trigger. It does not establish which device generations or firmware versions support it, how the target version is selected, or whether it is appropriate for this FHEM module.

## Rollback to the alternate firmware partition

Starting from firmware 43.4, the app initiated rollback with:

```json
{
  "type": "switchAppPartition"
}
```

The device returned an ordinary correlated response with `success: true`.

The app then requested a reboot through the normal secured write path. The sanitized inner message was:

```json
{
  "type": "setValue",
  "key": "rst",
  "value": 1
}
```

This was also acknowledged with `success: true`. After reboot, the device reported firmware 43.3-rc2.

Static application analysis independently confirms the same user-interface flow: `switchAppPartition`, successful response, reboot confirmation, and a write that maps to `rst=1`.

The observed sequence therefore was:

1. `switchAppPartition`
2. successful response
3. `setValue` for `rst=1`
4. successful response
5. reboot into the alternate partition

This does not establish whether `switchAppPartition` accepts parameters, how partitions are validated, whether the command is supported by legacy devices, or whether direct use outside the app is safe.

## Direct download by the Wattpilot

Immediately after the explicit OTA request, the Wattpilot resolved and connected to:

```text
update.wattpilot.io:443
```

The TLS ClientHello used SNI `update.wattpilot.io` and advertised HTTP/1.1. At the time of observation, DNS resolution included `lb2-fsn.go-e.io` and an address in the provider network. Those intermediate names and addresses are operational details and must not be pinned because they can change.

The phone transferred only a small amount of metadata and control traffic. The Wattpilot itself received the firmware transfer, confirming that the app does not relay the image.

The full HTTPS request path was not visible because the device-to-server connection remained TLS encrypted. The app traffic and static app code contained only the target version, not the final download URL.

### Immediate pre-download sequence

A full packet capture starting about 15 seconds before the successful download showed this sequence:

1. one short cloud-to-device application record consistent in size with the known `otaCloud` command;
2. one short device-to-cloud record consistent in size with the correlated success response;
3. A and AAAA lookups for `update.wattpilot.io` about 31 milliseconds later;
4. a TCP connection to the resolved update-server address;
5. a TLS ClientHello with SNI `update.wattpilot.io`;
6. one encrypted HTTP request after the TLS handshake;
7. the firmware response immediately afterwards.

The observed TLS 1.3 application-record sizes are exactly consistent with the known JSON messages when using a 36-character request UUID, ordinary WebSocket framing, the TLS 1.3 authentication tag, and no record padding:

```json
{"requestId":"<36-character UUID>","type":"otaCloud","firmware":"43.4"}
```

```json
{"type":"response","requestId":"<36-character UUID>","success":true}
```

This is strong size-correlation evidence rather than decrypted payload proof. It supports the conclusion that the cloud message carries the requested version and request ID, not an additional download URL or long access token.

Within the captured pre-download window, the Wattpilot contacted no separate DNS name or new HTTPS endpoint for a manifest, token, checksum, or object identifier. A value obtained and cached before the capture began cannot be excluded.

### Single encrypted HTTP request

After the TLS handshake, the Wattpilot sent exactly one TLS application record containing the HTTP request. Its encrypted record payload was 155 bytes. Under the observed TLS 1.3 framing, and assuming no optional record padding, this permits about 138 bytes of HTTP plaintext.

The server then began its response immediately. No second request, redirect round trip, or authentication challenge was observed on that connection. This rules out a separate manifest request on the same connection and makes conventional long AWS Signature Version 4 presigned URLs or `Authorization` headers unlikely. It does not exclude a compact proprietary header, a short capability path or query value, mutual TLS, or authorization state already available to the device.

Two successful captures showed the same basic request shape. The server delivered roughly 86.8 MB of unique TCP payload per download, including TLS and HTTP overhead; the firmware body is therefore slightly smaller. The bulk transfer completed in approximately 13 to 15 seconds in the observed network conditions.

## Private certificate hierarchy

The server presented this certificate hierarchy:

```text
update.wattpilot.io
└─ Wattpilot production CA
   └─ go-e IOT ROOT CA
```

Observed certificate roles and validity:

| Certificate | Role | Observed validity |
| --- | --- | --- |
| `update.wattpilot.io` | server certificate | 2025-11-11 through 2026-11-11 |
| `Wattpilot production CA` | intermediate CA | 2021-04-15 through 2091-03-29 |
| `go-e IOT ROOT CA` | self-signed private root CA | 2020-11-29 through 2090-11-12 |

A connection using a certificate chain rooted in an untrusted CA was rejected by the Wattpilot with TLS alert `unknown ca`. This confirms active certificate-chain validation. It does **not** by itself prove additional leaf-certificate or public-key pinning.

Because the short-lived server certificate is issued by long-lived private CAs, the evidence is consistent with a device trust store containing the private root or intermediate CA. The exact trust anchor and any additional pinning remain unknown.

## Firmware object storage

Anonymous requests to `update.wattpilot.io` returned an S3-compatible XML error with:

```text
Code: AccessDenied
BucketName: goe-firmware-bin
```

Response metadata included:

```text
x-debug-bucket: goe-firmware-bin
x-amz-request-id: <redacted>
```

The host therefore fronts an S3-compatible object store, with response identifiers consistent with a Ceph deployment. The exact storage implementation is operational evidence only and may change.

Both plausible and deliberately nonexistent anonymous object paths returned equivalent `403 AccessDenied` responses. Therefore:

- anonymous path tests cannot establish whether an object exists;
- `accept-ranges: bytes` does not prove that a tested object exists;
- the real device request requires HTTP-level authorization or an equivalent access mechanism.

Possible mechanisms include a time-limited signed URL, an authorization header, a vendor-specific token, or another backend-mediated method. The observations do not distinguish between them.

## Static Android application analysis

The analyzed file had these properties:

| Property | Value |
| --- | --- |
| Package | `co.goe.iot.app.fronius` |
| Version | `1.10.24` |
| Version code | `551` |
| SHA-256 | `09a742295ecadc49fa73f26de1e7741ac10637e26279c0b220cf95947f7086a4` |
| Framework | React Native |
| JavaScript runtime | Hermes bytecode, version 96 |

The APK itself is not committed. The static analysis retained only minimal protocol findings.

The following strings and mechanisms were confirmed:

- `otaCloud`
- `switchAppPartition`
- `firmware_changelog`
- the app-side OTA field aliases listed above
- the `ocs` display mapping listed below
- `oct=1` as the encoded default update trigger

The following terms were not found in the unpacked APK:

```text
update.wattpilot.io
goe-firmware-bin
X-Amz-
AWS4-HMAC-SHA256
presign
wattpilot_flex-secure-release
```

Negative string-search results do not prove absolute absence of every dynamically generated or obfuscated equivalent. Together with the observed behavior, however, they support the narrower conclusion that this app version does not contain the visible direct firmware host, bucket name, S3 signature vocabulary, or final object path. Firmware resolution and download authorization therefore occur outside the visible app update command path, most likely on the device or through device-side backend communication.

## OTA status fields

Device status messages contained these fields:

| Field | Observed or app-defined role | Evidence limit |
| --- | --- | --- |
| `ocs` | OTA state | Complete app-side display mapping exists; this remains application implementation evidence, not an official protocol enum. |
| `ocp` | OTA progress candidate | Progress-like numeric values were observed, ending at 100. Units and monotonic guarantees are not established. |
| `ocl` | OTA size or progress denominator candidate | Used by the app as the denominator for percentage calculation. Meaning and units across device generations remain unconfirmed. |
| `ocm` | OTA status text candidate | Contained human-readable progress text. One device message replaced the actual URL with `<SANITIZED-URL>`. |
| `oca` | OTA target/application metadata candidate | Contained fields including `project_name`, `version`, `secure_version`, `idf_ver`, and `sha256`; requiredness and semantics are not established. |

### App-side `ocs` mapping

The analyzed app maps `ocs` as follows:

| Value | App display meaning |
| ---: | --- |
| `0` | `Idle` |
| `1` | `Updating` |
| `2` | `Failed` |
| `3` | `Succeeded` |
| `4` | `NotReady` |

This is a static application mapping. It is stronger than a guess based on one observed update, but it remains neither official Fronius documentation nor proof of cross-version completeness.

### Progress calculation

The app calculates the displayed percentage in the general case as:

```text
min(100, round(100 * ocp / ocl))
```

The analyzed code contains a fallback value of `1416400` for `ocl` in an older or incomplete status path. The meaning and unit of that fallback are not established.

During the observed Flex update, `ocl=100`, so `ocp` behaved effectively as a percentage value in that session.

### Target metadata example

A sanitized target metadata example was:

```json
{
  "oca": {
    "project_name": "wattpilot_flex-secure-release",
    "version": "43.4",
    "secure_version": 0,
    "idf_ver": "43.4",
    "sha256": ""
  }
}
```

Observed progress text indicated that the device used Ethernet with WLAN as an alternate interface and executed the download in a constrained OTA control group. These are diagnostic implementation observations and must not become module behavior assumptions.

The final observed state included:

```json
{
  "ocs": 3,
  "ocp": 100,
  "ocm": "Installed"
}
```

At that point, the image was installed but the device still reported the old running firmware until a subsequent reboot activated 43.4.

## Blocked-download retry and automatic recovery

A controlled test temporarily rejected only TCP connections from the Wattpilot to `update.wattpilot.io:443`. DNS, the existing cloud WebSocket, local access, and other network traffic remained available.

The device accepted the original `otaCloud` request and entered the normal updating state. The first relevant status included:

```json
{
  "ocs": 1,
  "ocm": "Downloading... curl: (7) Failed to connect to update.wattpilot.io port 443 ...",
  "oca": {
    "project_name": "wattpilot_flex-secure-release",
    "version": "43.4",
    "secure_version": 0,
    "idf_ver": "43.4",
    "sha256": ""
  }
}
```

The diagnostic text also exposed these implementation details:

```text
cURL --interface eth0 (alternate: wlan0)
Cgroup: /uca_ota (max 200 MB)
```

The device repeatedly reported `Will retry...`. After about ten seconds without a successful connection, `ocm` added a stall counter and the text `timeout termination in 9 min...`. During the retained blocked interval, `ocs` stayed at `1` (`Updating`); a connection failure did not immediately transition it to the app-defined failed state `ocs=2`.

### Retry cadence

The packet captures establish the retry behavior for this failure mode:

- 299 rejected TCP connection attempts were observed in the first capture;
- 14 more rejected attempts occurred in the continuation capture before success;
- the median interval between TCP attempts was about 1.003 seconds;
- the median interval between repeated A/AAAA DNS lookups was about 3.096 seconds;
- each rejected TCP attempt received an immediate reset, matching cURL error 7 in `ocm`.

The status text indicates an overall failure window of roughly ten minutes, but the test deliberately restored reachability before that timeout. The final state after a complete timeout was therefore not observed.

### Automatic continuation after reachability returned

No new action was taken in the app when the block was removed. The last rejected TCP attempt occurred about 1.08 seconds before the next retry successfully established a TLS connection. No second cloud-to-device record with the observed `otaCloud` record size appeared before that successful connection.

The already running OTA operation therefore continued automatically. It did not require a second firmware-selection command or a device reboot. The successful retry used the same single encrypted HTTP-request shape documented above and proceeded directly to the firmware transfer.

## Controlled update reboot versus spontaneous reboot

After the successful retry, the firmware-transfer connection closed cleanly. The Wattpilot remained online during the installation phase and continued exchanging status traffic before deliberately preparing for restart.

The controlled update reboot showed this sequence:

- the active cloud connection was closed by the Wattpilot;
- multicast memberships were left;
- the remaining previous cloud connection was reset;
- the device stopped responding on the network;
- approximately 84.6 seconds after the prepared shutdown began, the device rejoined multicast groups and emitted new discovery traffic;
- it resolved `iot.wattpilot.com` and established a new cloud connection;
- it subsequently announced firmware 43.4.

The download connection began about 49.5 seconds before the prepared shutdown. The bulk transfer itself completed roughly 36 seconds before that shutdown, confirming that download, installation, and activation/reboot are separate phases.

This differs from the spontaneous-restart behavior tracked in Issue #98. During those failures, inbound WebSocket data stopped immediately but the old client socket remained apparently open and was only reported as `remoteSocketClosed` much later. The firmware-update observation must therefore not be used to claim that every Wattpilot reboot closes existing WebSocket connections cleanly.

## What the combined evidence confirms

For the observed Wattpilot Flex Home 22 C6, firmware transition, and analyzed app version, the combined evidence confirms:

- release notes are obtained from `data.v3.go-e.io/firmware_changelog`;
- the observed product/application discriminator is `wattpilot_flex-secure-release`;
- selecting a concrete firmware version uses `otaCloud` with the version string;
- the cloud command and success response record sizes are consistent with the known JSON only, without a visible additional URL or long token;
- the app also contains a default update trigger that maps to `oct=1`;
- rollback uses `switchAppPartition` followed by a reboot request;
- the Wattpilot downloads the image directly from `update.wattpilot.io` over HTTPS;
- no separate manifest or token endpoint appeared in the captured immediate pre-download sequence;
- the successful download uses one short encrypted HTTP request followed directly by the firmware response;
- the update server uses a private go-e/Wattpilot certificate hierarchy;
- the Wattpilot rejects an untrusted certificate authority;
- the update host fronts the private `goe-firmware-bin` object bucket;
- anonymous requests cannot distinguish existing from nonexistent object paths;
- the analyzed app contains neither the visible final download host nor the bucket name or S3-signature vocabulary;
- `ocs`, `ocp`, `ocl`, `ocm`, and `oca` participate in the observed or app-defined OTA state;
- a blocked TCP connection is retried about once per second, with DNS refreshed about every three seconds;
- `ocs` remains `1` during the observed connection-failure retry period;
- restoring update-server reachability allows the existing OTA operation to continue automatically without a second app action;
- the device reports use of `eth0`, fallback interface `wlan0`, OTA cgroup `/uca_ota`, and a 200 MB cgroup limit;
- download, installation, and activation after a controlled reboot are distinct stages;
- the controlled update reboot closes connections and leaves multicast groups before an observed network absence of about 84.6 seconds.

## What remains unknown

The evidence does not establish:

- the full firmware object path or decrypted HTTP request headers;
- the exact authorization mechanism used for the firmware object;
- whether the image is encrypted or signed and where verification occurs;
- which private CA certificate or public key is stored on the device;
- whether additional certificate or public-key pinning is used;
- accepted versions, downgrade restrictions, anti-rollback behavior, or server-side selection policy;
- the exact terminal status and cleanup behavior after the approximately ten-minute retry window expires completely;
- whether retry cadence, timeout, cgroup path, or interface preference are stable across releases and device models;
- complete device-side semantics, units, and guarantees for all OTA fields;
- whether the commands are supported on other Wattpilot models or firmware families;
- whether update commands may safely be exposed through this FHEM module;
- whether the vendor endpoints, query parameters, and storage architecture are stable or intended for third-party use.

No firmware-update command or OTA reading should be added to the module solely on the basis of these observations. Any such change requires a separate issue, an explicit safety analysis, sanitized reproducible testing, and an update to `PROTOCOL-SOURCES.md`.
