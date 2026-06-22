# Testing

Development and release checks require Perl, `Archive::Zip`, `CPAN::Meta`, `JSON`, `Crypt::PBKDF2`, `Crypt::URandom`, and `Crypt::Bcrypt`, plus the standard `prove`, `sha256sum`, `zip`/`unzip`, and POSIX shell tools. On Debian or Ubuntu, install `libarchive-zip-perl` in addition to the module dependencies. `Crypt::Bcrypt` remains optional at runtime for installations that use only PBKDF2, but its deterministic vector runs whenever it is installed.

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with controlled FHEM/DevIo stubs, validates callback registration and global subroutine structure, and models the complete FHEM `CommandRename` mutation sequence including the discarded `RenameFn` reply. It verifies pending-first FUUID ownership, recovery after owner-marker write failure, fail-closed behavior after pending-metadata failure, old-name reuse by a second FUUID in both restart orders, foreign and unowned-resource preservation, password-only Define startup despite foreign current-name or pending password hashes, fresh FUUID-hash storage during authentication, tri-state credential reads at every relevant caller, transactional password changes and deletion, the real `UndefFn`→`DeleteFn` failure sequence and runtime restoration from stable or already-owned current-name credentials, and Undef/Delete/Rename/Disable cleanup. It also reproduces DevIo level-5 payload logging and the transitive HttpUtils URL, DNS/IP, synchronous/asynchronous error, timeout, callback, initial-connect, and reconnect effects, exercises redacted Wattpilot-owned and explicitly enabled raw JSON logging, parses and validates embedded META data, inspects both command-reference languages and anchors, validates synthetic JSON fixtures, and checks the required repository structure.

`t/legacy_protocol2.t` and `t/fixtures/legacy-protocol2-session.json` additionally protect the established predecessor-device behavior: the historical PBKDF2 selection when the challenge has no algorithm field, split status initialization, unchanged readings for omitted partial fields, the twelve-value electrical array, continued processing of the sixteen-value Flex array, secured command wrapping, and response correlation. The fixture is synthetic and is not device evidence.

`t/protocol_input_hardening.t` adds deterministic synthetic PBKDF2, bcrypt serial-salt, authentication-response, canonical secured-JSON, and HMAC vectors. It rejects scalar/array top levels, missing or invalid message fields, malformed status data, invalid electrical arrays, malformed/oversized decoded input, and mixed valid/malformed batches. It verifies bounded completion of syntactically incomplete JSON across decoded returns, strings containing braces, `}{`, escapes, and newlines, multiple concatenated JSON objects, redacted unknown messages, persistence failures, and transient-auth cleanup across disconnect, partial raw-frame returns, disable, password change, authentication error, undefine, delete, and reconnect. `t/pr29_review_fixes.t` additionally enforces the 256-document batch limit with atomic rejection, distinguishes actual JSON strings from numbers, booleans, nulls, arrays, and objects, requires explicit hash-mode selection before derivation, and verifies that changing or deleting `authHash` closes and invalidates the old session, removes stale timers, leaves exactly one controlled reconnect, and blocks stale secured commands.

State lifetime is explicit: `deviceType`, `protocol`, `authPending`, `authHashMode`, `authenticated`, pending requests, and `jsonBuffer` are current-connection/current-device-hash state only and are cleared at connection-lifecycle boundaries. The password and derived signing key remain FUUID-owned persistent values; no new retry promise or persistent protocol state is stored in `$hash->{helper}`.

Framework-derived DevIo stub behavior is based on FHEM mirror revision `6a920121204142b435c7b05cd9e9e2dd754879f6`, specifically `DevIo_DoSimpleRead`, `DevIo_SimpleRead`, `DevIo_DecodeWS`, `DevIo_OpenDev`, `DevIo_SimpleWrite`, `DevIo_CloseDev`, and `DevIo_Disconnected`, plus their `HttpUtils_Connect` path. `DevIo_DecodeWS` appends raw bytes to `.WSBUF`, returns an empty string until a complete frame exists, removes complete frames from that buffer, and concatenates payloads from further complete frames before returning. It records `FIN` but does not use it to accumulate a logical message across separately returned complete frames. Close removes `.WSBUF`, the WebSocket marker, file descriptors, partial state, and reconnect timing; disconnect closes, marks the device disconnected, registers ReadyFn polling, and triggers `DISCONNECTED`. The Wattpilot double therefore queues already decoded `DevIo_SimpleRead` results and models disconnect side effects. Module tests distinguish DevIo's raw-frame buffer from the bounded logical JSON continuation required when a fragmented message is returned across calls. Existing command-level rename/timer behavior remains pinned separately in the stub; the rename double moves `%defs`, `NAME`, and attributes before calling `RenameFn` and discards its reply. The endpoint tests include a negative control demonstrating that DevIo `privacy=1` does not suppress the internal HttpUtils URL and DNS/IP logs.

Build and verify the release artifacts with:

```sh
scripts/build-release.sh
```

The build runs the full CI suite and `scripts/verify-release.sh`. It checks the manifest, internal and archive SHA-256 sums, ZIP integrity, version consistency, and byte equality of every packaged module copy. Generated files remain below ignored `dist/`.

Verify deterministic output with two builds from the same commit and the same `SOURCE_DATE_EPOCH`:

```sh
scripts/check_reproducible_release.sh
```

The check fails unless both generated ZIP archives have the same SHA-256 digest.

These automated tests use revision-aligned stubs and synthetic fixtures. They do not exercise real FHEM, predecessor Wattpilot hardware, Wattpilot Flex hardware, rename, `rereadcfg`, delete, network, WebSocket, authentication, reconnect, charging, command-response, or live-reading integration.
