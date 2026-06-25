use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);
my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'currentLimitWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000075',
        DeviceName => 'ws:192.0.2.75:80/ws', STATE => 'connected',
        TEST_OPEN => 1, helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-current-limit-key';
    return $hash;
}

sub sent_inner_payload {
    is(scalar @DevIo::WRITES, 1, 'exactly one secured frame was sent');
    my $outer = decode_json($DevIo::WRITES[0][1]);
    return decode_json($outer->{data});
}

sub set_confirmed_limit {
    my ($hash, $limit) = @_;
    main::Wattpilot_UpdateReadings($hash, { ama => $limit });
    is($hash->{READINGS}{configMaximumCurrentLimit}{VAL}, $limit,
        "device status publishes configMaximumCurrentLimit=$limit");
}

my $hash = fresh_device();
set_confirmed_limit($hash, 16);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 16), undef,
    'chargingCurrent accepts the effective upper boundary 16');
my $inner = sent_inner_payload();
is($inner->{key}, 'amp', 'accepted boundary writes amp');
is($inner->{value}, 16, 'accepted boundary writes amp=16');

for my $rejected (17, 32) {
    $hash = fresh_device();
    set_confirmed_limit($hash, 16);
    like(
        main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', $rejected),
        qr/<6-16>/,
        "chargingCurrent rejects $rejected above the effective 16 A limit with the accepted range");
    is(scalar @DevIo::WRITES, 0,
        "rejected chargingCurrent $rejected sends no WebSocket command");
}

$hash = fresh_device();
set_confirmed_limit($hash, 16);
my $help = main::Wattpilot_Set($hash, $hash->{NAME}, '?');
like($help, qr/(?:^|\s)chargingCurrent:slider,6,1,16(?:\s|$)/,
    'FHEMWEB Set options use the confirmed 16 A upper boundary');
unlike($help, qr/chargingCurrent:slider,6,1,32/,
    'dynamic Set options do not retain the static 32 A slider after a confirmed 16 A limit');

$hash = fresh_device();
set_confirmed_limit($hash, 32);
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 32), undef,
    'a confirmed 32 A limit preserves the established 6..32 range');
$inner = sent_inner_payload();
is($inner->{value}, 32, 'confirmed 32 A limit sends amp=32');
like(main::Wattpilot_SetOptions($hash),
    qr/(?:^|\s)chargingCurrent:slider,6,1,32(?:\s|$)/,
    'confirmed 32 A limit preserves the established slider');

$hash = fresh_device();
$hash->{READINGS}{configMaximumCurrentLimit}{VAL} = 16;
like(main::Wattpilot_SetOptions($hash),
    qr/(?:^|\s)chargingCurrent:slider,6,1,32(?:\s|$)/,
    'a persisted reading is ignored until ama was received for this device hash');
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 32), undef,
    'stale pre-status reading falls back to the compatibility maximum 32');
$inner = sent_inner_payload();
is($inner->{value}, 32, 'stale-reading fallback sends amp=32');

$hash = fresh_device();
set_confirmed_limit($hash, 16);
main::Wattpilot_ClearDefinitionSessionState($hash);
is($hash->{READINGS}{configMaximumCurrentLimit}{VAL}, 16,
    'definition-session cleanup preserves the device-confirmed public reading');
like(main::Wattpilot_SetOptions($hash),
    qr/(?:^|\s)chargingCurrent:slider,6,1,32(?:\s|$)/,
    'definition-session cleanup invalidates the old limit for Set discovery');

for my $case (
    ['missing', undef],
    ['non-integer', '16.5'],
    ['non-numeric', 'invalid'],
    ['below usable range', 5],
    ['above usable range', 33],
) {
    my ($label, $reading_value) = @$case;
    $hash = fresh_device();
    set_confirmed_limit($hash, 16);
    if (defined $reading_value) {
        $hash->{READINGS}{configMaximumCurrentLimit}{VAL} = $reading_value;
    }
    else {
        delete $hash->{READINGS}{configMaximumCurrentLimit};
    }

    like(main::Wattpilot_SetOptions($hash),
        qr/(?:^|\s)chargingCurrent:slider,6,1,32(?:\s|$)/,
        "$label maximum-current reading falls back to the 32 A slider");
    is(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 32), undef,
        "$label maximum-current reading falls back to accepting 32 A");
    $inner = sent_inner_payload();
    is($inner->{value}, 32,
        "$label maximum-current fallback sends amp=32");
}

$hash = fresh_device();
set_confirmed_limit($hash, 16);
$hash->{READINGS}{configChargingCurrent}{VAL} = 10;
is(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 16), undef,
    'accepted command is sent while a confirmed charging-current reading exists');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 10,
    'chargingCurrent setter does not update configChargingCurrent optimistically');

$hash = fresh_device();
set_confirmed_limit($hash, 16);
like(main::Wattpilot_Set($hash, $hash->{NAME}, 'chargingCurrent', 17, 'extra'),
    qr/^Usage: set currentLimitWallbox chargingCurrent <6-16>$/,
    'exact arity error also reports the dynamic accepted range');
is(scalar @DevIo::WRITES, 0,
    'dynamic exact-arity rejection sends no WebSocket command');

done_testing;
