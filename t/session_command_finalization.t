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
    $DevIo::NOW = 7000;
    my $hash = {
        NAME => 'commandLifeWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000075',
        DeviceName => 'ws:192.0.2.75:80/ws',
        STATE => 'connected',
        SERIAL => '10000075',
        TEST_OPEN => 1,
        TCPDev => 1,
        FD => 99,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub password_key {
    my ($hash) = @_;
    return 'Wattpilot_' . $hash->{FUUID} . '_password';
}

sub seed_pending {
    my ($hash) = @_;
    $hash->{helper}{pendingRequests} = {
        11 => { key => 'amp', value => 11, sentAt => $DevIo::NOW - 2 },
        12 => { key => 'amp', value => 12, sentAt => $DevIo::NOW - 1 },
    };
    main::Wattpilot_SetCommandReadings($hash, 12, 'pending', 'none');
    main::Wattpilot_ScheduleRequestTimeout($hash);
    return $hash->{helper}{timers}{command_timeout};
}

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

sub assert_finalized {
    my ($hash, $reason, $label) = @_;
    ok(!exists $hash->{helper}{pendingRequests}, "$label clears every pending request");
    is(timer_count('command_timeout'), 0, "$label cancels the command timeout");
    is($hash->{READINGS}{lastCommandRequestId}{VAL}, 12,
        "$label selects the newest pending request for public diagnostics");
    is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
        "$label publishes a terminal status");
    is($hash->{READINGS}{lastCommandError}{VAL}, $reason,
        "$label publishes the stable redacted reason");
}

my $hash = fresh_device();
seed_pending($hash);
main::Wattpilot_Attr('set', $hash->{NAME}, 'disable', '1');
assert_finalized($hash, 'device disabled', 'disable');

$hash = fresh_device();
$DevIo::KEY_VALUES{password_key($hash)} = 'old-password';
seed_pending($hash);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'password', 'new-password'), undef,
    'password replacement is accepted');
assert_finalized($hash, 'credentials changed', 'password replacement');

for my $attribute ([authHash => 'bcrypt'], [authHashCost => '10']) {
    $hash = fresh_device();
    $DevIo::KEY_VALUES{password_key($hash)} = 'password';
    seed_pending($hash);
    is(main::Wattpilot_Attr('set', $hash->{NAME}, @$attribute), undef,
        "$attribute->[0] replacement is accepted");
    assert_finalized($hash, 'credentials changed', "$attribute->[0] replacement");
}

$hash = fresh_device();
seed_pending($hash);
my $lifecycle_ctx = main::Wattpilot_ScheduleTimer(
    $hash, 'lifecycle_timeout', 30, 'Wattpilot_LifecycleTimeout',
    { phase => 'initialization' });
main::Wattpilot_LifecycleTimeout($lifecycle_ctx);
assert_finalized($hash, 'lifecycle timeout', 'lifecycle timeout');

$hash = fresh_device();
seed_pending($hash);
main::Wattpilot_AbortAuthentication($hash, 'authFailed');
assert_finalized($hash, 'authentication aborted', 'authentication abort');

$hash = fresh_device();
$DevIo::KEY_VALUES{password_key($hash)} = 'password';
seed_pending($hash);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reconnect'), undef,
    'manual reconnect is accepted');
assert_finalized($hash, 'reconnect requested', 'manual reconnect');

$hash = fresh_device();
seed_pending($hash);
main::Wattpilot_InvalidateSession($hash, undef, 'connection lost');
assert_finalized($hash, 'connection lost', 'session loss');
my $events_before_late_response = scalar @DevIo::READING_EVENTS;
main::Wattpilot_HandleResponse($hash, {
    type => 'response', requestId => 12, success => 1, status => {},
});
is(scalar @DevIo::READING_EVENTS, $events_before_late_response,
    'a late response from the obsolete session cannot alter diagnostics');
is($hash->{READINGS}{lastCommandError}{VAL}, 'connection lost',
    'late response preserves the session-loss terminal reason');

for my $lifecycle (qw(undefine shutdown)) {
    $hash = fresh_device();
    seed_pending($hash);
    my $events_before = scalar @DevIo::READING_EVENTS;
    if ($lifecycle eq 'undefine') {
        main::Wattpilot_Undefine($hash, $hash->{NAME});
    } else {
        main::Wattpilot_Shutdown($hash);
    }
    ok(!exists $hash->{helper}{pendingRequests}, "$lifecycle clears internal pending requests");
    is(timer_count('command_timeout'), 0, "$lifecycle cancels the command timeout");
    is($hash->{READINGS}{lastCommandStatus}{VAL}, 'pending',
        "$lifecycle suppresses new public command diagnostics");
    if ($lifecycle eq 'undefine') {
        is(scalar @DevIo::READING_EVENTS, $events_before,
            'undefine emits no new reading events');
    }
}

done_testing;
