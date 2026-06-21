# Repository guidance

- `72_Wattpilot.pm` in the repository root is the sole technical source of truth.
- Do not speculate about API fields. Keep documented, empirically confirmed, and unknown meanings clearly separated.
- Missing fields in `deltaStatus` must never delete readings.
- Add set commands only for fields that are unambiguously documented as writable.
- Never place sensitive device data in tests, logs, or fixtures.
- Use synthetic documentation values for addresses and identifiers.
- Name branches `codex/<short-description>` and open draft pull requests by default.
- Do not commit generated release artifacts, including anything below `dist/`.

