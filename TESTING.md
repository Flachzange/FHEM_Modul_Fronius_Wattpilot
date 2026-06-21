# Testing

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with minimal stubs, validates callback registration and global subroutine structure, parses and validates embedded META data, inspects both command-reference languages and anchors, validates synthetic JSON fixtures, and checks the required repository structure.

Build and verify the release artifacts with:

```sh
scripts/build-release.sh
```

The build runs the full CI suite and `scripts/verify-release.sh`. It checks the manifest, internal and archive SHA-256 sums, ZIP integrity, version consistency, and byte equality of every packaged module copy. Generated files remain below ignored `dist/`.

These automated tests use stubs. They do not connect to a real FHEM installation or Wattpilot and do not exercise a real WebSocket connection, authentication exchange, device command, or live reading update.
