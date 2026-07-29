use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Scalar::Util qw(looks_like_number);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

DevIo::reset_test_state();
my $hash = {
    NAME => 'timestampWallbox',
    TYPE => 'Wattpilot',
    FUUID => '00000000-0000-0000-0000-000000000113',
    DeviceName => 'ws:192.0.2.10:80/ws',
    STATE => 'connected',
    TEST_OPEN => 1,
    helper => {
        lifecycleState => 'connected',
        authenticated => 1,
    },
};
$defs{$hash->{NAME}} = $hash;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
    'synthetic-request-timestamp-signing-key';

my @warnings;
{
    no warnings 'redefine';
    local *main::gettimeofday = sub {
        return wantarray ? (1_000, 250_000) : 1_000.25;
    };
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    is(main::Wattpilot_SendSecure($hash, 'pdt', 7), undef,
        'secured command is accepted with Time::HiRes-compatible gettimeofday semantics');
}

is_deeply(\@warnings, [],
    'request tracking forces scalar timestamp context without an odd-hash warning');
is(scalar keys %{$hash->{helper}{pendingRequests}}, 1,
    'exactly one pending request is tracked');
ok(exists $hash->{helper}{pendingRequests}{1},
    'the pending request remains keyed by its request ID');
my $request = $hash->{helper}{pendingRequests}{1};
is_deeply([sort keys %$request], [qw(key sentAt value)],
    'the request metadata contains only the intended fields');
is($request->{key}, 'pdt', 'the tracked protocol key is preserved');
is($request->{value}, 7, 'the tracked protocol value is preserved');
ok(looks_like_number($request->{sentAt}), 'the tracked timestamp is numeric');
cmp_ok(abs($request->{sentAt} - 1_000.25), '<', 0.000001,
    'the tracked timestamp retains fractional-second precision as one scalar');

done_testing();
