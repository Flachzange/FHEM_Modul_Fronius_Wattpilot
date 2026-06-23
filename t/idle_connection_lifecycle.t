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
    $modules{Wattpilot}{defptr} = {};
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
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
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

sub due_in {
    my ($seconds) = @_;
    $DevIo::NOW += $seconds;
    DevIo::run_due_timers($DevIo::NOW);
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
$hash->{helper}{car_state} = 1;
$hash->{READINGS}{power}{VAL} = '55.00';
main::Wattpilot_Attr('set', $hash->{NAME}, 'update_while_idle', '1');
is(timer_count('idle_refresh'), 1,
    'update_while_idle=1 starts idle window using the new AttrFn value before commit');
main::Wattpilot_Attr('set', $hash->{NAME}, 'update_while_idle', '0');
is(timer_count('idle_refresh'), 0,
    'update_while_idle=0 stops an already running idle window before commit');
ok(!exists $hash->{helper}{idleRefreshPending},
    'update_while_idle=0 clears idle refresh state');

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
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
$hash->{LAST_UPDATE} = $DevIo::NOW;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1, nrg => nrg(0) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'charging-to-idle nrg in the same message bypasses the rate limit once');
is(timer_count('idle_refresh'), 0, 'same-message nrg cancels idle refresh');

main::Wattpilot_Parse($hash, status_msg({ nrg => nrg(555) }));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'the idle bypass is not reused for a second rate-limited nrg');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
$hash->{LAST_UPDATE} = $DevIo::NOW;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
is(timer_count('idle_refresh'), 1, 'idle transition without nrg arms one refresh timer');
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
$hash->{LAST_UPDATE} = $DevIo::NOW;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
due_in(1);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus',
    status => { partial => JSON::false, car => 1, nrg => nrg(0) },
}));
is($hash->{READINGS}{power}{VAL}, '0.00',
    'first authoritative nrg after idle refresh reconnect bypasses interval=300');
ok(!exists $hash->{helper}{idleRefreshAwaitingReconnectNrg},
    'refresh reconnect nrg consumes the one-shot bypass');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{TEST_OPEN} = 1;
$hash->{LAST_UPDATE} = $DevIo::NOW;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
due_in(1);
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus',
    status => { partial => JSON::true, car => 1, amp => 6 },
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
$hash->{LAST_UPDATE} = $DevIo::NOW;
$hash->{helper}{car_state} = 2;
$hash->{READINGS}{power}{VAL} = '1388.00';
main::Wattpilot_Parse($hash, status_msg({ car => 1 }));
due_in(31);
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus',
    status => { partial => JSON::false, car => 1, amp => 16 },
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
is($hash->{STATE}, 'auth_timeout', 'authentication timeout is exposed');
is(timer_count('connect'), 1, 'first authentication timeout schedules one retry');
due_in(5);
is($hash->{STATE}, 'authenticating', 'timeout retry uses the normal open path');
due_in(30);
is($hash->{STATE}, 'auth_timeout', 'second authentication timeout remains truthful');
is(timer_count('connect'), 0, 'second authentication timeout does not loop');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
is($hash->{STATE}, 'initializing', 'authSuccess alone enters initializing');
is(timer_count('lifecycle_timeout'), 1, 'initializing has one lifecycle timeout');
due_in(30);
is($hash->{STATE}, 'initialization_timeout', 'initialization timeout is exposed');
is(timer_count('connect'), 1, 'first initialization timeout schedules one retry');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
main::Wattpilot_Parse($hash, encode_json({ type => 'authError' }));
is($hash->{STATE}, 'auth_failed', 'authError remains fail-closed');
is(timer_count('connect'), 0, 'authError schedules no automatic retry');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({ type => 'fullStatus', status => { partial => JSON::true, amp => 16 } }));
is($hash->{STATE}, 'connected', 'partial fullStatus completes initialization');
is($hash->{READINGS}{Strom}{VAL}, 16, 'partial fullStatus is still applied incrementally');
is(timer_count('lifecycle_timeout'), 0, 'initialization timeout is cancelled after status');

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
main::Wattpilot_Connect($hash);
my $old_key = $hash->{NAME} . '.' . $hash->{DeviceName};
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
DevIo::complete_deferred_open(0);
is($hash->{NAME}, 'renamedLifeWallbox', 'rename test double moved the device name');
ok(!$hash->{TEST_OPEN}, 'deferred open started before rename is closed as stale');
ok(!exists $DevIo::SELECTLIST{$old_key}, 'deferred open completing after rename cleans old-name selectlist key');
is(timer_count('connect'), 1, 'rename keeps exactly one controlled reconnect owner');

$hash = fresh_device();
main::Wattpilot_ScheduleConnect($hash, 10);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('connect'), 1, 'rename replaces a pending connect timer under the new name');
is($DevIo::ACTIVE_TIMERS[0][2]{name}, 'renamedLifeWallbox',
    'rename timer context uses the new name');

$hash = fresh_device();
main::Wattpilot_Connect($hash);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('lifecycle_timeout'), 0, 'rename cancels an auth lifecycle timeout');
is(timer_count('connect'), 1, 'rename restarts lifecycle after auth timeout cancellation');

$hash = fresh_device();
$hash->{helper}{authenticated} = 1;
$hash->{helper}{pendingRequests}{1} = { sentAt => $DevIo::NOW };
main::Wattpilot_ScheduleRequestTimeout($hash);
DevIo::command_rename('lifeWallbox', 'renamedLifeWallbox');
is(timer_count('command_timeout'), 0, 'rename cancels command timeout context');
is(timer_count('connect'), 1, 'rename restarts lifecycle after command timeout cancellation');

$hash = fresh_device();
$hash->{STATE} = 'disconnected';
main::Wattpilot_Ready($hash);
is($DevIo::OPENS[0][1], 1, 'ReadyFn uses the guarded reopen path');
is($hash->{STATE}, 'authenticating', 'ReadyFn reaches the normal auth phase');

$hash = fresh_device();
$DevIo::OPEN_ERROR = 'synthetic immediate connect failure';
main::Wattpilot_Connect($hash);
is($hash->{STATE}, 'connection failed', 'immediate DevIo open error reports connection failed');
is(timer_count('connect'), 1, 'immediate DevIo open error schedules recovery through guarded connect');

$hash = fresh_device();
$hash->{TEST_OPEN} = 1;
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
ok($DevIo::READYFNLIST{$hash->{NAME}} == $hash, 'DevIo disconnect registers readyfnlist');
ok(defined $hash->{NEXT_OPEN}, 'DevIo disconnect sets NEXT_OPEN');
is(timer_count('connect'), 0, 'transport disconnect creates no module reconnect timer');
ok(!exists $hash->{FD}, 'DevIo close removes FD state');

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
main::Wattpilot_Set($hash, $hash->{NAME}, 'Password', 'new-password');
is(scalar @DevIo::OPENS, 1, 'Password change does not start a competing open before old callback');
DevIo::complete_deferred_open(0);
is(timer_count('connect'), 1, 'Password change schedules reconnect after stale open callback');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
main::Wattpilot_Set($hash, $hash->{NAME}, 'Password', 'new-password');
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
