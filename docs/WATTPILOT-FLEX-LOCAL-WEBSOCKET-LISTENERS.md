# Wattpilot Flex local WebSocket listener observations

Checked on 2026-06-28 on one Wattpilot Flex Home 22 C6 running firmware 43.4.

This note records sanitized empirical observations of local TCP, SSH, and WebSocket listeners. It is not an official Fronius protocol specification and does not establish cross-model or cross-version behavior.

Related records:

- Issue #98
- Draft PR #99
- `docs/WATTPILOT-FLEX-FIRMWARE-UPDATE.md`

## Evidence and privacy boundary

The retained evidence consists of complete TCP connect scans, service detection, ordinary HTTP requests, standards-compliant WebSocket upgrades, passive WebSocket captures, one SSH authentication-method query with an intentionally nonexistent probe user, and controlled no-op setter checks that wrote back a value already active on the device.

No raw captures are committed. The local full-status stream contains device identifiers, network configuration, backend information, operational state, and other potentially sensitive data. Examples and summaries below remove the real serial number, local addresses, request identifiers, authentication values, SSIDs, BSSIDs, certificate fingerprints, and unrelated status values.

No reboot, OTA, partition, network, force-state, charging-mode, or changed-value command was sent. No SSH key was tested and no SSH login was attempted.

## Ethernet listeners

The complete Ethernet TCP scan found these open listeners:

| Port | Detected service | Observed role |
| ---: | --- | --- |
| `80/tcp` | HTTP, nginx | authenticated local WebSocket endpoint used by the module |
| `9180/tcp` | HTTP, nginx | unencrypted WebSocket endpoint with application-level authentication |
| `9443/tcp` | TLS/HTTP, nginx | TLS WebSocket endpoint that exposes status and accepted a controlled no-op setter check without the observed bcrypt exchange |

Both 9180 and 9443 rejected an ordinary HTTP `GET /` with:

```text
HTTP/1.1 400 Bad Request
The WebSocket handshake Upgrade field is missing
```

Both accepted a standards-compliant WebSocket upgrade and returned `101 Switching Protocols`.

Port 9180 reported `secured:true` and issued the bcrypt `authRequired` challenge. Port 9443 reported `secured:false` and immediately emitted status messages over TLS without the observed Wattpilot-password exchange or client certificate.

A controlled check on Ethernet port 9443 used a supported setter and wrote back exactly the value that had just been read from `fullStatus`. The listener returned a correlated successful response containing the unchanged value. No operating setting was effectively changed.

A connection to the Ethernet address on port 80 returned `authRequired`. This confirms that the Ethernet security profile differs by listener and that port 9443 is not merely a TLS equivalent of the authenticated port-80 API.

## Wattpilot hotspot listeners

A complete TCP connect scan through the Wattpilot's own WLAN hotspot found exactly these open TCP ports:

| Port | Detected service |
| ---: | --- |
| `22/tcp` | Dropbear SSH 2024.85 |
| `80/tcp` | nginx, WebSocket |
| `443/tcp` | nginx, WebSocket over TLS |
| `8443/tcp` | nginx, WebSocket over TLS |
| `9180/tcp` | nginx, WebSocket |
| `9181/tcp` | nginx, WebSocket |
| `9443/tcp` | nginx, WebSocket over TLS |

The TLS listeners on 443, 8443, and 9443 presented the same device-specific certificate issued by the private `Wattpilot production CA`. Identifying certificate data and fingerprints are deliberately omitted.

The scan was TCP-only. It does not establish whether additional UDP services exist.

## Hotspot SSH listener

Port 22 identified itself as Dropbear SSH 2024.85 using SSH protocol 2 on Linux.

The advertised algorithm set included modern options such as Curve25519, Ed25519, ChaCha20-Poly1305, AES-CTR, and SHA-256, together with compatibility options including `ssh-rsa`, `diffie-hellman-group14-sha1`, and `hmac-sha1`.

A single `ssh-auth-methods` query using an intentionally nonexistent probe user reported only:

```text
publickey
```

Password authentication was not offered in that test. No private key, username guess, password, brute-force method, or login was attempted. The observation is consistent with a manufacturer, production, recovery, or service access path, but its intended purpose is not established.

## Hotspot WebSocket matrix

Passive WebSocket handshakes and captures produced this matrix:

| Port | Transport | `secured` | Behavior before client application data | Controlled no-op setter check |
| ---: | --- | :---: | --- | --- |
| 80 | WS | `false` | immediate `fullStatus`, inverter messages, and continuous `deltaStatus` | accepted |
| 443 | WSS | `false` | immediate `fullStatus`, inverter messages, and continuous `deltaStatus` | accepted |
| 8443 | WSS | `true` | bcrypt `authRequired`; no status stream before authentication | not attempted |
| 9180 | WS | `true` | bcrypt `authRequired`; no status stream before authentication | not attempted |
| 9181 | WS | `false` | immediate `fullStatus`, inverter messages, and continuous `deltaStatus` | accepted |
| 9443 | WSS | `false` | immediate `fullStatus`, inverter messages, and continuous `deltaStatus` | accepted |

All six WebSocket listeners reported protocol 2, `proto` 4, and firmware 43.4 in the observed `hello` message.

The four `secured:false` listeners exposed the same set of 558 `fullStatus` fields and the same general application-message sequence. One large `fullStatus` message observed on port 9181 was fragmented over four WebSocket frames, confirming that clients must support fragmented text messages.

The evidence supports these listener groups:

- authenticated API: 9180 over cleartext WebSocket and 8443 over TLS;
- hotspot application API without the additional Wattpilot secured-message layer: 80 and 9181 over cleartext WebSocket, plus 443 and 9443 over TLS.

TLS on 443 and 9443 encrypted the transport but did not add client authentication in the tested hotspot configuration.

## Controlled no-op setter checks

The checks were deliberately designed not to change an operating setting.

A first application-level message targeted a read-only status field. The device parsed the request and returned a semantic `has no setter` error. This established that incoming client application messages were being processed rather than silently ignored.

A second check used a supported setter and wrote back exactly the value that had just been read from `fullStatus`. Hotspot ports 80, 443, 9181, and 9443 each returned a correlated successful response containing the unchanged value.

The same no-op setter check was then performed against Ethernet port 9443. It also returned a correlated successful response containing the unchanged value.

The request used a numeric request identifier. The correlated response represented the identifier as a string.

These observations establish that the four hotspot listeners reporting `secured:false`, and Ethernet port 9443, are not passive read-only streams. They accept setter messages without the additional Wattpilot application-level secured-message exchange used on the authenticated listeners.

Hotspot access required association with and reachability through the Wattpilot hotspot. Ethernet port 9443, however, was reachable from the ordinary local network used for the device. The observations alone do not establish vendor intent or exposure beyond networks that can route to the listener.

## OTA and partition fields visible on 9443

The idle Ethernet `fullStatus` on port 9443 contained these OTA-related values:

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

It also contained this object:

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

The exposed status stream includes more than electrical measurements. It contains network, backend, device, and operational configuration.

For the observed device and firmware, clients associated with the hotspot could read this data and perform the controlled no-op setter checks on ports 80, 443, 9181, and 9443 without the additional Wattpilot secured-message exchange. A client with ordinary local-network reachability could also perform the controlled no-op setter check on Ethernet port 9443.

The Ethernet result is more security-relevant than the hotspot-only result because the access boundary is the surrounding local network rather than association with the device hotspot. This may still be an intentional trusted-LAN integration design. The observations alone do not establish a vulnerability classification or vendor intent.

Raw captures and full status payloads must therefore be treated as sensitive and must not be committed or posted publicly without sanitization.

## What remains unknown

The investigation does not establish:

- whether the hotspot and Ethernet 9443 behavior is intentional and documented internally;
- whether every supported setter is available through all `secured:false` listeners;
- whether any command classes have additional authorization checks;
- whether the behavior is implemented by nginx routing, separate backend listeners, or another network-policy layer;
- the intended purpose of the hotspot-local SSH service;
- the certificate identity and validation expectations intended for ordinary TLS clients;
- the exact meaning of `otaif` and every member of `otap`;
- whether the ports, message sequence, `secured` values, and setter behavior are stable across firmware versions or device models;
- whether any listener is intended or suitable as an alternative transport for this FHEM module.

No alternative module transport should be implemented solely from these observations. Any such change requires a separate issue, safety and privacy analysis, reproducible sanitized tests, and explicit protocol-source documentation.
