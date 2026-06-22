# Testing

Development and release checks require Perl, `Archive::Zip`, `CPAN::Meta`, `JSON`, `Crypt::PBKDF2`, and `Crypt::Bcrypt`, plus the standard `prove`, `sha256sum`, `zip`/`unzip`, and POSIX shell tools. On Debian or Ubuntu, install `libarchive-zip-perl` in addition to the module dependencies.

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with controlled FHEM/DevIo stubs, validates callback registration and global subroutine structure, and models the complete FHEM `CommandRename` mutation sequence including the discarded `RenameFn` reply. It verifies pending-first FUUID ownership, recovery after owner-marker write failure, fail-closed behavior after pending-metadata failure, old-name reuse by a second FUUID in both restart orders, foreign and unowned-resource preservation, password-only Define startup despite foreign current-name or pending password hashes, fresh FUUID-hash storage during authentication, tri-state credential reads at every relevant caller, transactional password changes and deletion, the real `UndefFn`→`DeleteFn` failure sequence and runtime restoration from stable or already-owned current-name credentials, and Undef/Delete/Rename/Disable cleanup. It also reproduces DevIo level-5 payload logging and the transitive HttpUtils URL, DNS/IP, synchronous/asynchronous error, timeout, callback, initial-connect, and reconnect effects, exercises redacted Wattpilot-owned and explicitly enabled raw JSON logging, parses and validates embedded META data, inspects both command-reference languages and anchors, validates synthetic JSON fixtures, and checks the required repository structure.

`t/legacy_protocol2.t` and `t/fixtures/legacy-protocol2-session.json` additionally protect the established predecessor-device behavior: the historical PBKDF2 selection when the challenge has no algorithm field, split status initialization, unchanged readings for omitted partial fields, the twelve-value electrical array, continued processing of the sixteen-value Flex array, secured command wrapping, and response correlation. The fixture is synthetic and is not device evidence.

Framework-derived stub behavior is based on FHEM mirror revision `5354e001b55c323f457bd907434e46f284d9582c`, specifically `CommandRename`, `DevIo_OpenDev`, `DevIo_SimpleWrite`, `DevIo_Disconnected`, `HttpUtils_Connect`, `HttpUtils_gethostbyname`, and `HttpUtils_TimeoutErr`. The rename double moves `%defs`, `NAME`, and attributes before calling `RenameFn` and discards its reply, matching the audited command-level caller. The endpoint tests include a negative control demonstrating that DevIo `privacy=1` does not suppress the internal HttpUtils URL and DNS/IP logs.

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
