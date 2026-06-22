#!/usr/bin/env python3
from pathlib import Path

path = Path('scripts/apply_issue8.py')
text = path.read_text(encoding='utf-8')
replacements = [
    ('Starts or stops charging manually.', 'Manually starts or stops the charging process.'),
    ('Sets the charging current in ampere (between 6A and 32A).',
     'Sets the charging current in Amperes (between 6A and 32A).'),
    ('Startet oder stoppt den Ladevorgang manuell (entspricht dem Parameter <code>frc</code>).</li>',
     'Startet oder stoppt die Ladung manuell (entspricht dem Parameter <code>frc</code>).</li>'),
]
for old, new in replacements:
    if old not in text:
        raise SystemExit(f'missing transform anchor: {old}')
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8')
exec(compile(text, str(path), 'exec'), {'__name__': '__main__'})
