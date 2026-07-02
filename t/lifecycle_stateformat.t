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

is($DevIo::FHEM_SOURCE_REVISION,
    '0ae38bf79d19d8d598c065bf84b3990b33063c4b',
    'stateFormat and reading-event behavior is pinned to the inspected FHEM revision');

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

sub fresh_device {
    my (%options) = @_;
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $DevIo::NOW = 1000;

    my $name = $options{name} // 'stateFormatWallbox';
    my $lifecycle = $options{lifecycle} // 'disconnected';
    my $hash = {
        NAME => $name,
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000102',
        DeviceName => 'ws:192.0.2.102:80/ws',
        SERIAL => '10000102',
        STATE => $lifecycle,
        TEST_OPEN => exists($options{open}) ? $options{open} : 1,
        helper => {
            lifecycleState => $lifecycle,
            deviceType => 'wattpilot_flex',
            protocol => 4,
        },
        READINGS => {
            state => { VAL => $lifecycle, TIME => 'restored' },
            carState => { VAL => 'complete', TIME => 'restored' },
            power => { VAL => '0.00', TIME => 'restored' },
        },
    };
    $hash->{helper}{authenticated} = 1 if $options{authenticated};
    $defs{$name} = $hash;
    $attr{$name}{stateFormat} =
        q({sprintf("%s | %s | %.2f kW",ReadingsVal($name,"state","unknown"),ReadingsVal($name,"carState","unknown"),ReadingsNum($name,"power",0)/1000)});
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} =
        'synthetic-state-format-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-state-format-hash';
    DevIo::evalStateFormat($hash);
    return $hash;
}

sub begin_authenticated_initialization {
    my ($hash) = @_;
    delete $hash->{helper}{authenticated};
    $hash->{helper}{authPending} = 1;
    main::Wattpilot_SetLifecycleState($hash, 'authenticating');
    main::Wattpilot_ScheduleTimer(
        $hash, 'lifecycle_timeout', 30,
        'Wattpilot_LifecycleTimeout', { phase => 'auth' });
    ok(main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' })),
        'authSuccess is processed');
    is(main::Wattpilot_CurrentLifecycleState($hash), 'initializing',
        'authSuccess enters the authoritative internal initializing lifecycle');
    is($hash->{READINGS}{state}{VAL}, 'initializing',
        'authSuccess publishes initializing');
    is($hash->{STATE}, 'initializing | complete | 0.00 kW',
        'stateFormat rewrites presentation STATE during initialization');
    isnt($hash->{STATE}, 'initializing',
        'negative control: the former raw STATE comparison would now fail');
    is(timer_count('lifecycle_timeout'), 1,
        'initialization timeout is armed before the first status');
}

for my $case (
    ['complete fullStatus', {
        type => 'fullStatus', partial => JSON::false,
        status => { car => 4, nrg => [230, 231, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
    }],
    ['partial fullStatus', {
        type => 'fullStatus', partial => JSON::true,
        status => { car => 4 },
    }],
    ['deltaStatus', {
        type => 'deltaStatus', status => { car => 4 },
    }],
) {
    my ($label, $message) = @$case;
    subtest "$label completes initialization despite formatted STATE" => sub {
        my $hash = fresh_device(lifecycle => 'authenticating');
        begin_authenticated_initialization($hash);
        ok(main::Wattpilot_Parse($hash, encode_json($message)),
            "$label is processed");
        is(main::Wattpilot_CurrentLifecycleState($hash), 'connected',
            "$label reaches internal connected");
        is($hash->{READINGS}{state}{VAL}, 'connected',
            "$label publishes connected");
        like($hash->{STATE}, qr/^connected \| /,
            "$label preserves the compound stateFormat display");
        is(timer_count('lifecycle_timeout'), 0,
            "$label cancels the initialization timeout");
        is(timer_count('inbound_watchdog'), 1,
            "$label arms exactly one inbound watchdog");
    };
}

subtest 'watchdog and manual reconnect use runtime lifecycle, not presentation STATE' => sub {
    my $hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    main::Wattpilot_StartInboundWatchdog($hash, 1, 1);
    is(timer_count('inbound_watchdog'), 1,
        'watchdog starts while displayed STATE is compound text');
    $DevIo::NOW = 1030;
    DevIo::run_due_timers($DevIo::NOW);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'connected',
        'healthy watchdog leaves runtime connected');
    like($hash->{STATE}, qr/^connected \| /,
        'healthy watchdog leaves formatted display intact');
    is(timer_count('inbound_watchdog'), 1,
        'healthy watchdog reschedules once');

    is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reconnect'), undef,
        'manual reconnect is admitted with stateFormat active');
    is(main::Wattpilot_CurrentLifecycleState($hash), 'disconnected',
        'manual reconnect immediately invalidates internal connectivity');
    is($hash->{READINGS}{state}{VAL}, 'disconnected',
        'manual reconnect publishes disconnected');
    like($hash->{STATE}, qr/^disconnected \| /,
        'manual reconnect keeps compound presentation formatting');
    is(timer_count('connect'), 1,
        'manual reconnect leaves one reconnect owner');
    my $event_hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    $event_hash->{helper}{pendingRequests}{1} = {
        key => 'amp', sentAt => 1000,
    };
    main::Wattpilot_ScheduleRequestTimeout($event_hash);
    my ($event_lifecycle, $event_command_result);
    $DevIo::READING_EVENT_HOOK = sub {
        my ($hook_hash, $events) = @_;
        return if !grep { $_ eq 'lastCommandStatus: failed' } @$events;
        $DevIo::READING_EVENT_HOOK = undef;
        $event_lifecycle = main::Wattpilot_CurrentLifecycleState($hook_hash);
        $event_command_result = main::Wattpilot_SendSecure($hook_hash, 'amp', 16);
    };
    is(main::Wattpilot_Set($event_hash, $event_hash->{NAME}, 'reconnect'), undef,
        'manual reconnect with a pending request is accepted');
    is($event_lifecycle, 'disconnected',
        'pending-command event already observes invalidated runtime lifecycle');
    like($event_command_result, qr/disconnected|not authenticated/,
        'reentrant command from reconnect diagnostics cannot use the old session');
};

subtest 'public reading and STATE manipulation cannot authorize runtime behavior' => sub {
    my $hash = fresh_device(lifecycle => 'disconnected', authenticated => 1);
    main::readingsSingleUpdate($hash, 'state', 'connected', 1);
    is($hash->{READINGS}{state}{VAL}, 'connected',
        'setreading-style manipulation changes the public reading');
    like($hash->{STATE}, qr/^connected \| /,
        'setreading-style manipulation changes presentation STATE');
    is(main::Wattpilot_CurrentLifecycleState($hash), 'disconnected',
        'public manipulation does not change authoritative runtime lifecycle');
    like(main::Wattpilot_SendSecure($hash, 'amp', 16), qr/not authenticated/,
        'forged connected reading cannot authorize a secured command');
    is(main::Wattpilot_StartInboundWatchdog($hash, 1, 1), undef,
        'forged connected reading cannot arm the watchdog');

    main::Wattpilot_SetLifecycleState($hash, 'connected', 0);
    main::readingsSingleUpdate($hash, 'state', 'rebooting', 1);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'connected',
        'misleading rebooting reading does not change runtime connected state');
    is(main::Wattpilot_SendSecure($hash, 'amp', 16), undef,
        'misleading rebooting reading does not block an internally connected session');
};

subtest 'runtime transition precedes reentrant reading-event commands' => sub {
    my $hash = fresh_device(lifecycle => 'initializing', authenticated => 1);
    my ($observed_state, $command_result);
    $DevIo::READING_EVENT_HOOK = sub {
        my ($event_hash, $events) = @_;
        return if !grep { $_ eq 'connected' } @$events;
        $DevIo::READING_EVENT_HOOK = undef;
        $observed_state = main::Wattpilot_CurrentLifecycleState($event_hash);
        $command_result = main::Wattpilot_SendSecure($event_hash, 'amp', 16);
    };
    main::Wattpilot_SetLifecycleState($hash, 'connected');
    is($observed_state, 'connected',
        'reentrant event handler already sees the new internal lifecycle');
    is($command_result, undef,
        'reentrant secured command is admitted after the internal transition');
    is(scalar @DevIo::WRITES, 1,
        'reentrant command sends exactly one secured frame');
};

subtest 'restored stale public state is not trusted after process recreation' => sub {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $DevIo::NOW = 2000;
    my $hash = {
        NAME => 'restoredWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000112',
        STATE => 'connected | complete | 0.00 kW',
        READINGS => {
            state => { VAL => 'connected', TIME => 'restored' },
            carState => { VAL => 'complete', TIME => 'restored' },
            power => { VAL => '0.00', TIME => 'restored' },
        },
    };
    $defs{$hash->{NAME}} = $hash;
    $attr{$hash->{NAME}}{stateFormat} =
        q({sprintf("%s | %s | %.2f kW",ReadingsVal($name,"state","unknown"),ReadingsVal($name,"carState","unknown"),ReadingsNum($name,"power",0)/1000)});
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} =
        'synthetic-restored-password';

    is(main::Wattpilot_Define(
            $hash, 'restoredWallbox Wattpilot 192.0.2.112 10000112'), undef,
        'fresh-process definition accepts restored public readings');
    is(main::Wattpilot_CurrentLifecycleState($hash), 'disconnected',
        'fresh process starts conservatively despite restored connected output');
    is($hash->{READINGS}{state}{VAL}, 'disconnected',
        'fresh process republishes actual disconnected runtime state');
    is(timer_count('connect'), 1,
        'fresh process schedules a real connection sequence');
    $DevIo::NOW = 2002;
    DevIo::run_due_timers($DevIo::NOW);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'authenticating',
        'real transport setup advances to authentication');
};

subtest 'stale lifecycle callback cannot mutate a newer session' => sub {
    my $hash = fresh_device(lifecycle => 'authenticating');
    main::Wattpilot_ScheduleTimer(
        $hash, 'lifecycle_timeout', 30,
        'Wattpilot_LifecycleTimeout', { phase => 'auth' });
    my $stale = $hash->{helper}{timers}{lifecycle_timeout};
    main::Wattpilot_InvalidateSession($hash, undef, 'session replaced');
    main::Wattpilot_SetLifecycleState($hash, 'connected', 0);
    main::Wattpilot_LifecycleTimeout($stale);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'connected',
        'stale timeout cannot replace the newer internal lifecycle');
    is($hash->{READINGS}{state}{VAL}, 'connected',
        'stale timeout cannot replace the newer public projection');
};

subtest 'timeout, socket close, disable, shutdown, and rename remain coherent with formatted STATE' => sub {
    my $timeout_hash = fresh_device(lifecycle => 'initializing', authenticated => 1);
    main::Wattpilot_ScheduleTimer(
        $timeout_hash, 'lifecycle_timeout', 30,
        'Wattpilot_LifecycleTimeout', { phase => 'initialization' });
    my $timeout_ctx = $timeout_hash->{helper}{timers}{lifecycle_timeout};
    main::Wattpilot_LifecycleTimeout($timeout_ctx);
    is(main::Wattpilot_CurrentLifecycleState($timeout_hash),
        'initializationTimeout',
        'active lifecycle timeout updates the internal lifecycle');
    is($timeout_hash->{READINGS}{state}{VAL}, 'initializationTimeout',
        'active lifecycle timeout publishes its public projection');
    like($timeout_hash->{STATE}, qr/^initializationTimeout \| /,
        'active lifecycle timeout remains visible through stateFormat');
    is(timer_count('connect'), 1,
        'active lifecycle timeout leaves one retry owner');

    my $socket_hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    push @DevIo::READS, { kind => 'websocket_close' };
    main::Wattpilot_Read($socket_hash);
    is(main::Wattpilot_CurrentLifecycleState($socket_hash), 'disconnected',
        'socket close invalidates the internal lifecycle');
    is($socket_hash->{READINGS}{state}{VAL}, 'disconnected',
        'socket close publishes disconnected');
    like($socket_hash->{STATE}, qr/^disconnected \| /,
        'socket close preserves compound presentation');
    is(timer_count('connect'), 1,
        'socket close schedules exactly one replacement connection');

    my $disable_hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    is(DevIo::command_attr($disable_hash->{NAME}, 'disable', '1'), undef,
        'disable succeeds with stateFormat active');
    is(main::Wattpilot_CurrentLifecycleState($disable_hash), 'disabled',
        'disable updates the authoritative lifecycle');
    is($disable_hash->{READINGS}{state}{VAL}, 'disabled',
        'disable publishes disabled');
    like($disable_hash->{STATE}, qr/^disabled \| /,
        'disable keeps stateFormat presentation');
    is(timer_count('connect'), 0,
        'disable owns no reconnect timer');

    my $shutdown_hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    is(main::Wattpilot_Shutdown($shutdown_hash), undef,
        'shutdown succeeds with stateFormat active');
    is(main::Wattpilot_CurrentLifecycleState($shutdown_hash), 'disconnected',
        'shutdown invalidates the authoritative lifecycle');
    like($shutdown_hash->{STATE}, qr/^disconnected \| /,
        'shutdown keeps stateFormat presentation coherent');
    is(timer_count('connect'), 0,
        'shutdown owns no reconnect timer');

    my $rename_hash = fresh_device(
        name => 'stateFormatBeforeRename',
        lifecycle => 'connected', authenticated => 1);
    is(DevIo::command_rename(
            'stateFormatBeforeRename', 'stateFormatAfterRename'), undef,
        'rename succeeds with stateFormat active');
    is($rename_hash->{NAME}, 'stateFormatAfterRename',
        'framework rename updates the live device hash first');
    is(main::Wattpilot_CurrentLifecycleState($rename_hash), 'disconnected',
        'rename invalidates old session ownership');
    like($rename_hash->{STATE}, qr/^disconnected \| /,
        'rename evaluates stateFormat under the new name');
    is(timer_count('connect'), 1,
        'rename leaves exactly one controlled reconnect');
};

subtest 'reload invalidates unverifiable ownership and reconnects with stateFormat active' => sub {
    my $hash = fresh_device(lifecycle => 'connected', authenticated => 1);
    main::Wattpilot_StartInboundWatchdog($hash, 1, 1);
    main::Wattpilot_ScheduleTimer(
        $hash, 'command_timeout', 30, 'Wattpilot_RequestTimeout');
    my $old_generation = main::Wattpilot_CurrentLifecycleGeneration($hash);
    my $old_watchdog = $hash->{helper}{timers}{inbound_watchdog};

    my $registration = {};
    main::Wattpilot_Initialize($registration);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'disconnected',
        'reload invalidates the old internal session');
    is($hash->{TEST_OPEN}, 0,
        'reload closes the unverifiable old transport');
    is(main::Wattpilot_CurrentLifecycleGeneration($hash), $old_generation + 1,
        'reload advances lifecycle generation');
    is(timer_count('inbound_watchdog'), 0,
        'reload removes the old watchdog');
    is(timer_count('command_timeout'), 0,
        'reload removes old command timers');
    is(timer_count('connect'), 1,
        'reload leaves exactly one controlled reconnect');
    like($hash->{STATE}, qr/^disconnected \| /,
        'reload preserves stateFormat presentation behavior');

    main::Wattpilot_InboundWatchdog($old_watchdog);
    is(main::Wattpilot_CurrentLifecycleState($hash), 'disconnected',
        'old pre-reload watchdog callback is harmless');
    is(timer_count('connect'), 1,
        'old callback cannot create duplicate ownership');
};

done_testing();
