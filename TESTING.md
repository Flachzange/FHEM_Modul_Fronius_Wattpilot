# Testing

Development and release checks require Perl, `Archive::Zip`, `CPAN::Meta`, `JSON`, `Crypt::PBKDF2`, and `Crypt::Bcrypt`, plus the standard `prove`, `sha256sum`, `zip`/`unzip`, and POSIX shell tools. On Debian or Ubuntu, install `libarchive-zip-perl` in addition to the module dependencies.

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with controlled FHEM/DevIo stubs, validates callback registration and global subroutine structure, and models the complete FHEM `CommandRename` mutation sequence including the discarded `RenameFn` reply. It verifies credential ownership and lifecycle behavior, connection cleanup, redacted logging, command semantics and response tracking, embedded META data, both command-reference languages, JSON fixtures, and the required repository structure.

`t/legacy_protocol2.t` and `t/fixtures/legacy-protocol2-session.json` protect the established predecessor-device behavior: the historical PBKDF2 selection when the challenge has no algorithm field, split status initialization, unchanged readings for omitted partial fields, the twelve-value electrical array, continued processing of the sixteen-value Flex array, secured command wrapping, and response correlation. The fixture is synthetic and is not device evidence.

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

These automated tests use revision-aligned stubs and synthetic fixtures. They do not exercise real FHEM, predecessor Wattpilot hardware, Wattpilot Flex hardware, network, WebSocket, charging, command-response, or live-reading integration.
