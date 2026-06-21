# Testing

Run the complete local check suite from the repository root:

```sh
scripts/ci.sh
```

It checks Perl syntax, loads the module with minimal stubs, validates callback registration and global subroutine structure, inspects both command-reference languages and anchors, validates synthetic JSON fixtures, and checks the required repository structure.

These checks do not connect to FHEM or a Wattpilot. They do not exercise a real WebSocket, authentication exchange, device command, or reading update.

