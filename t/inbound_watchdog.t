use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
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
        NAME => 'watchdogWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000090',
        DeviceName => 'ws:192.0.2.90:80/ws',
        STATE => 'initializing',
        TEST_OPEN => 1,
        FD => 90,
        helper => {
            authenticated => 1,
            lifecycleGeneration => 1,
            deviceType => 'wattpilot_flex',
        },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} =
        'synthetic-watchdog-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-watchdog-hash';
    main::Wattpilot_InitializeConnectionDiagnostics($hash);
    return $hash;
}

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

sub timer_context {
    my ($kind) = @_;
    my ($timer) = grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
    return $timer ? $timer->[2] : undef;
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

sub log_text {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

my $hash = fresh_device();
is(reading_value($hash, 'connectionLastReconnectReason'), 'none',
    'new connection diagnostics start with no reconnect reason');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 0,
    'new connection diagnostics start with a zero automatic count');

my $legacy = fresh_device();
$legacy->{helper}{deviceType} = 'wattpilot';
$legacy->{READINGS}{deviceType}{VAL} = 'wattpilot_flex';
main::Wattpilot_MarkInitialized($legacy);
is(timer_count('inbound_watchdog'), 0,
    'current legacy hello identity overrides a stale persisted Flex reading');

my $restored_flex = fresh_device();
delete $restored_flex->{helper}{deviceType};
$restored_flex->{READINGS}{deviceType}{VAL} = 'wattpilot_flex';
main::Wattpilot_MarkInitialized($restored_flex);
is(timer_count('inbound_watchdog'), 1,
    'persisted Flex identity can restore watchdog ownership after reload');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is($hash->{STATE}, 'connected',
    'successful initialization enters connected before watchdog monitoring');
is($hash->{helper}{lastInboundJsonAt}, 1000,
    'watchdog starts with a full grace period when no prior timestamp exists');
is(timer_count('inbound_watchdog'), 1,
    'connected session owns exactly one inbound watchdog');

main::Wattpilot_MarkInitialized($hash);
is(timer_count('inbound_watchdog'), 1,
    'repeated initialization replaces rather than duplicates the watchdog');

$DevIo::NOW = 1010;
is(main::Wattpilot_ProcessJsonPayload(
        $hash, '{"type":"unsupportedButComplete"}'), 1,
    'a complete JSON document is decoded even when its type is unsupported');
is($hash->{helper}{lastInboundJsonAt}, 1010,
    'every complete decoded JSON document refreshes inbound liveness');

$DevIo::NOW = 1030;
DevIo::run_due_timers($DevIo::NOW);
is(timer_count('inbound_watchdog'), 1,
    'healthy watchdog check schedules exactly one successor');
is(scalar @DevIo::CLOSES, 0,
    'healthy watchdog check does not touch the connection');

$DevIo::NOW = 1190;
DevIo::run_due_timers($DevIo::NOW);
is($hash->{STATE}, 'disconnected',
    'silent connected session becomes disconnected at the inbound timeout');
is(timer_count('inbound_watchdog'), 0,
    'timed-out watchdog does not reschedule its old session');
is(timer_count('connect'), 1,
    'timed-out watchdog schedules exactly one reconnect');
is(scalar @DevIo::CLOSES, 1,
    'timed-out watchdog closes the stale DevIo session once');
is(reading_value($hash, 'connectionLastReconnectReason'), 'inboundTimeout',
    'watchdog recovery remains visible through its reconnect reason');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 1,
    'watchdog recovery increments the automatic reconnect count once');
main::Wattpilot_RecordReconnect($hash, 'inboundTimeout', 1);
is(reading_value($hash, 'connectionLastReconnectReason'), 'inboundTimeout',
    'a repeated automatic recovery may keep the same reason');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 2,
    'a repeated automatic recovery remains observable through the counter');
like(log_text(), qr/no inbound JSON for 180 seconds; reconnecting silent session/,
    'watchdog logs the silent-session recovery without a payload');
ok(!exists $hash->{helper}{lastInboundJsonAt},
    'session invalidation clears the old inbound timestamp');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
$DevIo::NOW = 1179;
main::Wattpilot_ProcessJsonPayload($hash, '{"type":"keepAlive"}');
$DevIo::NOW = 1180;
DevIo::run_due_timers($DevIo::NOW);
is($hash->{STATE}, 'connected',
    'a complete document immediately before the timeout keeps the session alive');
is(timer_count('inbound_watchdog'), 1,
    'fresh inbound activity retains exactly one watchdog');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 0,
    'healthy inbound activity does not increment reconnect diagnostics');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
my $original_timestamp = $hash->{helper}{lastInboundJsonAt};
$DevIo::NOW = 1010;
is(main::Wattpilot_ProcessJsonPayload($hash, '{"type":'), 0,
    'incomplete JSON is buffered rather than treated as a complete document');
is($hash->{helper}{lastInboundJsonAt}, $original_timestamp,
    'incomplete JSON does not refresh inbound liveness');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
$original_timestamp = $hash->{helper}{lastInboundJsonAt};
$DevIo::NOW = 1010;
is(main::Wattpilot_ProcessJsonPayload($hash, 'not-json'), 0,
    'invalid JSON is rejected');
is($hash->{helper}{lastInboundJsonAt}, $original_timestamp,
    'invalid JSON does not refresh inbound liveness');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
my $stale_ctx = timer_context('inbound_watchdog');
main::Wattpilot_NextLifecycleGeneration($hash);
main::Wattpilot_CancelAllTimers($hash);
$hash->{STATE} = 'connected';
main::Wattpilot_StartInboundWatchdog($hash);
my $current_ctx = timer_context('inbound_watchdog');
ok($current_ctx && $current_ctx != $stale_ctx,
    'replacement lifecycle owns a distinct watchdog context');
main::Wattpilot_InboundWatchdog($stale_ctx);
is(timer_context('inbound_watchdog'), $current_ctx,
    'stale watchdog callback cannot remove the replacement timer');
is(scalar @DevIo::CLOSES, 0,
    'stale watchdog callback cannot close the replacement session');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(DevIo::command_attr($hash->{NAME}, 'interval', 0), undef,
    'interval zero is accepted during watchdog monitoring');
is(timer_count('inbound_watchdog'), 1,
    'interval zero does not alter inbound watchdog ownership');
is(DevIo::command_attr($hash->{NAME}, 'interval', 30), undef,
    'positive interval is accepted during watchdog monitoring');
is(DevIo::command_attr($hash->{NAME}, 'update_while_idle', 0), undef,
    'idle publication setting is accepted during watchdog monitoring');
is(timer_count('inbound_watchdog'), 1,
    'publication attributes remain independent of inbound liveness');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
my $disabled_ctx = timer_context('inbound_watchdog');
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 0), undef,
    'inbound watchdog can be disabled explicitly for diagnostics');
is(timer_count('inbound_watchdog'), 0,
    'disabling the watchdog immediately removes its timer');
is($hash->{STATE}, 'connected',
    'disabling the watchdog does not alter the live connection state');
main::Wattpilot_InboundWatchdog($disabled_ctx);
is(scalar @DevIo::CLOSES, 0,
    'an obsolete callback cannot close the connection after watchdog disable');
$DevIo::NOW = 1300;
DevIo::run_due_timers($DevIo::NOW);
is(timer_count('connect'), 0,
    'a disabled watchdog does not schedule a silent-session reconnect');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 0,
    'watchdog disable does not create an automatic reconnect event');
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 1), undef,
    'inbound watchdog can be re-enabled on the live Flex session');
is($hash->{helper}{lastInboundJsonAt}, 1300,
    'explicit re-enable starts with a fresh full inactivity grace period');
is(timer_count('inbound_watchdog'), 1,
    're-enabling restores exactly one watchdog timer');
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 0), undef,
    'watchdog can be disabled again before testing attribute deletion');
$DevIo::NOW = 1400;
is(DevIo::command_delete_attr($hash->{NAME}, 'inboundWatchdog'), undef,
    'deleting the watchdog attribute restores its enabled default');
ok(!exists $attr{$hash->{NAME}}{inboundWatchdog},
    'watchdog attribute deletion removes the stored override');
is($hash->{helper}{lastInboundJsonAt}, 1400,
    'attribute deletion also grants a fresh inactivity grace period');
is(timer_count('inbound_watchdog'), 1,
    'attribute deletion re-arms exactly one watchdog');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 0), undef,
    'watchdog can be disabled before a module reload');
my $disabled_registration = {};
main::Wattpilot_Initialize($disabled_registration);
is(timer_count('inbound_watchdog'), 0,
    'module reload preserves an explicitly disabled watchdog');
like($disabled_registration->{AttrList}, qr/(?:^|\s)inboundWatchdog:0,1(?:\s|$)/,
    'module registers the watchdog diagnostic switch');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 0), undef,
    'watchdog disable is accepted before ordinary socket-loss testing');
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
is(reading_value($hash, 'connectionLastReconnectReason'), 'socketClosed',
    'watchdog disable does not suppress ordinary socket-loss recovery');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 1,
    'ordinary automatic reconnects remain counted with watchdog disabled');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reconnect'), undef,
    'manual reconnect is accepted from a watched connection');
is(reading_value($hash, 'connectionLastReconnectReason'), 'manual',
    'manual reconnect records its distinct reason');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 0,
    'manual reconnect does not increment the automatic count');
is(timer_count('inbound_watchdog'), 0,
    'manual reconnect removes the old watchdog');
ok(!exists $hash->{helper}{lastInboundJsonAt},
    'manual reconnect clears the old inbound timestamp');

$hash = fresh_device();
$hash->{STATE} = 'connected';
main::Wattpilot_MarkInitialized($hash);
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
is(reading_value($hash, 'connectionLastReconnectReason'), 'socketClosed',
    'ordinary read loss records a socket-closed recovery');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 1,
    'ordinary read loss increments automatic recovery once');
is(timer_count('inbound_watchdog'), 0,
    'ordinary read loss removes the old watchdog');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot'), undef,
    'device reboot command can enter rebooting before watchdog suspension');
is(DevIo::command_attr($hash->{NAME}, 'inboundWatchdog', 0), undef,
    'watchdog can be suspended during the reboot transition');
is(timer_count('inbound_watchdog'), 0,
    'watchdog suspension removes only the reboot-transition watchdog');
is(timer_count('command_timeout'), 1,
    'watchdog suspension preserves the bounded reboot command timeout');
$DevIo::NOW = 1031;
DevIo::run_due_timers($DevIo::NOW);
is($hash->{STATE}, 'connected',
    'reboot command timeout still restores connected with watchdog disabled');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'timeout',
    'reboot timeout result remains authoritative with watchdog disabled');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot'), undef,
    'device reboot command enters the watched transitional state');
is($hash->{STATE}, 'rebooting',
    'device reboot command publishes rebooting');
is(timer_count('inbound_watchdog'), 1,
    'rebooting keeps the existing inbound watchdog armed');
$DevIo::NOW = 1020;
my $reboot_watchdog_ctx = timer_context('inbound_watchdog');
DevIo::RemoveInternalTimer($reboot_watchdog_ctx, $reboot_watchdog_ctx->{fn});
main::Wattpilot_InboundWatchdog($reboot_watchdog_ctx);
is($hash->{STATE}, 'rebooting',
    'healthy watchdog check does not disturb the reboot transition');
is(timer_count('inbound_watchdog'), 1,
    'watchdog reschedules while rebooting');
my $registration = {};
main::Wattpilot_Initialize($registration);
is(timer_count('inbound_watchdog'), 1,
    'reload replaces rather than drops the watchdog while rebooting');
$DevIo::NOW = 1031;
DevIo::run_due_timers($DevIo::NOW);
is($hash->{STATE}, 'connected',
    'normal reboot command timeout restores connected');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'timeout',
    'normal reboot timeout remains authoritative');
is(timer_count('inbound_watchdog'), 1,
    'command timeout does not remove the session watchdog');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot');
$hash->{helper}{lastInboundJsonAt} = 800;
$DevIo::NOW = 1020;
$reboot_watchdog_ctx = timer_context('inbound_watchdog');
DevIo::RemoveInternalTimer($reboot_watchdog_ctx, $reboot_watchdog_ctx->{fn});
main::Wattpilot_InboundWatchdog($reboot_watchdog_ctx);
is($hash->{STATE}, 'disconnected',
    'already stale rebooting session is recovered by the watchdog');
is(reading_value($hash, 'connectionLastReconnectReason'), 'inboundTimeout',
    'silent reboot transition records the watchdog reason');
is(reading_value($hash, 'connectionAutomaticReconnectCount'), 1,
    'silent reboot transition increments automatic recovery once');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success',
    'watchdog connection loss retains the reboot command success contract');
is(timer_count('connect'), 1,
    'silent reboot transition schedules exactly one reconnect');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
main::Wattpilot_Undefine($hash, $hash->{NAME});
is(timer_count('inbound_watchdog'), 0,
    'undefine leaves no inbound watchdog behind');

$hash = fresh_device();
main::Wattpilot_MarkInitialized($hash);
main::Wattpilot_Shutdown($hash);
is(timer_count('inbound_watchdog'), 0,
    'shutdown leaves no inbound watchdog behind');

done_testing;
