# Architecture

`72_Wattpilot.pm` is the authoritative FHEM module. It owns the FHEM callbacks, DevIo WebSocket integration, authentication, command handling, status parsing, readings, and embedded English and German command reference.

The development infrastructure is deliberately separate:

- `t/` contains structural tests, minimal FHEM/DevIo stubs, and synthetic fixtures.
- `scripts/` contains repository and command-reference checks plus the CI entry point.
- `.github/workflows/ci.yml` invokes the same entry point used locally.
- `docs/PROTOCOL-SOURCES.md` records protocol provenance and confidence without promoting guesses to documented behavior.
- Embedded META data and the central version in `72_Wattpilot.pm` are validated by `scripts/check_meta.pl`.
- Release tooling creates reproducible, verified artifacts only below ignored `dist/`.

The stubs are not an FHEM simulator. They exist only to compile and load the module and to inspect its registered callbacks. No test in this repository establishes real FHEM, network, WebSocket, authentication, or Wattpilot compatibility.
