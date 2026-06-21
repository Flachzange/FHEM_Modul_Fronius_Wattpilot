# Review checklist

- [ ] The change is scoped to the stated issue.
- [ ] `72_Wattpilot.pm` remains the authoritative module source.
- [ ] Runtime behavior, readings, commands, authentication, and WebSocket handling are unchanged unless explicitly in scope.
- [ ] API claims distinguish documented, empirically confirmed, and unknown meanings.
- [ ] Tests and fixtures contain only minimal synthetic data.
- [ ] No passwords, hashes, real device identifiers, private addresses, signed URLs, or other sensitive data are present.
- [ ] `scripts/ci.sh` passes completely.
- [ ] Generated files under `dist/` are not committed.
- [ ] The pull request is draft unless it is intentionally ready for review.

