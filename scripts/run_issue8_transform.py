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

module_path = Path('72_Wattpilot.pm')
module = module_path.read_text(encoding='utf-8')
old = """sub Wattpilot_ClearCommandState($) {
    my ($hash) = @_;
    RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout');
    delete $hash->{helper}{pendingRequests};
    delete $hash->{helper}{authenticated};
}
"""
new = """sub Wattpilot_ClearCommandState($) {
    my ($hash) = @_;
    my $pending = $hash->{helper}{pendingRequests};
    RemoveInternalTimer($hash, 'Wattpilot_RequestTimeout')
        if ref($pending) eq 'HASH' && keys %$pending;
    delete $hash->{helper}{pendingRequests};
    delete $hash->{helper}{authenticated};
}
"""
if module.count(old) != 1:
    raise SystemExit(f'command-state cleanup anchor count={module.count(old)}')
module_path.write_text(module.replace(old, new, 1), encoding='utf-8')

test_path = Path('t/72_Wattpilot.t')
test = test_path.read_text(encoding='utf-8')
anchor = """    return $hash;
}

sub synthetic_device {
"""
helper = """    return $hash;
}

sub mark_command_ready {
    my ($hash) = @_;
    $hash->{TEST_OPEN} = 1;
    $hash->{STATE} = 'connected';
    $hash->{helper}{authenticated} = 1;
    delete $hash->{helper}{pendingRequests};
    delete $hash->{msg_id};
}

sub synthetic_device {
"""
if test.count(anchor) != 1:
    raise SystemExit(f'test helper anchor count={test.count(anchor)}')
test = test.replace(anchor, helper, 1)
call = "main::Wattpilot_SendSecure($hash, 'amp', 16);"
if test.count(call) != 5:
    raise SystemExit(f'expected 5 existing secure-command calls, found {test.count(call)}')
test = test.replace(call, "mark_command_ready($hash);\n" + call)
test_path.write_text(test, encoding='utf-8')
