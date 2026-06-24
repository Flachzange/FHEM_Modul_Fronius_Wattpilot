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
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'runtimeFixWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000203',
        DeviceName => 'ws:192.0.2.203:80/ws',
        SERIAL => '20000003',
        STATE => 'disconnected',
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

sub log_text {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

my $hash = fresh_device();
$hash->{VERSION} = '43.4';
my $other = {
    NAME => 'unrelatedDevice',
    TYPE => 'dummy',
    VERSION => 'unchanged',
};
$defs{$other->{NAME}} = $other;
my $state_before = $hash->{STATE};
my %registration;
main::Wattpilot_Initialize(\%registration);
is($hash->{VERSION}, '2.0.8',
    'reload-style Initialize refreshes VERSION to the module version');
is($other->{VERSION}, 'unchanged',
    'reload-style Initialize does not alter unrelated devices');
is($hash->{STATE}, $state_before,
    'reload-style VERSION refresh leaves lifecycle state unchanged');
is(scalar @DevIo::OPENS, 0,
    'reload-style VERSION refresh opens no connection');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'reload-style VERSION refresh schedules no timer');
is(scalar @DevIo::READING_UPDATES, 0,
    'reload-style VERSION refresh emits no reading update');

$hash = fresh_device();
delete $hash->{VERSION};
is(main::Wattpilot_Define(
        $hash, 'runtimeFixWallbox Wattpilot 192.0.2.203 20000003'), undef,
    'fresh definition succeeds');
is($hash->{VERSION}, '2.0.8',
    'fresh definition exposes the module version in VERSION');

main::Wattpilot_DispatchMessage($hash, {
    type => 'hello',
    version => '43.4',
    devicetype => 'wattpilot_flex',
    protocol => 2,
});
is($hash->{VERSION}, '2.0.8',
    'device hello firmware does not overwrite module VERSION');
is($hash->{READINGS}{firmwareVersion}{VAL}, '43.4',
    'device hello firmware remains available as firmwareVersion');
is($hash->{helper}{protocol}, 2,
    'hello.protocol is stored separately in the connection helper');

main::Wattpilot_DispatchMessage($hash, {
    type => 'fullStatus',
    partial => 0,
    status => { proto => 4, car => 4 },
});
is($hash->{helper}{protocol}, 2,
    'status.proto does not overwrite the separate hello.protocol helper');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 0;
$attr{$hash->{NAME}}{interval} = 30;
main::Wattpilot_UpdateReadings($hash, {
    car => 4,
    eto => 780600,
    wh => 6730,
    nrg => [231.61, 230.81, 231.70, 0, 0, 0, 0, 0, 0, 0, 0, 0],
}, 'fullStatus');
is($hash->{READINGS}{energyTotal}{VAL}, '780.60',
    'energyTotal updates while idle nrg processing is disabled');
is($hash->{READINGS}{energySincePlugIn}{VAL}, '6730.00',
    'energySincePlugIn updates while idle nrg processing is disabled');
ok(!exists $hash->{READINGS}{voltageL1},
    'idle voltage remains suppressed when update_while_idle is disabled');
ok(!exists $hash->{READINGS}{power},
    'idle power remains suppressed when update_while_idle is disabled');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 0;
$attr{$hash->{NAME}}{interval} = 300;
$hash->{LAST_UPDATE} = time;
main::Wattpilot_UpdateReadings($hash, {
    car => 2,
    eto => 781000,
    wh => 6800,
    nrg => [232, 232, 232, 0, 1, 1, 1, 230, 230, 230, 0, 690],
}, 'deltaStatus');
is($hash->{READINGS}{energyTotal}{VAL}, '781.00',
    'energyTotal updates while interval suppresses charging nrg');
is($hash->{READINGS}{energySincePlugIn}{VAL}, '6800.00',
    'energySincePlugIn updates while interval suppresses charging nrg');
ok(!exists $hash->{READINGS}{voltageL1},
    'recent LAST_UPDATE keeps charging nrg behind the interval gate');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
$attr{$hash->{NAME}}{interval} = 30;
main::Wattpilot_UpdateReadings($hash, {
    car => 4,
    eto => 780600,
    wh => 6730,
    nrg => [231.61, 230.81, 231.70, 0, 0, 0, 0, 0, 0, 0, 0, 0],
}, 'fullStatus');
is($hash->{READINGS}{voltageL1}{VAL}, '231.61',
    'idle voltage is processed when update_while_idle is enabled');
is($hash->{READINGS}{power}{VAL}, '0.00',
    'device-supplied idle zero power is processed when enabled');

$hash = fresh_device();
for my $type (qw(clearInverters updateInverter clearSmips)) {
    DevIo::reset_test_state();
    $attr{$hash->{NAME}}{verbose} = 4;
    main::Wattpilot_DispatchMessage($hash, {
        type => $type,
        privateField => 'must-not-appear',
    });
    like(log_text(), qr/Received JSON message type=\Q$type\E/,
        "observed startup message type $type remains visible at level 4");
    unlike(log_text(), qr/Ignoring unsupported JSON message type=/,
        "observed startup message type $type produces no level-3 unsupported warning");
    unlike(log_text(), qr/must-not-appear/,
        "observed startup message payload for $type is not logged");
}

DevIo::reset_test_state();
main::Wattpilot_DispatchMessage($hash, {
    type => 'futureMessage',
    privateField => 'must-not-appear',
});
like(log_text(), qr/Ignoring unsupported JSON message type=futureMessage/,
    'safe unknown message type is named in the diagnostic');
unlike(log_text(), qr/message type=unknown/,
    'safe unknown message type is no longer collapsed to unknown');
unlike(log_text(), qr/must-not-appear/,
    'unknown message payload is not logged');

DevIo::reset_test_state();
main::Wattpilot_DispatchMessage($hash, {
    type => "bad\nTYPE",
    privateField => 'also-must-not-appear',
});
like(log_text(), qr/Ignoring unsupported JSON message type=redacted/,
    'unsafe message type token is redacted');
unlike(log_text(), qr/bad|TYPE|also-must-not-appear/,
    'unsafe type content and payload fields are not logged');

DevIo::reset_test_state();
main::Wattpilot_DispatchMessage($hash, {
    type => 'A' x 65,
});
like(log_text(), qr/Ignoring unsupported JSON message type=redacted/,
    'overlong message type token is redacted');
unlike(log_text(), qr/A{65}/,
    'overlong message type content is not logged');

done_testing;
