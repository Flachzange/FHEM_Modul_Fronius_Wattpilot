# Wattpilot Flex local WebSocket listener observations

Checked on 2026-06-28 on one Wattpilot Flex Home 22 C6 running firmware 43.4.

This note records sanitized empirical observations of local TCP and WebSocket listeners. It is not an official Fronius protocol specification and does not establish cross-model or cross-version behavior.

Related records:

- Issue #98
- Draft PR #99
- `docs/WATTPILOT-FLEX-FIRMWARE-UPDATE.md`

## Evidence and privacy boundary

The retained evidence consists of a complete TCP connect scan of the Ethernet address, service detection, ordinary HTTP requests, standards-compliant WebSocket upgrades, and passive WebSocket captures. No state-changing WebSocket message was sent during this investigation.

Raw captures are deliberately not committed. The local full-status stream contains device identifiers, network configuration, backend information, operational state, and other potentially sensitive data. Examples below remove the real serial number, local addresses, authentication tokens, and unrelated status values.

## Ethernet listeners

The complete TCP scan found these open listeners:

| Port | Detected service | Observed role |
| ---: | --- | --- |
| `80/tcp` | HTTP, nginx | existing local WebSocket endpoint used by the module |
| `9180/tcp` | HTTP, nginx | unencrypted WebSocket endpoint with application-level authentication |
| `9443/tcp` | TLS/HTTP, nginx | TLS WebSocket endpoint that immediately exposes status without the observed bcrypt exchange |

The service names above are empirical observations, not a compatibility guarantee. No conclusion is made about UDP services, other Wattpilot models, or future firmware versions.

Both 9180 and 9443 rejected an ordinary HTTP `GET /` with:

```text
HTTP/1.1 400 Bad Request
The WebSocket handshake Upgrade field is missing
```

Both accepted a standards-compliant WebSocket upgrade and returned:

```text
HTTP/1.1 101 Switching Protocols
Server: nginx
Connection: upgrade
Upgrade: websocket
```

## Port 9180

Port 9180 returned a text WebSocket `hello` message with this sanitized shape:

```json
{
  "type": "hello",
  "devicefamily": "wattpilot",
  "devicetype": "wattpilot_flex",
  "devicesubtype": "wattpilot_flex_c6",
  "version": "43.4",
  "protocol": 2,
  "proto": 4,
  "secured": true
}
```

The next message was:

```json
{
  "type": "authRequired",
  "token1": "<redacted>",
  "token2": "<redacted>",
  "hash": "bcrypt"
}
```

The passive capture contained exactly these two logical messages. Because the client sent no authentication response, no `fullStatus` or `deltaStatus` followed.

This matches the existing Flex application-level authentication model: `secured:true`, bcrypt challenge, and subsequent protected messages after successful authentication.

## Port 9443

Port 9443 used TLS and returned a text WebSocket `hello` message with the same basic device identity, but with:

```json
{
  "type": "hello",
  "protocol": 2,
  "proto": 4,
  "secured": false
}
```

The test client supplied:

- no Wattpilot password;
- no `auth` response;
- no `securedMsg`;
- no client certificate;
- no application message after the WebSocket handshake.

Nevertheless, the device immediately emitted this logical message sequence:

1. one `hello`;
2. one `fullStatus`;
3. one `clearInverters`;
4. two `updateInverter` messages;
5. one `clearSmips`;
6. fifteen `deltaStatus` messages during the retained interval.

No `authRequired` message was observed on 9443.

The `fullStatus` JSON payload was 13,755 bytes and contained 558 top-level status fields. It was fragmented over four WebSocket frames. The remaining application messages were ordinary text WebSocket messages.

The transport itself was TLS encrypted. Therefore, `secured:false` appears to describe the absence of the additional Wattpilot application-level secured-message layer rather than absence of transport encryption.

The observation establishes unauthenticated **read access at the Wattpilot application layer** for this local TLS listener. It does not establish anonymous write access. No `setValue`, `otaCloud`, `switchAppPartition`, reboot, or other state-changing message was tested on port 9443.

## OTA and partition fields visible on 9443

The idle `fullStatus` contained these OTA-related values:

```json
{
  "onv": "43.4",
  "ocu": ["43.4"],
  "ocs": 0,
  "ocp": 0,
  "ocl": 100,
  "ocm": "No events yet",
  "oca": null,
  "opad": null,
  "otaif": "-"
}
```

It also contained this previously unrecorded object:

```json
{
  "otap": {
    "type": 0,
    "subtype": 0,
    "address": 0,
    "size": 0,
    "label": "kernel.1:booted",
    "encrypted": false
  }
}
```

The field name and label are consistent with OTA or boot-partition metadata, but exact semantics are unknown.

In particular, `otap.encrypted=false` must not be interpreted as proof that the downloadable firmware image is unencrypted. It may describe only the current partition entry, its storage format, or another internal property.

The fields `otaif` and `otap` are candidates for passive observation during a future update because they may expose interface, target-partition, address, or size changes. Their stability and meaning are not established.

## Security and privacy implications

The 9443 status stream includes more than simple electrical measurements. The captured `fullStatus` contained network, backend, device, and operational configuration.

For the observed device and firmware, a client with local network reachability to port 9443 could obtain this data without the Wattpilot password and without the observed bcrypt exchange. This may be an intentional trusted-LAN integration interface; the observation alone does not establish a vulnerability or vendor intent.

Raw 9443 captures should therefore be treated as sensitive and must not be committed or posted publicly without sanitization.

## What remains unknown

The investigation does not establish:

- whether port 9443 intentionally supports read-only access or also accepts writes;
- whether any write requires a different authentication mechanism;
- whether ports 9180 and 9443 are reachable through the Wattpilot hotspot;
- whether hotspot clients receive the same status stream;
- the certificate identity and validation expectations intended for ordinary 9443 clients;
- the exact meaning of `otaif` and every member of `otap`;
- whether the ports, message sequence, and `secured` values are stable across firmware versions or device models;
- whether 9443 is intended or suitable as an alternative transport for this FHEM module.

No alternative module transport or unauthenticated write path should be implemented solely from these observations. Any such change requires a separate issue, a safety and privacy analysis, reproducible sanitized tests, and explicit protocol-source documentation.
