use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'reviewWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000029',
        DeviceName => 'ws:192.0.2.29:80/ws', STATE => 'disconnected',
        SERIAL => '10000029', TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub logs {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

sub seed_auth_state {
    my ($hash) = @_;
    $hash->{helper}{authenticated} = 1;
    $hash->{helper}{authPending} = 1;
    $hash->{helper}{authHashMode} = 'pbkdf2';
    $hash->{helper}{deviceType} = 'wattpilot';
    $hash->{helper}{protocol} = 2;
    $hash->{helper}{pendingRequests}{1} = { key => 'amp', value => 16, sentAt => 1 };
}

sub auth_state_is_clear {
    my ($hash) = @_;
    return !exists($hash->{helper}{authenticated})
        && !exists($hash->{helper}{authPending})
        && !exists($hash->{helper}{authHashMode})
        && !exists($hash->{helper}{deviceType})
        && !exists($hash->{helper}{protocol})
        && !exists($hash->{helper}{pendingRequests});
}

my $hash = fresh_device();
eval { main::Wattpilot_DerivePasswordHash($hash, 'x', '10000029') };
like($@, qr/hash mode was not selected/,
    'password derivation fails closed without a selected hash mode');

$hash = fresh_device();
for my $invalid_type (
    '{"type":123}', '{"type":true}', '{"type":false}', '{"type":null}',
    '{"type":[]}', '{"type":{}}',
) {
    @DevIo::LOGS = ();
    is(main::Wattpilot_Parse($hash, $invalid_type), 1,
        'a non-string JSON type remains one structurally decoded document');
    like(logs(), qr/missing or invalid type/,
        'the decoded non-string type is rejected before message dispatch');
}
@DevIo::LOGS = ();
is(main::Wattpilot_Parse($hash, '{"type":"123"}'), 1,
    'a numeric-looking JSON string remains a valid string type');
unlike(logs(), qr/missing or invalid type/,
    'a numeric-looking JSON string is not confused with a JSON number');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$hash->{READINGS}{configChargingCurrent}{VAL} = 20;
my $maximum_documents = join '', map {
    encode_json({ type => 'deltaStatus', status => { amp => 20 } })
} 1..256;
is(main::Wattpilot_Parse($hash, $maximum_documents), 256,
    'exactly 256 concatenated documents are accepted');
my $too_many_documents = join '', map {
    encode_json({ type => 'deltaStatus', status => { amp => 21 } })
} 1..257;
is(main::Wattpilot_Parse($hash, $too_many_documents), 0,
    '257 concatenated documents are rejected');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 20,
    'document-count rejection is atomic');

for my $attr_command ([set => 'bcrypt', 'pbkdf2'], [del => undef, 'bcrypt']) {
    my ($command, $value, $old_value) = @$attr_command;
    $hash = fresh_device();
    $attr{$hash->{NAME}}{authHash} = $old_value;
    seed_auth_state($hash);
    $hash->{STATE} = 'connected';
    $hash->{READINGS}{state}{VAL} = 'connected';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'x';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'stale-signing-key';
    InternalTimer(gettimeofday()+10, 'Wattpilot_Connect', $hash, 0);
    InternalTimer(gettimeofday()+20, 'Wattpilot_RequestTimeout', $hash, 0);

    main::Wattpilot_Attr($command, $hash->{NAME}, 'authHash', $value);

    ok(auth_state_is_clear($hash),
        "authHash $command clears connection-scoped authentication and command state");
    ok(!$hash->{TEST_OPEN},
        "authHash $command closes the connection");
    is($hash->{STATE}, 'disconnected',
        "authHash $command requests a fresh login");
    is(scalar(grep { $_->[1] eq 'Wattpilot_Connect' } @DevIo::ACTIVE_TIMERS), 1,
        "authHash $command leaves exactly one reconnect timer");
    is(scalar @DevIo::ACTIVE_TIMERS, 1,
        "authHash $command removes stale request and reconnect timers");
    ok(!exists $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'},
        "authHash $command invalidates the persisted signing hash before reconnect");
    @DevIo::WRITES = ();
    like(main::Wattpilot_SendSecure($hash, 'amp', 16),
        qr/disconnected|not authenticated/,
        "authHash $command blocks the previous authenticated session");
    is(scalar @DevIo::WRITES, 0,
        "authHash $command sends no command with the stale signing key");
}

$hash = fresh_device();
$attr{$hash->{NAME}}{disable} = 1;
$attr{$hash->{NAME}}{authHash} = 'pbkdf2';
seed_auth_state($hash);
$hash->{STATE} = 'connected';
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'x';
main::Wattpilot_Attr('set', $hash->{NAME}, 'authHash', 'bcrypt');
is($hash->{STATE}, 'disabled', 'authHash change preserves disabled state');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'authHash change schedules no reconnect while disabled');

$hash = fresh_device();
$attr{$hash->{NAME}}{authHash} = 'pbkdf2';
seed_auth_state($hash);
$hash->{STATE} = 'connected';
main::Wattpilot_Attr('set', $hash->{NAME}, 'authHash', 'bcrypt');
is($hash->{STATE}, 'passwordMissing',
    'authHash change reports a missing password instead of reconnecting');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'authHash change schedules no reconnect without a password');

$hash = fresh_device();
$attr{$hash->{NAME}}{authHash} = 'pbkdf2';
seed_auth_state($hash);
$hash->{STATE} = 'connected';
$DevIo::GET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_password'} =
    'synthetic credential read failure';
main::Wattpilot_Attr('set', $hash->{NAME}, 'authHash', 'bcrypt');
is($hash->{STATE}, 'credentialError',
    'authHash change preserves credential read errors');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'authHash change schedules no reconnect after a credential read error');

$hash = fresh_device();
$attr{$hash->{NAME}}{authHash} = 'pbkdf2';
seed_auth_state($hash);
$hash->{STATE} = 'connected';
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'x';
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'stale-signing-key';
$DevIo::SET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
    'synthetic hash deletion failure';
main::Wattpilot_Attr('set', $hash->{NAME}, 'authHash', 'bcrypt');
is($hash->{STATE}, 'credentialError',
    'authHash change fails closed when persisted signing hash cannot be invalidated');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'}, 'stale-signing-key',
    'failed authHash invalidation preserves the old signing hash');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'authHash invalidation failure schedules no reconnect');

done_testing;
