# Testing

Development and release checks require Perl, `Archive::Zip`, `CPAN::Meta`, `JSON`, `Crypt::PBKDF2`, and `Crypt::Bcrypt`, plus the standard `prove`, `sha256sum`, `zip`/`unzip`, and POSIX shell tools. On Debian or Ubuntu, install `libarchive-zip-perl` in addition to the module dependencies.

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with controlled FHEM/DevIo stubs, validates callback registration and global subroutine structure, verifies retryable rename migration, transactional password changes and deletion, and Undef/Delete/Rename/Disable cleanup, reproduces DevIo level-5 payload logging and the transitive HttpUtils URL, DNS/IP, synchronous/asynchronous error, timeout, callback, initial-connect, and reconnect effects, exercises redacted and explicitly enabled raw JSON logging, parses and validates embedded META data, inspects both command-reference languages and anchors, validates synthetic JSON fixtures, and checks the required repository structure.

Framework-derived stub behavior is based on FHEM mirror revision `5354e001b55c323f457bd907434e46f284d9582c`, specifically `DevIo_OpenDev`, `DevIo_SimpleWrite`, `DevIo_Disconnected`, `HttpUtils_Connect`, `HttpUtils_gethostbyname`, and `HttpUtils_TimeoutErr`. The endpoint tests include a negative control demonstrating that DevIo `privacy=1` does not suppress the internal HttpUtils URL and DNS/IP logs.

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

These automated tests use stubs. They do not exercise real FHEM, Wattpilot, rename, `rereadcfg`, network, WebSocket, authentication, reconnect, command-response, or live-reading integration.
