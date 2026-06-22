use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
require $module;

sub load_fixture {
    my $path = File::Spec->catfile($root, 't', 'fixtures', 'legacy-protocol2-session.json');
    open my $fh, '<', $path or die "Cannot read fixture: $!";
    local $/;
    my $fixture = decode_json(<$fh>);
    close $fh;
    return $fixture;
}

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'legacyWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000027',
        DeviceName => 'ws:192.0.2.27:80/ws', STATE => 'disconnected', TEST_OPEN => 1,
        SERIAL => '10000001',
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-value';
    return $hash;
}

sub recorded_reading {
    my ($reading) = @_;
    my @matches = grep { ($_->[1] // '') eq $reading } @DevIo::READING_UPDATES;
    return @matches ? $matches[-1][2] : undef;
}

my $fixture = load_fixture();
is($fixture->{hello}{devicetype}, 'wattpilot', 'fixture identifies legacy Wattpilot');
is($fixture->{hello}{protocol}, 2, 'fixture identifies protocol 2');
ok($fixture->{hello}{secured}, 'fixture records secured legacy commands');
ok(!exists $fixture->{authRequired}{hash}, 'legacy challenge omits hash');
is(scalar @{$fixture->{fullStatus}[1]{status}{nrg}}, 12, 'legacy nrg has twelve elements');

my $hash = fresh_device();
main::Wattpilot_Parse($hash, encode_json($fixture->{hello}));
is($hash->{SERIAL}, '10000001', 'configured serial remains available for legacy PBKDF2');
is($hash->{VERSION}, '36.3', 'legacy hello accepts profile fields');
is(main::Wattpilot_GetAuthHashMode($hash, $fixture->{authRequired}), 'pbkdf2',
    'missing legacy hash selects PBKDF2');
main::Wattpilot_Parse($hash, encode_json($fixture->{authRequired}));
is(scalar @DevIo::WRITES, 1, 'legacy challenge produces one response');
my $auth = decode_json($DevIo::WRITES[0][1]);
is($auth->{type}, 'auth', 'legacy response type is auth');
like($auth->{token3}, qr/^[0-9a-f]{32}$/, 'token3 shape is preserved');
like($auth->{hash}, qr/^[0-9a-f]{64}$/, 'response hash shape is preserved');
is(recorded_reading('authHashMode'), 'pbkdf2', 'legacy authentication reports PBKDF2');
ok(defined $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'},
    'legacy authentication stores derived signing value');

$DevIo::ATTR_VALUES{'legacyWallbox|authHash'} = 'bcrypt';
is(main::Wattpilot_GetAuthHashMode($hash, $fixture->{authRequired}), 'bcrypt',
    'manual bcrypt override remains available');
$DevIo::ATTR_VALUES{'legacyWallbox|authHash'} = 'pbkdf2';
is(main::Wattpilot_GetAuthHashMode($hash, { hash => 'bcrypt' }), 'pbkdf2',
    'manual PBKDF2 override remains authoritative');
delete $DevIo::ATTR_VALUES{'legacyWallbox|authHash'};
is(main::Wattpilot_GetAuthHashMode($hash, { hash => 'bcrypt' }), 'bcrypt',
    'explicit bcrypt announcement remains supported');
is(main::Wattpilot_GetAuthHashMode($hash, { hash => 'pbkdf2' }), 'pbkdf2',
    'explicit PBKDF2 announcement remains supported');

$main::attr{legacyWallbox}{update_while_idle} = 1;
main::Wattpilot_Parse($hash, encode_json($fixture->{fullStatus}[0]));
is($hash->{READINGS}{Strom}{VAL}, 16, 'partial legacy fullStatus updates amp');
is($hash->{READINGS}{CarState}{VAL}, 'Idle', 'partial legacy fullStatus updates car');
main::Wattpilot_Parse($hash, encode_json($fixture->{fullStatus}[1]));
is($hash->{READINGS}{Strom}{VAL}, 16, 'completion keeps omitted amp unchanged');
is($hash->{READINGS}{Voltage_L1}{VAL}, '230.00', 'legacy nrg updates voltage');
is($hash->{READINGS}{Current_L3}{VAL}, '3.00', 'legacy nrg updates current');
is($hash->{READINGS}{power}{VAL}, '1388.00', 'legacy nrg updates total power');

main::Wattpilot_UpdateReadings($hash, {
    nrg => [230,231,232,0,1,2,3,230,462,696,0,1388,1,1,1,1]
});
is($hash->{READINGS}{power}{VAL}, '1388.00', 'Flex sixteen-element nrg remains compatible');

main::Wattpilot_Parse($hash, encode_json({ type => 'authSuccess' }));
$hash->{msg_id} = 0;
@DevIo::WRITES = ();
is(main::Wattpilot_SendSecure($hash, 'amp', 16), undef, 'legacy secured command is accepted');
my $outer = decode_json($DevIo::WRITES[0][1]);
is($outer->{type}, 'securedMsg', 'legacy command remains securedMsg');
is($outer->{requestId}, '1sm', 'secured request ID remains correlated');
my $inner = decode_json($outer->{data});
is_deeply(
    { map { $_ => $inner->{$_} } qw(type requestId key value) },
    { type => 'setValue', requestId => 1, key => 'amp', value => 16 },
    'legacy setValue schema remains unchanged');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true, status => { amp => 16 },
}));
is(recorded_reading('lastCommandStatus'), 'success', 'legacy response correlation succeeds');
ok(!exists $hash->{helper}{pendingRequests}, 'legacy response clears pending state');

done_testing;
