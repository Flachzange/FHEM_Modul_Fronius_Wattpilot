use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Storable qw(dclone);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
require $module;

sub fresh_device {
    my ($name) = @_;
    $name //= 'testWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME       => $name,
        TYPE       => 'Wattpilot',
        FUUID      => '00000000-0000-0000-0000-000000000037',
        DeviceName => 'ws:192.0.2.37:80/ws',
        STATE      => 'connected',
        TEST_OPEN  => 1,
        helper     => {
            authenticated                  => 1,
            authPending                    => 1,
            authHashMode                   => 'pbkdf2',
            jsonBuffer                     => '{',
            idleRefreshPending             => 1,
            idleRefreshAwaitingReconnectNrg => 1,
            pendingRequests                => {
                37 => { key => 'amp', value => 16, sentAt => 1 },
            },
        },
    };
    $defs{$name} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-hash';
    return $hash;
}

sub definition_hash {
    my ($name) = @_;
    $name //= 'newWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME  => $name,
        TYPE  => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000038',
        helper => { preexisting => 'unchanged' },
    };
    $defs{$name} = $hash;
    return $hash;
}

my %registration;
main::Wattpilot_Initialize(\%registration);
ok(!exists $registration{GetFn}, 'module does not register an empty GetFn');
ok(!defined &main::Wattpilot_Get, 'unused Wattpilot_Get callback is absent');
ok(index($registration{AttrList}, 'debug') < 0,
    'removed no-op debug attribute is absent from AttrList');
ok(index($registration{AttrList}, 'defaultAmp') < 0,
    'removed no-op defaultAmp attribute is absent from AttrList');

my %valid_existing_value = (
    interval          => '30',
    update_while_idle => '0',
    disable           => '0',
    rawJsonLog        => '0',
    authHash          => 'auto',
    authHashCost      => '8',
);

my @invalid_attributes = (
    [interval          => '-1',       qr/interval must be an integer from 0 to 300/],
    [interval          => '301',      qr/interval must be an integer from 0 to 300/],
    [interval          => '1.5',      qr/interval must be an integer from 0 to 300/],
    [interval          => 'not-a-number', qr/interval must be an integer from 0 to 300/],
    [update_while_idle => '7',        qr/update_while_idle must be 0 or 1/],
    [disable           => 'true',     qr/disable must be 0 or 1/],
    [rawJsonLog        => 'yes',      qr/rawJsonLog must be 0 or 1/],
    [authHash          => 'sha256',   qr/authHash must be one of auto, pbkdf2, bcrypt/],
    [authHashCost      => '3',        qr/authHashCost must be an integer from 4 to 14/],
    [authHashCost      => '15',       qr/authHashCost must be an integer from 4 to 14/],
    [authHashCost      => '8.0',      qr/authHashCost must be an integer from 4 to 14/],
);

for my $case (@invalid_attributes) {
    my ($attribute, $value, $error_re) = @$case;
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{$attribute} = $valid_existing_value{$attribute};
    my $hash_before = dclone($hash);
    my $keys_before = dclone(\%DevIo::KEY_VALUES);
    my $attr_before = dclone(\%attr);

    my $error = DevIo::command_attr($hash->{NAME}, $attribute, $value);
    like($error, $error_re, "$attribute rejects invalid set value");
    is_deeply($hash, $hash_before, "$attribute invalid value leaves device state unchanged");
    is_deeply(\%DevIo::KEY_VALUES, $keys_before,
        "$attribute invalid value leaves credentials unchanged");
    is_deeply(\%attr, $attr_before,
        "$attribute invalid value is rejected before FHEM attribute storage");
    is(scalar @DevIo::KEY_OPERATIONS, 0,
        "$attribute invalid value performs no credential I/O");
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        "$attribute invalid value creates no timer");
    is(scalar @DevIo::REMOVED_TIMERS, 0,
        "$attribute invalid value removes no timer");
    is(scalar @DevIo::CLOSES, 0,
        "$attribute invalid value does not close DevIo");
    is(scalar @DevIo::OPENS, 0,
        "$attribute invalid value does not open DevIo");
    is(scalar @DevIo::READING_UPDATES, 0,
        "$attribute invalid value creates no reading event");
    is(scalar @DevIo::LOGS, 0,
        "$attribute invalid value creates no misleading diagnostic");
}

my @valid_attributes = (
    [interval          => '0'],
    [interval          => '300'],
    [update_while_idle => '0'],
    [update_while_idle => '1'],
    [disable           => '0'],
    [disable           => '1'],
    [rawJsonLog        => '0'],
    [rawJsonLog        => '1'],
    [authHash          => 'auto'],
    [authHash          => 'pbkdf2'],
    [authHash          => 'bcrypt'],
    [authHashCost      => '4'],
    [authHashCost      => '14'],
);

for my $case (@valid_attributes) {
    my ($attribute, $value) = @$case;
    my $hash = fresh_device();
    is(DevIo::command_attr($hash->{NAME}, $attribute, $value), undef,
        "$attribute accepts documented value $value");
    is($attr{$hash->{NAME}}{$attribute}, $value,
        "$attribute documented value $value is stored after AttrFn accepts it");
}

for my $attribute (qw(
    interval update_while_idle disable rawJsonLog authHash authHashCost
)) {
    my $hash = fresh_device();
    is(main::Wattpilot_Attr('del', $hash->{NAME}, $attribute, undef), undef,
        "$attribute deletion bypasses set-value validation");
}

{
    my $hash = fresh_device();
    my $before = dclone($hash);
    is(DevIo::command_attr($hash->{NAME}, 'room', 'Garage'), undef,
        'generic readingFnAttribute remains outside module validation');
    is($attr{$hash->{NAME}}{room}, 'Garage',
        'generic attribute is stored after the module callback accepts it');
    is_deeply($hash, $before, 'generic attribute callback has no module side effects');
}

my @invalid_definitions = (
    ['newWallbox Wattpilot', qr/^Usage: define <name> Wattpilot <IP> \[Serial\]$/,
        'missing host is rejected with usage'],
    ['newWallbox Wattpilot 192.0.2.37 123456 extra',
        qr/^Usage: define <name> Wattpilot <IP> \[Serial\]$/,
        'additional argument is rejected with usage'],
    ['newWallbox Wattpilot 192.0.2.37 ABC123',
        qr/^Serial must contain digits only$/,
        'alphanumeric serial is rejected'],
    ['newWallbox Wattpilot 192.0.2.37 12-34',
        qr/^Serial must contain digits only$/,
        'punctuated serial is rejected'],
);

for my $case (@invalid_definitions) {
    my ($definition, $error_re, $label) = @$case;
    my $hash = definition_hash();
    my $hash_before = dclone($hash);
    my $error = main::Wattpilot_Define($hash, $definition);
    like($error, $error_re, $label);
    is_deeply($hash, $hash_before, "$label without mutating the device hash");
    is(scalar @DevIo::KEY_OPERATIONS, 0, "$label without credential access");
    is(scalar @DevIo::ACTIVE_TIMERS, 0, "$label without scheduling timers");
    is(scalar @DevIo::CLOSES, 0, "$label without closing DevIo");
    is(scalar @DevIo::OPENS, 0, "$label without opening DevIo");
    is(scalar @DevIo::READING_UPDATES, 0, "$label without reading updates");
    is(scalar @DevIo::LOGS, 0, "$label without runtime diagnostics");
}

{
    my $hash = definition_hash();
    is(main::Wattpilot_Define(
        $hash, 'newWallbox Wattpilot wallbox.example.invalid'), undef,
        'three-field Define accepts a DevIo-compatible hostname');
    is($hash->{DeviceName}, 'ws:wallbox.example.invalid:80/ws',
        'Define constructs the expected WebSocket endpoint');
    ok(!defined $hash->{SERIAL}, 'serial remains undefined when omitted');
    is($hash->{STATE}, 'passwordMissing',
        'valid Define without a credential reports passwordMissing');
}

{
    my $hash = definition_hash();
    is(main::Wattpilot_Define(
        $hash, 'newWallbox Wattpilot 192.0.2.37 00123456'), undef,
        'four-field Define accepts a digits-only serial');
    is($hash->{SERIAL}, '00123456', 'Define preserves leading zeroes in the serial');
}

{
    my $hash = fresh_device('modifyWallbox');
    $hash->{DEF} = '192.0.2.37 00123456';
    $hash->{SERIAL} = '00123456';
    $DevIo::SELECTLIST{'modifyWallbox.ws:192.0.2.37:80/ws'} = $hash;

    is(DevIo::command_modify(
        'modifyWallbox', '198.51.100.44 00999999'), undef,
        'modify accepts a valid endpoint and serial change');
    is($hash->{DEF}, '198.51.100.44 00999999',
        'FHEM keeps the accepted new DEF');
    is($hash->{DeviceName}, 'ws:198.51.100.44:80/ws',
        'modify installs the new WebSocket endpoint');
    is($hash->{SERIAL}, '00999999',
        'modify installs the new serial');
    ok(!$hash->{TEST_OPEN},
        'modify closes the old established connection');
    ok(!exists $DevIo::SELECTLIST{'modifyWallbox.ws:192.0.2.37:80/ws'},
        'modify removes the old DevIo select-list owner');
    is(scalar @DevIo::CLOSES, 1,
        'modify closes exactly one old DevIo context');
    is(scalar @DevIo::ACTIVE_TIMERS, 1,
        'modify schedules exactly one reconnect');
    is($hash->{STATE}, 'disconnected',
        'modify exposes a truthful disconnected state before reconnect');
    ok(!exists $hash->{helper}{authenticated}
        && !exists $hash->{helper}{authPending}
        && !exists $hash->{helper}{jsonBuffer},
        'modify clears old authentication and parser state');
    ok(!exists $hash->{helper}{idleRefreshPending}
        && !exists $hash->{helper}{idleRefreshAwaitingReconnectNrg}
        && !exists $hash->{helper}{idleRefreshAttempted},
        'modify clears old idle-refresh state');
    is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
        'modify terminates pending commands explicitly');
    is($hash->{READINGS}{lastCommandError}{VAL}, 'definition changed',
        'modify reports the pending-command termination reason');
}

{
    my $hash = fresh_device('sameWallbox');
    $hash->{DEF} = '192.0.2.37 00123456';
    $hash->{SERIAL} = '00123456';
    my $generation = $hash->{helper}{lifecycleGeneration} // 0;

    is(DevIo::command_modify(
        'sameWallbox', '192.0.2.37 00123456'), undef,
        'modify accepts an unchanged definition');
    ok($hash->{TEST_OPEN},
        'unchanged modify preserves the established connection');
    is(scalar @DevIo::CLOSES, 0,
        'unchanged modify does not close DevIo');
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        'unchanged modify does not schedule a reconnect');
    is($hash->{helper}{lifecycleGeneration} // 0, $generation,
        'unchanged modify does not advance lifecycle generation');
    ok(exists $hash->{helper}{pendingRequests}{37},
        'unchanged modify preserves pending command state');
}

{
    my $hash = fresh_device('rollbackWallbox');
    $hash->{DEF} = '192.0.2.37 00123456';
    $hash->{SERIAL} = '00123456';
    my $before = dclone($hash);
    my $keys_before = dclone(\%DevIo::KEY_VALUES);

    like(DevIo::command_modify(
        'rollbackWallbox', '198.51.100.44 invalid'),
        qr/^Serial must contain digits only$/,
        'invalid modify is vetoed');
    is($hash->{DEF}, '192.0.2.37 00123456',
        'FHEM restores the old DEF after modify veto');
    is_deeply($hash, $before,
        'invalid modify leaves all module state unchanged');
    is_deeply(\%DevIo::KEY_VALUES, $keys_before,
        'invalid modify leaves credentials unchanged');
    is(scalar @DevIo::CLOSES, 0,
        'invalid modify does not close DevIo');
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        'invalid modify does not schedule timers');
    is(scalar @DevIo::READING_UPDATES, 0,
        'invalid modify emits no reading updates');
}


{
    my $hash = fresh_device('deferredModifyWallbox');
    $hash->{DEF} = '192.0.2.37 00123456';
    $hash->{SERIAL} = '00123456';
    $hash->{TEST_OPEN} = 0;
    delete $hash->{TCPDev};
    delete $hash->{CD};
    $DevIo::OPEN_MODE = 'deferred';

    main::Wattpilot_Connect($hash);
    ok(ref($hash->{helper}{openInFlight}) eq 'HASH',
        'deferred open is owned before modify');
    is(scalar @DevIo::OPEN_CALLBACKS, 1,
        'one deferred open callback is pending before modify');

    is(DevIo::command_modify(
        'deferredModifyWallbox', '198.51.100.45 00999998'), undef,
        'modify accepts a change while an asynchronous open is in flight');
    ok($hash->{helper}{pendingReconnectAfterOpen},
        'changed definition transfers reconnect ownership to the stale open callback');
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        'no parallel reconnect timer starts before the stale callback completes');

    DevIo::complete_deferred_open(0);
    ok(!$hash->{TEST_OPEN},
        'stale deferred transport for the old definition is closed');
    ok(!exists $DevIo::SELECTLIST{'deferredModifyWallbox.ws:192.0.2.37:80/ws'},
        'stale old-definition select-list owner is removed');
    is(scalar @DevIo::ACTIVE_TIMERS, 1,
        'stale callback hands off exactly one reconnect for the new definition');
    ok(!exists $hash->{helper}{pendingReconnectAfterOpen},
        'reconnect handoff flag clears after stale callback completion');
}

{
    my $hash = fresh_device('disabledModifyWallbox');
    $hash->{DEF} = '192.0.2.37 00123456';
    $hash->{SERIAL} = '00123456';
    $attr{$hash->{NAME}}{disable} = 1;

    is(DevIo::command_modify(
        'disabledModifyWallbox', '198.51.100.46 00999997'), undef,
        'disabled device accepts a valid definition change');
    ok(!$hash->{TEST_OPEN},
        'disabled modify closes the old established connection');
    is($hash->{STATE}, 'disabled',
        'disabled modify derives the truthful disabled state');
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        'disabled modify does not schedule a reconnect');
}

done_testing;
