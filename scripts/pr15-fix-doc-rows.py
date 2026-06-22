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
    '| `frc` | inferred forced state | `Laden_starten` | `forceState` | read: 0 Start, 1 Stop; write: Start→0, Stop→1; immediate | current implementation; device writability unverified |',
    '| `frc` | forced-state candidate; semantics conflict | `Laden_starten` | `forceState` | current 1.x reads 0 Start, 1 Stop and writes Start→0, Stop→1; pinned Wattpilot-specific sources instead state 0 Neutral, 1 Off, 2 On | observed value 0 only; current implementation conflicts with pinned commits `4712ba3b8409fda55303870c047038b1b221d7ff` and `498aa8709f198fcde2b41159ad99dc02e57accc9`; actual Flex 43.4 enum/writability unverified |',
    'frc mapping row',
)

one(
    '| `amp` | inferred current limit/A | `Strom` | `chargingCurrent` | copied immediately; write accepts integer syntax and sends value | current implementation; device writability/range unverified by capture |',
    '| `amp` | charging-current candidate in A; accepted range conflicts by source/scope | `Strom` | `chargingCurrent` | current 1.x copies immediately and sends any unsigned integer; observed Flex value and `cll.currentLimitMax` are 32; pinned older Wattpilot source states 6–16; Issue #8 targets 6–32 | observed Flex structure/value plus conflicting older third-party evidence; actual Flex 43.4 write range and writability unverified |',
    'amp mapping row',
)

one(
    '| `amp` | number | `32` | Current 1.x implementation interprets this as configured charging current. | A (implementation interpretation) | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; value `32` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |',
    '| `amp` | number | `32` | Current 1.x interprets this as configured charging current. The observed Flex value and `cll.currentLimitMax` are 32, while a pinned older Wattpilot-specific source states a 6–16 range. | A (current implementation and older third-party interpretation) | current 1.x reads and writes the field; pinned older source marks it R/W; actual Flex 43.4 writability and accepted range are unverified | observed value 32; conflicting older third-party 6–16 candidate; Issue #8 target 6–32 | Issue #11 sanitized capture; `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff`; Issue #8. Model/firmware scope conflict remains explicit. |',
    'amp field row',
)

one(
    '| `frc` | number | `0` | Current 1.x implementation interprets this as forced charging state. | unknown | read and written by current 1.x implementation; device writability not established by this capture | inferred from current implementation; only value `0` observed | Issue #11 sanitized capture; historical API aliases are not promoted to facts. |',
    '| `frc` | number | `0` | Current 1.x interprets 0 as Start and 1 as Stop. Two pinned Wattpilot-specific sources instead state 0 Neutral, 1 Off, 2 On. | unknown | current 1.x reads/writes it; both pinned third-party sources mark it R/W; actual Flex 43.4 writability is unverified | observed numeric 0 only; current implementation conflicts with pinned third-party enum | Issue #11 sanitized capture; `joscha82/wattpilot` commit `4712ba3b8409fda55303870c047038b1b221d7ff`; `ruaan-deysel/wattpilot-api` commit `498aa8709f198fcde2b41159ad99dc02e57accc9`; Issue #8. |',
    'frc field row',
)

p.write_text(s, encoding='utf-8')
