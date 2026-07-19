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
is(reading_value($hash, 'configLoadBalancingPriority'), 50,
    'lop publishes the observed raw priority code');
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
    status => {
        loe => JSON::false,
        lop => 70,
        map => [3, 1],
        cci => {
            label => 'Replacement source',
            connected => JSON::false,
        },
    },
});
is(reading_value($hash, 'configLoadBalancingEnabled'), 0,
    'a later boolean updates the configured switch');
is(reading_value($hash, 'configLoadBalancingPriority'), 70,
    'an unknown priority code remains visible as a raw integer');
is(reading_value($hash, 'configLoadBalancingFallbackCurrent'), 0,
    'an omitted fallback value is preserved');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L3 L1',
    'a later valid phase array preserves device order');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'a later selected source label is published');
is(reading_value($hash, 'loadBalancingSourceConnected'), 0,
    'a later selected source connection state is published');

main::Wattpilot_DispatchMessage($hash, {
    type => 'deltaStatus',
    status => {
        loe => 1,
        lop => -1,
        lof => '0',
        map => [1, 1],
        cci => {
            label => '',
            connected => 0,
        },
    },
});
is(reading_value($hash, 'configLoadBalancingEnabled'), 0,
    'non-boolean loe cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingPriority'), 70,
    'negative priority cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingFallbackCurrent'), 0,
    'numeric-string fallback cannot overwrite the last valid value');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L3 L1',
    'duplicate phases cannot overwrite the last valid assignment');
is(reading_value($hash, 'configLoadBalancingSourceLabel'), 'Replacement source',
    'empty source label cannot overwrite the last valid label');
is(reading_value($hash, 'loadBalancingSourceConnected'), 0,
    'non-boolean source state cannot overwrite the last valid state');

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
is(reading_value($hash, 'configLoadBalancingPriority'), 70,
    'null load-balancing fields preserve the last valid priority');
is(reading_value($hash, 'configLoadBalancingPhaseAssignment'), 'L3 L1',
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
