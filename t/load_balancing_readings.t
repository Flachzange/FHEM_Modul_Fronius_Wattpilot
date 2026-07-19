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
        NAME => 'loadBalancingWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000101',
        DeviceName => 'ws:192.0.2.101:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { lifecycleState => 'connected' },
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

my $fixture_path = File::Spec->catfile(
    $root, 't', 'fixtures', 'fullStatus-flex-observed.json');
open my $fixture_fh, '<:raw', $fixture_path
    or die "Cannot read $fixture_path: $!";
local $/;
my $fixture = decode_json(<$fixture_fh>);
close $fixture_fh;

my $hash = fresh_device();
ok(main::Wattpilot_DispatchMessage($hash, $fixture),
    'observed Flex fullStatus is dispatched');
is(reading_value($hash, 'configLoadBalancingEnabled'), 1,
    'loe publishes the configured load-balancing switch');
is(reading_value($hash, 'configLoadBalancingPriority'), 'medium',
    'lop maps the observed medium priority code');
is(reading_value($hash, 'configLoadBalancingFallbackCurrent'), 0,
    'lof preserves the configured zero-amp fallback value');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L1 L2 L3',
    'map publishes the selected phase assignment');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), '<PV_SYSTEM_LABEL>',
    'cci.label publishes only the selected source label');
is(reading_value($hash, 'loadBalancingSourceConnected'), 1,
    'cci.connected publishes the selected source connection state');

ok(!exists $hash->{READINGS}{configLoadBalancingSourceId},
    'the selected source identifier is not exposed');
ok(!exists $hash->{READINGS}{configLoadBalancingSourceIp},
    'the selected source private endpoint is not exposed');
my $interface = main::Wattpilot_InterfaceSnapshot();
ok(!exists $interface->{commands}{load_balancing},
    'no loadBalancing Set command is exposed without verified writes');
like(main::Wattpilot_Set($hash, $hash->{NAME}, 'loadBalancing', 'enabled', '1'),
    qr/^Unknown argument loadBalancing, choose one of /,
    'unverified load-balancing writes are rejected by Set discovery');
is(scalar @DevIo::WRITES, 0,
    'an unverified load-balancing write sends no frame');


main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => { lop => 40 },
});
is(reading_value($hash, 'configLoadBalancingPriority'), 'high',
    'lop maps the real-device-confirmed high priority code');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => { lop => 60 },
});
is(reading_value($hash, 'configLoadBalancingPriority'), 'low',
    'lop maps the real-device-confirmed low priority code');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        loe => JSON::false,
        lop => 70,
        map => [1, 0, 0],
        cci => {
            label => 'Replacement source',
            connected => JSON::false,
        },
    },
});
is(reading_value($hash, 'configLoadBalancingEnabled'), 0,
    'a later boolean updates the configured switch');
is(reading_value($hash, 'configLoadBalancingPriority'), 'unknown:70',
    'an unknown priority code remains explicit');
is(reading_value($hash, 'configLoadBalancingFallbackCurrent'), 0,
    'an omitted fallback value is preserved');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L1',
    'the confirmed L1-only slot vector maps to L1');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'a later selected source label is published');
is(reading_value($hash, 'loadBalancingSourceConnected'), 0,
    'a later selected source connection state is published');

for my $case (
    [[0, 1, 0], 'L2', 'the confirmed L2-only slot vector maps to L2'],
    [[0, 0, 1], 'L3', 'the confirmed L3-only slot vector maps to L3'],
    [[1, 2, 3], 'L1 L2 L3', 'the confirmed three-phase vector maps to all phases'],
) {
    main::Wattpilot_DispatchMessage($hash, {
        type => 'deltaStatus',
        status => { map => $case->[0] },
    });
    is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), $case->[1],
        $case->[2]);
}

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        loe => 1,
        lop => -1,
        lof => '0',
        map => [1, 2, 0],
        cci => {
            label => '',
            connected => 0,
        },
    },
});
is(reading_value($hash, 'configLoadBalancingEnabled'), 0,
    'non-boolean loe cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingPriority'), 'unknown:70',
    'negative priority cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingFallbackCurrent'), 0,
    'numeric-string fallback cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L1 L2 L3',
    'a semantically invalid two-phase vector cannot overwrite the last valid assignment');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'empty source label cannot overwrite the last valid label');
is(reading_value($hash, 'loadBalancingSourceConnected'), 0,
    'non-boolean source state cannot overwrite the last valid state');

for my $invalid_map (
    [0, 0, 0],
    [1, 1, 1],
    [1, 0],
    [1, 0, 0, 0],
    [1, 0, '0'],
) {
    main::Wattpilot_DispatchMessage($hash, {
        type => 'deltaStatus',
        status => { map => $invalid_map },
    });
    is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L1 L2 L3',
        'an unconfirmed or malformed phase vector preserves the last valid assignment');
}

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        loe => undef,
        lop => undef,
        lof => undef,
        map => undef,
        cci => undef,
    },
});
is(reading_value($hash, 'configLoadBalancingEnabled'), 0,
    'null load-balancing fields preserve the last valid switch');
is(reading_value($hash, 'configLoadBalancingPriority'), 'unknown:70',
    'null load-balancing fields preserve the last valid priority');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L1 L2 L3',
    'null load-balancing fields preserve the last valid phase assignment');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'null cci preserves the selected source label');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => { cci => [] },
});
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'wrong-shaped cci preserves the selected source label');
is(reading_value($hash, 'loadBalancingSourceConnected'), 0,
    'wrong-shaped cci preserves the selected source connection state');

done_testing;
