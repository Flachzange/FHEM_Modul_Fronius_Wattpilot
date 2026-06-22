#!/usr/bin/env python3
from pathlib import Path

p = Path('docs/WATTPILOT-FLEX-JSON-API.md')
s = p.read_text(encoding='utf-8')

def one(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1 match, found {n}')
    s = s.replace(old, new, 1)

one(
    '| Current implementation behavior | Directly visible in root `72_Wattpilot.pm`; describes what FHEM 1.x currently does, not what the device specification promises. |\n| Historical compilation |',
    '| Current implementation behavior | Directly visible in root `72_Wattpilot.pm`; describes what FHEM 1.x currently does, not what the device specification promises. |\n| Pinned Wattpilot-specific third-party evidence | Reproducible statements from an identified external Wattpilot implementation at a pinned commit. This is neither an official Fronius specification nor proof for Flex 43.4. |\n| Historical compilation |',
    'evidence class',
)

one(
    '| `frc` | `0` | Current 1.x candidates: 0 Start, 1 Stop | Current implementation only; capture directly observes only numeric 0; writability unverified. |',
    '| `frc` | `0` | Current 1.x: 0 Start, 1 Stop. Pinned Wattpilot-specific sources: 0 Neutral, 1 Off, 2 On. | The capture proves only numeric value 0. Current 1.x conflicts with the two pinned third-party sources; the actual Flex 43.4 enum and writability remain unverified. |',
    'frc enum row',
)

old = 'No go-e enum is promoted to Wattpilot fact here. Historical or third-party candidates require independent Wattpilot-specific evidence.\n\n## Current FHEM mapping and planned 2.0 names'
new = '''No go-e enum is promoted to Wattpilot fact here. Historical or third-party candidates require independent Wattpilot-specific evidence.

## Known evidence conflicts

The following conflicts are deliberately retained rather than silently resolved. They identify where the observed Flex 43.4 payload, current FHEM 1.x behavior, pinned Wattpilot-specific third-party implementations, and planned fixes do not yet form one verified specification.

### `frc` force-state enum and writability

- **Observed Flex 43.4 capture:** `frc` is a JSON number and the sanitized sample contains `0`. This proves neither the enum meaning nor writability.
- **Current FHEM 1.x behavior:** reads `0` as `Start`, `1` as `Stop`, and sends `0` for Start and `1` for Stop.
- **Pinned Wattpilot-specific third-party evidence:** both `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff` and `ruaan-deysel/wattpilot-api` commit `498aa8709f198fcde2b41159ad99dc02e57accc9` describe `0=Neutral`, `1=Off`, `2=On` and mark the field R/W.
- **Repository issue state:** Issue #8 records the current FHEM mapping as a confirmed functional defect and plans Start→`2`, Stop→`1`.
- **Remaining uncertainty:** the two pinned implementations are not official Fronius documentation, and the enum plus write behavior have not been reproduced on the captured Flex Home 22 C6 with firmware 43.4/protocol 4.

### `amp` range, unit, and writability

- **Observed Flex 43.4 capture:** `amp` is numeric with sanitized value `32`; `cll.currentLimitMax` and `cll.requestedCurrent` are also `32`. These observations support neither a complete accepted range nor writability by themselves.
- **Current FHEM 1.x behavior:** interprets `amp` as amperes, displays it directly, accepts every unsigned integer, and sends it through `setValue`.
- **Pinned older Wattpilot-specific evidence:** `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff` describes `amp` as R/W amperes with range 6–16. Its older and incompletely established device/firmware scope conflicts with the observed Flex value 32 and must not be generalized to this Flex model.
- **Repository issue state:** Issue #8 targets validation of the current public command to 6–32 A.
- **Remaining uncertainty:** the actual accepted Flex 43.4 write range, validation behavior, and error response still require applicable documentation or a reproducible device test.

## Current FHEM mapping and planned 2.0 names'''
one(old, new, 'known conflicts section')

p.write_text(s, encoding='utf-8')
