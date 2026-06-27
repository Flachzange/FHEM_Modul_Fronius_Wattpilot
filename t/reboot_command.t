use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);
my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

is(prototype(\&main::Wattpilot_SendSecure), '$$$',
    'reboot keeps the established three-argument SendSecure prototype');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $DevIo::NOW = 1000;
    my $hash = {
        NAME => 'rebootWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000093',
        DeviceName => 'ws:192.0.2.93:80/ws',
        SERIAL => '10000093',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => {
            authenticated => 1,
            protocol => 4,
            deviceType => 'wattpilot_flex',
        },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} =
        'synthetic-reboot-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-reboot-hash';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer, decode_json($outer->{data}));
}

sub timer_count {
    my ($kind) = @_;
    return scalar grep {
        ref($_->[2]) eq 'HASH' && ($_->[2]{kind} // '') eq $kind
    } @DevIo::ACTIVE_TIMERS;
}

my $hash = fresh_device();
my $help = main::Wattpilot_Set($hash, $hash->{NAME}, '?');
like($help, qr/(?:^|\s)reboot:noArg(?:\s|$)/,
    'Set discovery exposes reboot as a no-argument command');

is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot', 'now'),
    'Usage: set rebootWallbox reboot',
    'reboot rejects an argument');
is(scalar @DevIo::WRITES, 0,
    'invalid reboot syntax sends no frame');

$hash = fresh_device();
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot'), undef,
    'reboot is accepted while connected and authenticated');
is(scalar @DevIo::WRITES, 1,
    'reboot sends exactly one secured frame');
my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
is($outer->{type}, 'securedMsg',
    'reboot uses the existing securedMsg wrapper');
is($inner->{type}, 'setValue',
    'reboot uses the existing setValue command payload');
is($inner->{key}, 'rst',
    'reboot writes protocol key rst');
ok(JSON::is_bool($inner->{value}) && $inner->{value},
    'reboot sends the exact JSON boolean true trigger value');
is($inner->{requestId}, 1,
    'reboot keeps ordinary request correlation');
is($outer->{requestId}, '1sm',
    'reboot secured wrapper keeps ordinary request correlation');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'pending',
    'reboot remains pending while the connection stays open without a response');
is($hash->{helper}{pendingRequests}{1}{key}, 'rst',
    'ordinary pending metadata retains the reboot protocol key');
ok(!exists $hash->{helper}{pendingRequests}{1}{disconnectExpected},
    'reboot adds no transport-specific pending flag');
is(timer_count('command_timeout'), 1,
    'reboot retains the bounded response timeout while the socket stays open');

main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true, status => {},
}));
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success',
    'a regular successful response completes reboot normally');
is($hash->{READINGS}{lastCommandError}{VAL}, 'none',
    'successful reboot response has no command error');
ok(!exists $hash->{helper}{pendingRequests},
    'successful reboot response clears pending state');

$hash = fresh_device();
main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::false,
    message => 'synthetic rejection detail',
}));
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
    'an explicit device rejection remains a failure');
is($hash->{READINGS}{lastCommandError}{VAL}, 'device rejected rst',
    'reboot rejection uses the normal concise redacted error');

$hash = fresh_device();
main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot');
$hash->{TCPDev} = 1;
$hash->{FD} = 93;
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
is($hash->{STATE}, 'disconnected',
    'ordinary EOF after reboot publishes disconnected');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success',
    'ordinary EOF after reboot is the expected terminal command outcome');
is($hash->{READINGS}{lastCommandError}{VAL}, 'none',
    'expected reboot EOF does not expose a connection-lost command error');
ok(!exists $hash->{helper}{pendingRequests},
    'expected reboot EOF clears pending state');
is(timer_count('command_timeout'), 0,
    'expected reboot EOF clears the command timeout');
ok($DevIo::READYFNLIST{$hash->{NAME}} == $hash,
    'ordinary reboot EOF retains the DevIo-owned reconnect path');
is(timer_count('connect'), 0,
    'ordinary reboot EOF creates no competing module reconnect timer');
my $open_count = scalar @DevIo::OPENS;
main::Wattpilot_Ready($hash);
is(scalar @DevIo::OPENS, $open_count + 1,
    'first ReadyFn callback reaches DevIo after reboot EOF');
main::Wattpilot_Ready($hash);
ok(DevIo::DevIo_IsOpen($hash),
    'later ReadyFn callback reopens the transport after reboot EOF');
is($hash->{STATE}, 'authenticating',
    'normal authentication restarts after reboot EOF');

$hash = fresh_device();
main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot');
$hash->{TCPDev} = 1;
$hash->{FD} = 93;
push @DevIo::READS, { kind => 'websocket_close' };
main::Wattpilot_Read($hash);
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success',
    'WebSocket Close after reboot is also an expected terminal outcome');
is($hash->{READINGS}{lastCommandError}{VAL}, 'none',
    'expected reboot Close frame has no command error');
is(timer_count('connect'), 1,
    'ownerless reboot Close frame uses the existing single module reconnect owner');
ok(!exists $DevIo::READYFNLIST{$hash->{NAME}},
    'reboot Close frame does not invent a DevIo ReadyFn owner');

$hash = fresh_device();
main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 16);
$hash->{TCPDev} = 1;
$hash->{FD} = 93;
push @DevIo::READS, undef;
main::Wattpilot_Read($hash);
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed',
    'ordinary secured commands still fail on connection loss');
is($hash->{READINGS}{lastCommandError}{VAL}, 'connection lost',
    'ordinary secured command keeps the established connection-loss error');

$hash = fresh_device();
main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot');
DevIo::run_due_timers(1031);
ok(!exists $hash->{helper}{pendingRequests},
    'reboot cannot remain pending forever when neither response nor disconnect arrives');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'timeout',
    'missing response and missing disconnect still produce the bounded timeout');
is($hash->{READINGS}{lastCommandError}{VAL}, 'response timeout',
    'reboot timeout retains the normal concise error');

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
like(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot'), qr/disconnected/,
    'reboot is rejected while disconnected');
is(scalar @DevIo::WRITES, 0,
    'disconnected reboot sends no frame');

$hash = fresh_device();
delete $hash->{helper}{authenticated};
like(main::Wattpilot_Set($hash, $hash->{NAME}, 'reboot'), qr/not authenticated/,
    'reboot is rejected while unauthenticated');
is(scalar @DevIo::WRITES, 0,
    'unauthenticated reboot sends no frame');

done_testing();
