#!/usr/bin/env sh
set -eu
python3 - <<'PY'
from pathlib import Path
p = Path('README.md')
s = p.read_text(encoding='utf-8')
old = 'vollständige sanitiserte Beobachtung'
assert s.count(old) == 1
p.write_text(s.replace(old, 'vollständige bereinigte Beobachtung', 1), encoding='utf-8')
PY
