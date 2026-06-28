# Wattpilot Flex firmware update observations

Checked on 2026-06-28. This document records sanitized empirical observations of the Solar.wattpilot app, the vendor services involved in firmware updates, and one Wattpilot Flex Home 22 C6 while switching between firmware 43.4 and 43.3-rc2.

The observations are **not an official Fronius API specification**. They establish only the message names, field shapes, endpoints, application mappings, and sequences seen in the described device and software versions. They do not establish a stable public contract, accepted version ranges, cross-model behavior, image-verification details, or suitability for implementation in this FHEM module.

Related diagnostic record: Issue #98.

## Evidence and privacy boundary

The retained evidence consists of sanitized network observations, certificate-chain inspection, HTTP response metadata, device status messages, and a static analysis of a maintainer-provided Android application package.

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

The Wattpilot received approximately 82.3 MiB. The phone transferred only a small amount of metadata and control traffic. This confirms that the device, not the app, downloaded the firmware image.

The full HTTPS request path was not visible because the device-to-server connection remained TLS encrypted. The app traffic and static app code contained only the target version, not the final download URL.

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

## Controlled update reboot versus spontaneous reboot

The controlled firmware update visibly prepared for reboot:

- existing external connections were closed;
- multicast memberships were left;
- the device disappeared from the network;
- it later returned and announced firmware 43.4.

This differs from the spontaneous-restart behavior tracked in Issue #98. During those failures, inbound WebSocket data stopped immediately but the old client socket remained apparently open and was only reported as `remoteSocketClosed` much later. The firmware-update observation must therefore not be used to claim that every Wattpilot reboot closes existing WebSocket connections cleanly.

## What the combined evidence confirms

For the observed Wattpilot Flex Home 22 C6, firmware transition, and analyzed app version, the combined evidence confirms:

- release notes are obtained from `data.v3.go-e.io/firmware_changelog`;
- the observed product/application discriminator is `wattpilot_flex-secure-release`;
- selecting a concrete firmware version uses `otaCloud` with the version string;
- the app also contains a default update trigger that maps to `oct=1`;
- rollback uses `switchAppPartition` followed by a reboot request;
- the Wattpilot downloads the image directly from `update.wattpilot.io` over HTTPS;
- the update server uses a private go-e/Wattpilot certificate hierarchy;
- the Wattpilot rejects an untrusted certificate authority;
- the update host fronts the private `goe-firmware-bin` object bucket;
- anonymous requests cannot distinguish existing from nonexistent object paths;
- the analyzed app contains neither the visible final download host nor the bucket name or S3-signature vocabulary;
- `ocs`, `ocp`, `ocl`, `ocm`, and `oca` participate in the observed or app-defined OTA state;
- installation completion and activation after reboot are distinct stages.

## What remains unknown

The evidence does not establish:

- the full firmware object path or HTTP request headers;
- the exact authorization mechanism used for the firmware object;
- whether the image is encrypted or signed and where verification occurs;
- which private CA certificate or public key is stored on the device;
- whether additional certificate or public-key pinning is used;
- accepted versions, downgrade restrictions, anti-rollback behavior, or retry rules;
- complete device-side semantics, units, and guarantees for all OTA fields;
- whether the commands are supported on other Wattpilot models or firmware families;
- whether update commands may safely be exposed through this FHEM module;
- whether the vendor endpoints, query parameters, and storage architecture are stable or intended for third-party use.

No firmware-update command or OTA reading should be added to the module solely on the basis of these observations. Any such change requires a separate issue, an explicit safety analysis, sanitized reproducible testing, and an update to `PROTOCOL-SOURCES.md`.
