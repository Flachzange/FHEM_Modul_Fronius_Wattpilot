use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs);
my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'testWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000008',
        DeviceName => 'ws:192.0.2.10:80/ws', STATE => 'connected',
        TEST_OPEN => 1, helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer, decode_json($outer->{data}));
}

my $hash = fresh_device();
for my $case ([0, 'neutral'], [1, 'off'], [2, 'on'], [7, 'unknown:7']) {
    main::Wattpilot_UpdateReadings($hash, { frc => $case->[0] });
    is($hash->{READINGS}{forceState}{VAL}, $case->[1], "frc=$case->[0] maps explicitly");
}

for my $case (
    ['neutral', 0],
    ['off', 1],
    ['on', 2],
) {
    $hash = fresh_device();
    is(main::Wattpilot_Set($hash, 'testWallbox', 'forceState', $case->[0]), undef,
        "forceState $case->[0] is accepted");
    my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{key}, 'frc', "forceState $case->[0] writes frc");
    is($inner->{value}, $case->[1],
        "forceState $case->[0] writes frc=$case->[1]");
    is($outer->{requestId}, '1sm', 'secured wrapper uses correlated request ID');
    is($hash->{READINGS}{lastCommandStatus}{VAL}, 'pending',
        'command is pending until response');
}

$hash = fresh_device();
main::Wattpilot_Set($hash, 'testWallbox', 'forceState', 'on');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { amp => 20, frc => 2 },
}));
is($hash->{READINGS}{chargingCurrent}{VAL}, 20,
    'successful response updates returned amp status');
is($hash->{READINGS}{forceState}{VAL}, 'on',
    'successful response uses the normal frc update path');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'success',
    'successful response completes request');
ok(!exists $hash->{helper}{pendingRequests},
    'successful response removes pending request');

for my $case (
    ['default', 3],
    ['eco', 4],
    ['nextTrip', 5],
) {
    $hash = fresh_device();
    is(main::Wattpilot_Set($hash, 'testWallbox', 'chargingMode', $case->[0]), undef,
        "chargingMode $case->[0] is accepted");
    (undef, my $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{key}, 'lmo', "chargingMode $case->[0] writes lmo");
    is($inner->{value}, $case->[1],
        "chargingMode $case->[0] writes lmo=$case->[1]");
}

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'testWallbox', 'nextTripTime', '07:30'), undef,
    'nextTripTime accepts exact two-digit HH:MM');
(undef, my $time_inner) = inner_payload($DevIo::WRITES[0]);
is($time_inner->{key}, 'ftt', 'nextTripTime writes ftt');
is($time_inner->{value}, 27000, '07:30 is converted to seconds after midnight');
for my $invalid_time ('7:30', '24:00', '07:60', '07:3') {
    $hash = fresh_device();
    like(main::Wattpilot_Set($hash, 'testWallbox', 'nextTripTime', $invalid_time),
        qr/HH:MM/, "nextTripTime rejects $invalid_time");
    is(scalar @DevIo::WRITES, 0, 'invalid nextTripTime sends no frame');
}

for my $accepted (6, 32) {
    $hash = fresh_device();
    is(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', $accepted), undef,
        "chargingCurrent boundary $accepted is accepted");
    (undef, my $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{value}, $accepted, "chargingCurrent sends exact boundary $accepted");
}
for my $rejected (5, 33, '6.5', 'abc') {
    $hash = fresh_device();
    like(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', $rejected), qr/6-32/,
        "chargingCurrent value $rejected is rejected");
    is(scalar @DevIo::WRITES, 0, 'rejected chargingCurrent value sends no frame');
}

$hash = fresh_device();
$hash->{TEST_OPEN} = 0;
like(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16), qr/disconnected/,
    'disconnected command returns actionable error');
is(scalar @DevIo::WRITES, 0, 'disconnected command sends no frame');

$hash = fresh_device();
delete $hash->{helper}{authenticated};
like(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16), qr/not authenticated/,
    'unauthenticated command returns actionable error');
is(scalar @DevIo::WRITES, 0, 'unauthenticated command sends no frame');

$hash = fresh_device();
delete $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'};
like(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16), qr/signing key is missing/,
    'missing signing key returns actionable error');
is(scalar @DevIo::WRITES, 0, 'missing signing key sends no frame');

$hash = fresh_device();
main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => '1sm', success => JSON::false,
    message => 'SYNTHETIC-SECRET-DETAIL',
}));
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'failed', 'failed response is exposed');
is($hash->{READINGS}{lastCommandError}{VAL}, 'device rejected amp', 'failed response uses concise redacted error');
unlike(join("\n", map { $_->[2] // '' } @DevIo::LOGS), qr/SYNTHETIC-SECRET-DETAIL/,
    'normal logs suppress the device error payload');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { amp => 18, frc => 0 });
main::Wattpilot_Set($hash, 'testWallbox', 'chargingMode', 'eco');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 99, success => JSON::true, status => { frc => 2 },
}));
is($hash->{READINGS}{chargingCurrent}{VAL}, 18, 'unmatched response does not reset an existing reading');
ok(exists $hash->{helper}{pendingRequests}{1}, 'unmatched response does not consume another request');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true, status => { frc => 2 },
}));
is($hash->{READINGS}{chargingCurrent}{VAL}, 18, 'missing response field leaves existing reading unchanged');
is($hash->{READINGS}{forceState}{VAL}, 'on', 'present response field updates normally');

$hash = fresh_device();
$DevIo::NOW = 1000;
main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16);
ok(scalar(grep { $_->[1] eq 'Wattpilot_RequestTimeout' } @DevIo::ACTIVE_TIMERS),
    'pending request schedules a timeout timer');
DevIo::run_due_timers(1031);
ok(!exists $hash->{helper}{pendingRequests}, 'timeout removes pending request');
is($hash->{READINGS}{lastCommandStatus}{VAL}, 'timeout', 'timeout is exposed through command status');
is($hash->{READINGS}{lastCommandError}{VAL}, 'response timeout', 'timeout exposes concise error');

$hash = fresh_device();
$hash->{helper}{pendingRequests} = {
    map { $_ => { key => 'amp', value => 16, sentAt => 1000 + $_ } } 1 .. 32
};
$DevIo::NOW = 1000;
like(main::Wattpilot_Set($hash, 'testWallbox', 'chargingCurrent', 16), qr/Too many/,
    'pending request bookkeeping is bounded');
is(scalar @DevIo::WRITES, 0, 'bounded bookkeeping rejects an additional frame');


for my $old_command (qw(Password Laden_starten Strom Modus Zeit_NextTrip)) {
    $hash = fresh_device();
    like(main::Wattpilot_Set($hash, 'testWallbox', $old_command, 'x'),
        qr/^Unknown argument /, "old command $old_command is rejected");
    is(scalar @DevIo::WRITES, 0, 'rejected old command sends no frame');
}

$hash = fresh_device();
my $help = main::Wattpilot_Set($hash, 'testWallbox', '?');
like($help, qr/password/, 'Set help exposes password');
like($help, qr/forceState:neutral,off,on/, 'Set help exposes forceState values');
like($help, qr/chargingCurrent:slider,6,1,32/, 'Set help exposes chargingCurrent range');
like($help, qr/chargingMode:default,eco,nextTrip/, 'Set help exposes chargingMode values');
like($help, qr/nextTripTime/, 'Set help exposes nextTripTime');
unlike($help, qr/Password|Laden_starten|Strom|Modus|Zeit_NextTrip/,
    'Set help exposes no old command name');

$hash = fresh_device();
is(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-password'), undef,
    'password command stores a new password');
is($hash->{STATE}, 'disconnected',
    'password command transitions directly to the truthful disconnected state');
ok(!scalar(grep { defined($_->[2]) && $_->[2] eq 'password stored' } @DevIo::READING_UPDATES),
    'password command emits no transient password-stored state');

done_testing;
