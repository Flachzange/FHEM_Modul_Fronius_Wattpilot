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
    $DevIo::NOW = 1000;
    my $hash = {
        NAME => 'lifeWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000009',
        DeviceName => 'ws:192.0.2.9:80/ws',
        STATE => 'disconnected',
        SERIAL => '10000009',
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub nrg {
    my ($power) = @_;
    return [230, 231, 232, 0, 0, 0, 0, 0, 0, 0, 0, $power, 0, 0, 0, 0];
}

sub status_msg {
    my ($status) = @_;
    return encode_json({ type => 'deltaStatus', status => $status });
}

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

sub stable_password_key {
    my ($hash) = @_;
    return 'Wattpilot_' . $hash->{FUUID} . '_password';
}

sub set_stable_password {
    my ($hash, $password) = @_;
    $DevIo::KEY_VALUES{stable_password_key($hash)} = $password // 'synthetic-password';
}

sub due_in {
    my ($seconds) = @_;
    $DevIo::NOW += $seconds;
    DevIo::run_due_timers($DevIo::NOW);
}

sub seed_telemetry_clock {
    my ($hash, $interval) = @_;
    $hash->{helper}{telemetryClock} = {
        lastFlush => $DevIo::NOW,
        nextFlush => $DevIo::NOW + $interval,
        interval => $interval,
    };
}

my %registration;
main::Wattpilot_Initialize(\%registration);
ok(ref($registration{ShutdownFn}) eq 'CODE', 'ShutdownFn is registered');

my $hash = fresh_device();
$attr{$hash->{NAME}}{disable} = 1;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '0');
is(timer_count('connect'), 1,
    'disable=0 schedules connect using the new AttrFn value before FHEM commits attr');
$attr{$hash->{NAME}}{disable} = 0;
due_in(1);
is($hash->{STATE}, 'authenticating',
    'connect timer created during AttrFn remains valid after the framework commits disable=0');

$hash = fresh_device();
$hash->{TEST_OPEN} = 1;
$hash->{FD} = 99;
$hash->{helper}{car_state} = 1;
$hash->{READINGS}{power}{VAL} = '55.00';
main::Wattpilot_Attr('set', $hash->{NAME}, 'update_while_idle', '1');
is(timer_count('idle_refresh'), 0,
    'changing update_while_idle while already idle does not create a refresh episode');
$hash->{helper}{car_state} = 2;
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
is(timer_count('idle_refresh'), 1,
    'charging-to-idle starts the bounded refresh independently of the attribute');
my $idle_timer_ctx = $hash->{helper}{timers}{idle_refresh};
main::Wattpilot_Attr('set', $hash->{NAME}, 'update_while_idle', '0');
is(timer_count('idle_refresh'), 1,
    'changing update_while_idle does not cancel an active refresh episode');
ok($hash->{helper}{timers}{idle_refresh} == $idle_timer_ctx,
    'attribute change preserves the existing refresh owner');

$hash = fresh_device();
$hash->{helper}{car_state} = 1;
$hash->{READINGS}{power}{VAL} = '123.00';
main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '123.00',
    'update_while_idle=0 keeps idle high-frequency readings passive');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$hash->{helper}{car_state} = 1;
main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'update_while_idle=1 processes real idle nrg values');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 0;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
$hash->{FD} = 99;
seed_telemetry_clock($hash, 300);
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1, nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'update_while_idle=0 still allows transition-message nrg once');
is(timer_count('idle_refresh'), 0, 'same-message nrg cancels idle refresh');

main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(555) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'subsequent ordinary idle nrg stays passive with update_while_idle=0');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 0;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
$hash->{FD} = 99;
seed_telemetry_clock($hash, 300);
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
is(timer_count('idle_refresh'), 1, 'update_while_idle=0 arms one refresh timer after charging');
due_in(10);
main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'nrg inside the 30-second idle window bypasses rate limiting');
is(timer_count('idle_refresh'), 0, 'authoritative idle nrg clears the pending window');
is(scalar @DevIo::CLOSES, 0, 'authoritative idle nrg avoids refresh reconnect');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$hash->{TEST_OPEN} = 1;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
is($hash->{READINGS}{power}{VAL}, '1388.00',
    'idle timeout never synthesizes zero electrical readings');
is(scalar @DevIo::CLOSES, 1, 'missing nrg triggers one controlled refresh close');
is(timer_count('connect'), 1, 'missing nrg schedules one refresh reconnect');
due_in(1);
is(timer_count('idle_refresh'), 0, 'refresh reconnect does not start a second idle timer');
main::Wattpilot_Parse($hash, status_msg({ car => 2 }));
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
is(timer_count('idle_refresh'), 1,
    'a later charging phase opens a new idle episode');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
seed_telemetry_clock($hash, 300);
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
due_in(1);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::false,
    status => { car => 1, nrg => nrg(0) },
}));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'first authoritative nrg after idle refresh reconnect bypasses interval=300');
ok(!exists $hash->{helper}{idleRefreshAwaitingReconnectNrg},
    'refresh reconnect nrg consumes the one-shot bypass');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
seed_telemetry_clock($hash, 300);
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
due_in(1);
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::true,
    status => { car => 1, amp => 6 },
}));
main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'refresh reconnect nrg bypass survives nrg-less partial status');
is(timer_count('idle_refresh'), 0,
    'partial status without nrg does not create a reconnect loop');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
seed_telemetry_clock($hash, 300);
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::false,
    status => { car => 1, amp => 16 },
}));
ok(!exists $hash->{helper}{idleRefreshAwaitingReconnectNrg},
    'refresh reconnect without nrg ends the one-shot wait without looping');
is(timer_count('idle_refresh'), 0,
    'refresh reconnect without nrg does not arm another idle timer');

$hash = fresh_device();
$hash->{READINGS}{power}{VAL} = '42.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
is($hash->{READINGS}{power}{VAL}, '42.00',
    'missing delta fields remain unchanged');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
is($hash->{STATE}, 'authenticating', 'successful open enters authenticating');
is(timer_count('lifecycle_timeout'), 1, 'authenticating has one lifecycle timeout');
due_in(30);
is($hash->{STATE}, 'authTimeout', 'authentication timeout is exposed');
is(timer_count('connect'), 1, 'first authentication timeout schedules one retry');
due_in(5);
is($hash->{STATE}, 'authenticating', 'timeout retry uses the normal open path');
due_in(30);
is($hash->{STATE}, 'authTimeout', 'second authentication timeout remains truthful');
is(timer_count('connect'), 0, 'second authentication timeout does not loop');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
is($hash->{STATE}, 'initializing', 'authSuccess alone enters initializing');
is(timer_count('lifecycle_timeout'), 1, 'initializing has one lifecycle timeout');
due_in(30);
is($hash->{STATE}, 'initializationTimeout', 'initialization timeout is exposed');
is(timer_count('connect'), 1, 'first initialization timeout schedules one retry');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
main::Wattpilot_Parse($hash, encode_json({ type => 'authError' }));
is($hash->{STATE}, 'authFailed', 'authError remains fail-closed');
is(timer_count('connect'), 0, 'authError schedules no automatic retry');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::true, status => { amp => 16 },
}));
is($hash->{STATE}, 'connected',
    'partial fullStatus establishes the authenticated session');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 16,
    'partial fullStatus is still applied incrementally');
is(timer_count('lifecycle_timeout'), 0,
    'partial fullStatus cancels the initialization timeout');
my $connected_state = $hash->{STATE};
main::Wattpilot_LifecycleTimeout({
    hash => $hash,
    kind => 'lifecycle_timeout',
    generation => main::Wattpilot_CurrentLifecycleGeneration($hash) - 1,
    name => $hash->{NAME},
    fuuid => $hash->{FUUID},
    phase => 'initialization',
});
is($hash->{STATE}, $connected_state,
    'a stale initialization timeout cannot mutate the established session');
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::true, status => { car => 1 },
}));
is($hash->{READINGS}{carState}{VAL}, 'idle',
    'later partial chunks continue to update only supplied fields');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::true, status => [],
}));
is($hash->{STATE}, 'initializing',
    'non-hash partial status cannot establish initialization');
is(timer_count('lifecycle_timeout'), 1,
    'malformed status leaves the initialization timeout active');

$hash = fresh_device();
$hash->{STATE} = 'authenticating';
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', partial => JSON::true, status => { amp => 14 },
}));
is($hash->{STATE}, 'authenticating',
    'status received before authentication cannot initialize the session');

$hash = fresh_device();
main::Wattpilot_ScheduleConnect($hash, 10);
main::Wattpilot_ScheduleConnect($hash, 20);
is(timer_count('connect'), 1, 'scheduling keeps exactly one connect timer');

$hash = fresh_device();
main::Wattpilot_ScheduleTimer($hash, 'idle_refresh', 10, 'Wattpilot_IdleRefreshTimeout');
my $stale_ctx = $DevIo::ACTIVE_TIMERS[0][2];
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '1');
$stale_ctx->{fn} = 'Wattpilot_IdleRefreshTimeout';
main::Wattpilot_IdleRefreshTimeout($stale_ctx);
is(scalar @DevIo::OPENS, 0, 'stale timer callback after disable is ignored');

$hash = fresh_device();
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
main::Wattpilot_Connect($hash);
is(scalar @DevIo::OPENS, 1, 'parallel DevIo_OpenDev calls are prevented');
main::Wattpilot_Shutdown($hash);
DevIo::complete_deferred_open(0);
is($hash->{STATE}, 'disconnected',
    'old DevIo open callback after shutdown remains ineffective');
ok(!$hash->{TEST_OPEN}, 'stale successful open after shutdown is closed');
is(timer_count('lifecycle_timeout'), 0, 'old DevIo callback after shutdown arms no timeout');

$hash = fresh_device();
$DevIo::OPEN_MODE = 'deferred';
set_stable_password($hash);
main::Wattpilot_Connect($hash);
my $old_key = $hash->{NAME} . '.' . $hash->{DeviceName};
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
DevIo::complete_deferred_open(0);
is($hash->{NAME}, 'renamedLifeWallbox', 'rename test double moved the device name');
ok(!$hash->{TEST_OPEN}, 'deferred open started before rename is closed as stale');
ok(!exists $DevIo::SELECTLIST{$old_key}, 'deferred open completing after rename cleans old-name selectlist key');
is(timer_count('connect'), 1, 'rename keeps exactly one controlled reconnect owner');

$hash = fresh_device();
set_stable_password($hash);
main::Wattpilot_ScheduleConnect($hash, 10);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('connect'), 1, 'rename replaces a pending connect timer under the new name');
is($DevIo::ACTIVE_TIMERS[0][2]{name}, 'renamedLifeWallbox',
    'rename timer context uses the new name');

$hash = fresh_device();
set_stable_password($hash);
main::Wattpilot_Connect($hash);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('lifecycle_timeout'), 0, 'rename cancels an auth lifecycle timeout');
is(timer_count('connect'), 1, 'rename restarts lifecycle after auth timeout cancellation');

$hash = fresh_device();
set_stable_password($hash);
$hash->{helper}{authenticated} = 1;
$hash->{helper}{pendingRequests}{1} = { sentAt => $DevIo::NOW };
main::Wattpilot_ScheduleRequestTimeout($hash);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('command_timeout'), 0, 'rename cancels command timeout context');
is(timer_count('connect'), 1, 'rename restarts lifecycle after command timeout cancellation');

$hash = fresh_device();
$DevIo::GET_KEY_ERRORS{stable_password_key($hash)} = 'synthetic read failure';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is($hash->{STATE}, 'credentialError',
    'rename credential read failure leaves the device in credential error');
is(timer_count('connect'), 0,
    'rename credential read failure schedules no immediate reconnect');
DevIo::complete_deferred_open(0);
is(timer_count('connect'), 0,
    'stale deferred open after rename credential failure schedules no delayed reconnect');

$hash = fresh_device();
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is($hash->{STATE}, 'passwordMissing',
    'active rename without a readable password is fail-closed');
is(timer_count('connect'), 0,
    'active rename without password schedules no reconnect');

$hash = fresh_device();
$DevIo::GET_KEY_ERRORS{stable_password_key($hash)} = 'synthetic read failure';
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is($hash->{STATE}, 'credentialError',
    'active rename with credential read failure reports credential error');
is(timer_count('connect'), 0,
    'active rename with credential read failure schedules no reconnect');

$hash = fresh_device();
$hash->{STATE} = 'disconnected';
main::Wattpilot_Ready($hash);
is($DevIo::OPENS[0][1], 1, 'ReadyFn uses the guarded reopen path');
is($hash->{STATE}, 'authenticating', 'ReadyFn reaches the normal auth phase');

$hash = fresh_device();
$hash->{STATE} = 'disconnected';
$hash->{NEXT_OPEN} = $DevIo::NOW - 1;
$DevIo::READYFNLIST{$hash->{NAME}} = $hash;
$DevIo::READYFNLIST{$hash->{NAME} . '.' . $hash->{DeviceName}} = $hash;
$DevIo::OPEN_ERROR = 'synthetic immediate reconnect failure';
main::Wattpilot_Ready($hash);
is($hash->{STATE}, 'connectionFailed',
    'ReadyFn synchronous reopen error reports connection failed');
is(timer_count('connect'), 1,
    'ReadyFn synchronous reopen error creates one module recovery owner');
ok(!exists $DevIo::READYFNLIST{$hash->{NAME}},
    'ReadyFn synchronous reopen error does not retain stale readyfnlist owner');
ok(defined($hash->{NEXT_OPEN}) && $hash->{NEXT_OPEN} <= $DevIo::NOW,
    'ReadyFn synchronous reopen error ignores the expired NEXT_OPEN as recovery owner');

$hash = fresh_device();
$DevIo::OPEN_ERROR = 'synthetic immediate connect failure';
main::Wattpilot_Connect($hash);
is($hash->{STATE}, 'connectionFailed', 'immediate DevIo open error reports connection failed');
is(timer_count('connect'), 1, 'immediate DevIo open error schedules recovery through guarded connect');
ok(!defined $hash->{NEXT_OPEN}, 'immediate DevIo open error has no DevIo recovery owner');
ok(!exists $DevIo::READYFNLIST{$hash->{NAME}},
    'immediate DevIo open error leaves no readyfnlist owner');

$hash = fresh_device();
$DevIo::OPEN_MODE = 'async_error';
main::Wattpilot_Connect($hash);
is($hash->{STATE}, 'connectionFailed', 'async DevIo open error reports connection failed');
is(timer_count('connect'), 0, 'async DevIo open error keeps recovery owned by DevIo');
ok(defined $hash->{NEXT_OPEN}, 'async DevIo open error sets NEXT_OPEN');
ok($DevIo::READYFNLIST{$hash->{NAME}} == $hash,
    'async DevIo open error registers readyfnlist owner');

$hash = fresh_device();
$DevIo::OPEN_MODE = 'timeout';
main::Wattpilot_Connect($hash);
is($hash->{STATE}, 'connectionFailed', 'DevIo open timeout reports connection failed');
is(timer_count('connect'), 0, 'DevIo open timeout keeps recovery owned by DevIo');
ok(defined $hash->{NEXT_OPEN}, 'DevIo open timeout sets NEXT_OPEN');
ok($DevIo::READYFNLIST{$hash->{NAME}} == $hash,
    'DevIo open timeout registers readyfnlist owner');

$hash = fresh_device();
$hash->{TEST_OPEN} = 1;
$hash->{TCPDev} = 1;
$hash->{FD} = 99;
$hash->{helper}{pendingRequests}{41} = { key => 'amp', sentAt => $DevIo::NOW };
main::Wattpilot_ScheduleRequestTimeout($hash);
$hash->{READINGS}{lastCommandStatus}{VAL} = 'pending';
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
ok($DevIo::READYFNLIST{$hash->{NAME}} == $hash, 'ordinary DevIo disconnect registers readyfnlist');
ok($hash->{DevIoJustClosed}, 'ordinary DevIo disconnect marks the close for ReadyFn');
is(timer_count('connect'), 0, 'ordinary transport disconnect creates no module reconnect timer');
is($hash->{STATE}, 'disconnected', 'ordinary transport disconnect publishes truthful state');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
    'ordinary transport disconnect finalizes a pending command');
is($hash->{READINGS}{lastCommandError}{VAL}, 'connection lost',
    'ordinary transport disconnect exposes the redacted reason');
my $open_count = scalar @DevIo::OPENS;
main::Wattpilot_Ready($hash);
is(scalar @DevIo::OPENS, $open_count + 1,
    'first ReadyFn callback reaches DevIo OpenDev');
ok(!DevIo::DevIo_IsOpen($hash),
    'DevIoJustClosed consumes the first ReadyFn open without opening');
is($hash->{STATE}, 'disconnected',
    'consumed ReadyFn open does not enter authentication');
main::Wattpilot_Ready($hash);
ok(DevIo::DevIo_IsOpen($hash), 'later ReadyFn callback opens normally');
is($hash->{STATE}, 'authenticating', 'later ReadyFn callback enters authentication');

$hash = fresh_device();
$hash->{TEST_OPEN} = 1;
$hash->{TCPDev} = 1;
$hash->{FD} = 99;
$hash->{helper}{pendingRequests}{42} = { key => 'amp', sentAt => $DevIo::NOW };
main::Wattpilot_ScheduleRequestTimeout($hash);
push @DevIo::READS, { kind => 'websocket_close' };
main::Wattpilot_Read($hash);
is($hash->{STATE}, 'disconnected', 'WebSocket Close publishes disconnected');
is(timer_count('connect'), 1, 'WebSocket Close installs exactly one module reconnect owner');
ok(!exists $DevIo::READYFNLIST{$hash->{NAME}},
    'WebSocket Close does not invent a DevIo ReadyFn owner');
is($hash->{READINGS}{lastCommandError}{VAL}, 'connection lost',
    'WebSocket Close finalizes pending commands consistently');
push @DevIo::READS, { kind => 'websocket_close' };
main::Wattpilot_Read($hash);
is(timer_count('connect'), 1, 'repeated close callbacks cannot duplicate reconnect timers');
my $stale_connect = $hash->{helper}{timers}{connect};
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '1');
main::Wattpilot_Connect($stale_connect);
is(scalar @DevIo::OPENS, 0, 'stale WebSocket-close reconnect is suppressed after disable');

$hash = fresh_device();
main::Wattpilot_ScheduleConnect($hash, 10);
main::Wattpilot_ScheduleTimer($hash, 'idle_refresh', 10, 'Wattpilot_IdleRefreshTimeout');
main::Wattpilot_Shutdown($hash);
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'ShutdownFn removes tracked timers');
is(scalar @DevIo::CLOSES, 1, 'ShutdownFn closes DevIo synchronously');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
main::Wattpilot_Set($hash, $hash->{NAME}, 'password', 'new-password');
is(scalar @DevIo::OPENS, 1, 'Password change does not start a competing open before old callback');
DevIo::complete_deferred_open(0);
is(timer_count('connect'), 1, 'Password change schedules reconnect after stale open callback');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
main::Wattpilot_Set($hash, $hash->{NAME}, 'password', 'new-password');
DevIo::complete_deferred_open(0, 'synthetic async failure');
is(timer_count('connect'), 1, 'Password change schedules reconnect after stale open error');
ok(!defined $hash->{NEXT_OPEN}, 'stale open error cleanup removes DevIo recovery owner');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '1');
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '0');
is(scalar @DevIo::OPENS, 1, 'disable/enable does not start a competing open before old callback');
DevIo::complete_deferred_open(0);
is(timer_count('connect'), 1, 'disable/enable reconnect is deferred until stale open completes');

done_testing;
