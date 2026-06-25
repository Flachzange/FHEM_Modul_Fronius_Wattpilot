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
        NAME => 'reconnectWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000047',
        DeviceName => 'ws:192.0.2.47:80/ws',
        SERIAL => '10000047',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => {
            authenticated => 1,
            protocol => 2,
            deviceType => 'wattpilot_flex',
        },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} =
        'synthetic-reconnect-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-reconnect-hash';
    return $hash;
}

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

sub run_now {
    DevIo::run_due_timers($DevIo::NOW);
}

my $hash = fresh_device();
$hash->{READINGS}{power}{VAL} = '1234.00';
$hash->{READINGS}{configPvSurplusStartPower}{VAL} = 1400;
$hash->{helper}{jsonBuffer} = '{"partial":';
$hash->{helper}{idleRefreshPending} = 1;
$hash->{helper}{idleRefreshAwaitingReconnectNrg} = 1;
$hash->{helper}{idleRefreshAttempted} = 1;
$hash->{helper}{pendingRequests} = {
    1 => { key => 'amp', sentAt => 1000 },
    2 => { key => 'fst', sentAt => 1001 },
};
main::Wattpilot_ScheduleRequestTimeout($hash);
main::Wattpilot_ScheduleTimer(
    $hash, 'idle_refresh', 30, 'Wattpilot_IdleRefreshTimeout');

is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'reconnect is accepted while connected and authenticated');
is(scalar @DevIo::WRITES, 0,
    'reconnect is a local lifecycle operation and sends no protocol frame');
is(scalar @DevIo::CLOSES, 1,
    'reconnect closes the current DevIo session once');
is($hash->{STATE}, 'disconnected',
    'reconnect exposes disconnected before the new attempt');
is(timer_count('connect'), 1,
    'reconnect schedules exactly one immediate connection attempt');
is(timer_count('command_timeout'), 0,
    'reconnect removes the pending-command timeout');
is(timer_count('idle_refresh'), 0,
    'reconnect removes the idle-refresh timer');
ok(!exists $hash->{helper}{pendingRequests},
    'reconnect removes all pending secured requests');
is($hash->{READINGS}{lastCommandRequestId}{VAL}, 2,
    'reconnect identifies the newest aborted secured request');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
    'reconnect terminates pending command state');
is($hash->{READINGS}{lastCommandError}{VAL}, 'reconnect requested',
    'reconnect exposes a stable terminal error');
ok(!exists $hash->{helper}{authenticated},
    'reconnect clears session authentication state');
ok(!exists $hash->{helper}{protocol},
    'reconnect clears session protocol state');
ok(!exists $hash->{helper}{jsonBuffer},
    'reconnect clears partial JSON state');
ok(!exists $hash->{helper}{idleRefreshPending}
    && !exists $hash->{helper}{idleRefreshAwaitingReconnectNrg}
    && !exists $hash->{helper}{idleRefreshAttempted},
    'reconnect clears all idle-refresh episode state');
is($hash->{READINGS}{power}{VAL}, '1234.00',
    'reconnect preserves operational power readings');
is($hash->{READINGS}{configPvSurplusStartPower}{VAL}, 1400,
    'reconnect preserves configuration readings');
is($hash->{SERIAL}, '10000047',
    'reconnect preserves the device serial');
is($hash->{DeviceName}, 'ws:192.0.2.47:80/ws',
    'reconnect preserves the endpoint configuration');

run_now();
is(scalar @DevIo::OPENS, 1,
    'the scheduled manual reconnect opens exactly once');
is($hash->{STATE}, 'authenticating',
    'successful transport reconnect enters authentication');
$hash->{helper}{authPending} = 1;
main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus', status => { amp => 16 },
}));
is($hash->{STATE}, 'connected',
    'device-supplied initial status completes the reconnect lifecycle');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 16,
    'device-supplied initial status is processed normally after reconnect');

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect', 'now'),
    'Usage: set reconnectWallbox reconnect',
    'reconnect rejects an argument');
is(scalar @DevIo::CLOSES, 0,
    'invalid reconnect syntax does not close the session');

$hash = fresh_device();
$attr{$hash->{NAME}}{disable} = 1;
$hash->{STATE} = 'disabled';
like(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), qr/disabled/,
    'reconnect refuses a disabled device');
is($hash->{STATE}, 'disabled',
    'disabled reconnect does not silently enable the device');
is(scalar @DevIo::CLOSES, 0,
    'disabled reconnect does not touch DevIo');
is(timer_count('connect'), 0,
    'disabled reconnect schedules no connection');

$hash = fresh_device();
delete $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'};
like(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), qr/password is missing/,
    'reconnect reports a missing password');
is($hash->{STATE}, 'connected',
    'missing-password preflight leaves an existing session state unchanged');
is(scalar @DevIo::CLOSES, 0,
    'missing-password reconnect preserves the existing session');
is(timer_count('connect'), 0,
    'missing-password reconnect starts no loop');

$hash = fresh_device();
$DevIo::GET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_password'} =
    'synthetic storage failure';
like(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'),
    qr/credential storage is unavailable/,
    'reconnect reports credential-storage failure');
is($hash->{STATE}, 'connected',
    'credential-storage failure preflight leaves an existing session state unchanged');
is(scalar @DevIo::CLOSES, 0,
    'credential-storage failure does not destroy the current session');

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
$hash->{STATE} = 'connectionFailed';
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'reconnect is available after connection failure');
is(timer_count('connect'), 1,
    'connection-failed reconnect schedules one immediate attempt');

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'first rapid reconnect is accepted');
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'second rapid reconnect is accepted');
is(timer_count('connect'), 1,
    'rapid reconnect commands retain exactly one connection timer');
run_now();
is(scalar @DevIo::OPENS, 1,
    'rapid reconnect commands produce one actual open');

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
$hash->{STATE} = 'disconnected';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
ok($hash->{helper}{openInFlight},
    'deferred open models an in-flight connection');
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'reconnect is accepted during an in-flight open');
is(timer_count('connect'), 0,
    'new open waits for ownership cleanup of the in-flight callback');
ok($hash->{helper}{pendingReconnectAfterOpen},
    'in-flight reconnect records one deferred reconnect owner');
DevIo::complete_deferred_open(0, undef);
is(timer_count('connect'), 1,
    'stale open callback schedules exactly one replacement attempt');
is($hash->{STATE}, 'disconnected',
    'stale DevIo success cannot leave the device falsely opened');
ok(!exists $hash->{helper}{openInFlight},
    'stale open callback releases its old ownership');
$DevIo::OPEN_MODE = 'success';
$DevIo::NOW += 1;
run_now();
is(scalar @DevIo::OPENS, 2,
    'replacement open is the only second open after the stale callback');


$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
$hash->{STATE} = 'disconnected';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
ok($hash->{helper}{openInFlight},
    'disable test starts with an in-flight open');
is(DevIo::command_attr($hash->{NAME}, 'disable', 1), undef,
    'disable succeeds while the open is in flight');
is($hash->{STATE}, 'disabled',
    'disable immediately exposes disabled');
DevIo::complete_deferred_open(0, undef);
is($hash->{STATE}, 'disabled',
    'stale DevIo success cannot overwrite disabled');
is(timer_count('connect'), 0,
    'stale disabled callback schedules no reconnect');

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
$hash->{STATE} = 'disconnected';
$DevIo::OPEN_MODE = 'deferred';
main::Wattpilot_Connect($hash);
ok($hash->{helper}{openInFlight},
    'shutdown test starts with an in-flight open');
is(main::Wattpilot_Shutdown($hash), undef,
    'shutdown succeeds while the open is in flight');
DevIo::complete_deferred_open(0, undef);
is($hash->{STATE}, 'disconnected',
    'stale DevIo success cannot overwrite shutdown state');
is(timer_count('connect'), 0,
    'stale shutdown callback schedules no reconnect');

$hash = fresh_device();
main::Wattpilot_ScheduleTimer(
    $hash, 'lifecycle_timeout', 30, 'Wattpilot_LifecycleTimeout',
    { phase => 'auth' });
$hash->{STATE} = 'authenticating';
$hash->{helper}{authPending} = 1;
is(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'), undef,
    'reconnect is accepted while authenticating');
is(timer_count('lifecycle_timeout'), 0,
    'authenticating reconnect removes the old lifecycle timeout');
is(timer_count('connect'), 1,
    'authenticating reconnect schedules one replacement connection');

for my $flag (qw(undefined deleting shuttingDown)) {
    $hash = fresh_device();
    $hash->{helper}{$flag} = 1;
    like(main::Wattpilot_Set($hash, 'reconnectWallbox', 'reconnect'),
        qr/not active/,
        "$flag device cannot schedule a manual reconnect");
    is(timer_count('connect'), 0,
        "$flag device has no reconnect timer");
}

$hash = fresh_device();
my $help = main::Wattpilot_Set($hash, 'reconnectWallbox', '?');
like($help, qr/\breconnect\b/, 'Set help exposes reconnect');

done_testing;
