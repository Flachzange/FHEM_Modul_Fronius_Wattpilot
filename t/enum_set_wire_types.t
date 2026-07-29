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
        NAME => 'enumWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000114',
        DeviceName => 'ws:192.0.2.114:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1, lifecycleState => 'connected' },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-enum-wire-key';
    return $hash;
}

sub secured_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer->{data}, decode_json($outer->{data}));
}

my @cases = (
    ['chargingMode default', [chargingMode => 'default'], 'lmo', 3, 'configChargingMode'],
    ['chargingMode eco', [chargingMode => 'eco'], 'lmo', 4, 'configChargingMode'],
    ['chargingMode nextTrip', [chargingMode => 'nextTrip'], 'lmo', 5, 'configChargingMode'],
    ['pvControlPreference preferFromGrid', [pvControlPreference => 'preferFromGrid'], 'frm', 0,
        'configPvControlPreference'],
    ['pvControlPreference default', [pvControlPreference => 'default'], 'frm', 1,
        'configPvControlPreference'],
    ['pvControlPreference preferToGrid', [pvControlPreference => 'preferToGrid'], 'frm', 2,
        'configPvControlPreference'],
    ['phaseSwitch mode auto', [phaseSwitch => mode => 'auto'], 'psm', 0,
        'configPhaseSwitchMode'],
    ['phaseSwitch mode force1', [phaseSwitch => mode => 'force1'], 'psm', 1,
        'configPhaseSwitchMode'],
    ['phaseSwitch mode force3', [phaseSwitch => mode => 'force3'], 'psm', 2,
        'configPhaseSwitchMode'],
);

for my $case (@cases) {
    my ($label, $args, $key, $expected, $reading) = @$case;
    my $hash = fresh_device();

    is(main::Wattpilot_Set($hash, $hash->{NAME}, @$args), undef,
        "$label is accepted");
    is(scalar @DevIo::WRITES, 1, "$label sends exactly one frame");

    my ($raw, $payload) = secured_payload($DevIo::WRITES[0]);
    is($payload->{key}, $key, "$label writes $key");
    is($payload->{value}, $expected, "$label retains the established numeric mapping");
    like($raw, qr/"value":\Q$expected\E(?:,|})/,
        "$label encodes the protocol value as a JSON number");
    unlike($raw, qr/"value":"\Q$expected\E"/,
        "$label never encodes the protocol value as a JSON string");
    ok(!exists $hash->{READINGS}{$reading},
        "$label does not update the confirmed configuration reading optimistically");
}

for my $case (
    ['chargingMode invalid', [chargingMode => 'invalid']],
    ['pvControlPreference invalid', [pvControlPreference => 'invalid']],
    ['phaseSwitch mode invalid', [phaseSwitch => mode => 'invalid']],
) {
    my ($label, $args) = @$case;
    my $hash = fresh_device();
    like(main::Wattpilot_Set($hash, $hash->{NAME}, @$args),
        qr/^(?:Unknown mode|Usage:)/, "$label is rejected locally");
    is(scalar @DevIo::WRITES, 0, "$label sends no secured request");
}

done_testing();
