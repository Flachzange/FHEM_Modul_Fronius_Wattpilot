# Review checklist

- [ ] The change is scoped to the stated issue.
- [ ] `72_Wattpilot.pm` remains the authoritative module source.
- [ ] Runtime behavior, readings, commands, authentication, and WebSocket handling are unchanged unless explicitly in scope.
- [ ] API claims distinguish documented, empirically confirmed, and unknown meanings.
- [ ] Tests and fixtures contain only minimal synthetic data.
- [ ] No passwords, hashes, real device identifiers, private addresses, signed URLs, or other sensitive data are present.
- [ ] `scripts/ci.sh` passes completely.
- [ ] `scripts/build-release.sh` passes; `scripts/release-files.txt` contains every intended maintained package source; artifact names and SHA-256 sums are recorded in the PR.
- [ ] Source, META, changelog, package, and artifact versions agree.
- [ ] Protocol claims cite `docs/PROTOCOL-SOURCES.md` with an explicit confidence class.
- [ ] FHEM callback-order assumptions are checked against the pinned revision; the PR states that deterministic stubs do not replace real FHEM/Wattpilot integration tests.
- [ ] Generated files under `dist/` are not committed.
- [ ] The pull request is draft unless it is intentionally ready for review.
