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

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'syntheticWallbox', TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000010',
        DeviceName => 'ws:192.0.2.10:80/ws', STATE => 'disconnected',
        SERIAL => '10000001', TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    return $hash;
}

sub logs {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

sub seed_auth_state {
    my ($hash) = @_;
    $hash->{helper}{authenticated} = 1;
    $hash->{helper}{authPending} = 1;
    $hash->{helper}{authHashMode} = 'pbkdf2';
    $hash->{helper}{deviceType} = 'wattpilot';
    $hash->{helper}{protocol} = 2;
    $hash->{helper}{pendingRequests}{1} = { key => 'amp', value => 16, sentAt => 1 };
}

sub auth_state_is_clear {
    my ($hash) = @_;
    return !exists($hash->{helper}{authenticated})
        && !exists($hash->{helper}{authPending})
        && !exists($hash->{helper}{authHashMode})
        && !exists($hash->{helper}{deviceType})
        && !exists($hash->{helper}{protocol})
        && !exists($hash->{helper}{jsonBuffer})
        && !exists($hash->{helper}{pendingRequests});
}

my $hash = fresh_device();
$hash->{helper}{authHashMode} = 'pbkdf2';
is(
    main::Wattpilot_DerivePasswordHash($hash, 'example-password', '10000001'),
    'M0EStldQZDSYxD81d70Y7fa1P0dHS7ph',
    'fixed PBKDF2-HMAC-SHA512 vector matches'
);
is(
    unpack('H*', main::Wattpilot_BcryptSerialRawSalt('10000001', 16)),
    '00000000000000000100000000000001',
    'serial digits use the fixed raw bcrypt salt encoding'
);
SKIP: {
    skip 'Crypt::Bcrypt is optional and unavailable in this test environment', 1
        if !defined &main::bcrypt;
    $hash->{helper}{authHashMode} = 'bcrypt';
    is(
        main::Wattpilot_DerivePasswordHash($hash, 'example-password', '10000001'),
        'w18liQdhm0/A6.DVaTEbjhenCxPaa62',
        'fixed bcrypt cost-8 vector including serial salt encoding matches'
    );
}

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-password';
$hash->{helper}{deviceType} = 'wattpilot';
$hash->{helper}{protocol} = 2;
{
    no warnings 'redefine';
    local *main::Wattpilot_SecureRandomBytes = sub { return pack('C*', 0..15) };
    main::Wattpilot_SendAuth($hash, { token1 => 'token-one', token2 => 'token-two' });
}
is(scalar @DevIo::WRITES, 1, 'legacy missing-hash challenge sends one authentication response');
my $auth = decode_json($DevIo::WRITES[0][1]);
is($auth->{token3}, '000102030405060708090a0b0c0d0e0f', 'fixed token3 is encoded as lowercase hex');
is($auth->{hash}, 'cb0e8d966f518ac5d3c488757b361fa0c5fd7cbf27753584e9f02760c9ec5696',
    'fixed token1/token2/token3 authentication response matches');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'},
    'M0EStldQZDSYxD81d70Y7fa1P0dHS7ph',
    'authentication persists the deterministic signing key');

$hash->{STATE} = 'connected';
$hash->{helper}{authenticated} = 1;
$hash->{TEST_OPEN} = 1;
@DevIo::WRITES = ();
$hash->{msg_id} = 0;
is(main::Wattpilot_SendSecure($hash, 'amp', 16), undef, 'fixed secured command is accepted');
my $expected_inner = '{"key":"amp","requestId":1,"type":"setValue","value":16}';
my $expected_hmac = 'dff32bc1c702a2a4e4ae63f991f48eb0af25bc5128b4f431c1155c07e637c119';
my $expected_outer = '{"data":"{\\"key\\":\\"amp\\",\\"requestId\\":1,\\"type\\":\\"setValue\\",\\"value\\":16}","hmac":"'
    . $expected_hmac . '","requestId":"1sm","type":"securedMsg"}';
is($DevIo::WRITES[0][1], $expected_outer, 'secured-message JSON is canonical and deterministic');
my $secured = decode_json($DevIo::WRITES[0][1]);
is($secured->{data}, $expected_inner, 'secured inner JSON matches fixed vector');
is($secured->{hmac}, $expected_hmac, 'secured-message HMAC matches fixed vector');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-password';
main::Wattpilot_Parse($hash, encode_json({
    type => 'hello', devicetype => 'wattpilot', protocol => 2, version => 'synthetic'
}));
is(main::Wattpilot_GetAuthHashMode($hash, { token1 => 'a', token2 => 'b' }), 'pbkdf2',
    'documented legacy profile still selects PBKDF2 when hash is absent');
@DevIo::WRITES = ();
main::Wattpilot_SendAuth($hash, { hash => 'future-hash', token1 => 'a', token2 => 'b' });
is(scalar @DevIo::WRITES, 0, 'explicitly unknown hash algorithm is rejected');
is($hash->{STATE}, 'authHashUnsupported', 'unknown hash reports unsupported authentication state');
ok(auth_state_is_clear($hash), 'unknown hash clears transient authentication state');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-password';
main::Wattpilot_SendAuth($hash, { token1 => 'a', token2 => 'b' });
is(scalar @DevIo::WRITES, 0, 'missing hash outside the evidenced legacy profile is rejected');
is($hash->{STATE}, 'authHashUnsupported', 'non-legacy missing hash reports unsupported state');

$hash = fresh_device();
main::Wattpilot_Parse($hash, '{"type":"authSuccess"}');
ok(!$hash->{helper}{authenticated}, 'unsolicited authentication success cannot mark the connection authenticated');
is($hash->{STATE}, 'authSequenceInvalid', 'unsolicited authentication success fails closed');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-password';
$DevIo::SET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic write failure';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'a', token2 => 'b' });
is(scalar @DevIo::WRITES, 0, 'signing-key persistence failure aborts authentication');
is($hash->{STATE}, 'authHashStoreFailed', 'signing-key persistence failure remains distinguishable');
ok(auth_state_is_clear($hash), 'persistence failure clears transient authentication state');

$hash = fresh_device();
$attr{$hash->{NAME}}{update_while_idle} = 1;
is(main::Wattpilot_Parse($hash, '17'), 1, 'scalar JSON is structurally decoded');
is(main::Wattpilot_Parse($hash, '[{"type":"deltaStatus"}]'), 1, 'array JSON is structurally decoded');
like(logs(), qr/non-object top level/, 'scalar and array top levels are rejected without dispatch');
main::Wattpilot_Parse($hash, '{}');
main::Wattpilot_Parse($hash, '{"type":[]}');
like(logs(), qr/missing or invalid type/, 'missing and invalid type are rejected');

$hash->{READINGS}{configChargingCurrent}{VAL} = 16;
main::Wattpilot_Parse($hash, '{"type":"deltaStatus"}');
main::Wattpilot_Parse($hash, '{"type":"deltaStatus","status":[]}');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 16, 'missing or invalid status leaves readings unchanged');

$hash->{READINGS}{power}{VAL} = '123.00';
for my $bad_nrg (
    [1,2,3],
    'not-an-array',
    [230,231,232,0,1,2,'not-numeric',230,462,696,0,1388],
) {
    main::Wattpilot_Parse($hash, encode_json({
        type => 'deltaStatus', status => { amp => 17, nrg => $bad_nrg }
    }));
    is($hash->{READINGS}{power}{VAL}, '123.00', 'invalid nrg leaves existing electrical readings unchanged');
}
is($hash->{READINGS}{configChargingCurrent}{VAL}, 17, 'another valid field survives invalid nrg in the same update');
main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus', status => {
        car => [], frc => {}, ftt => '12:00', amp => 'sixteen', lmo => [],
        eto => 'many', wh => {},
    }
}));
is($hash->{READINGS}{configChargingCurrent}{VAL}, 17, 'invalid known scalar values leave prior readings unchanged');

main::Wattpilot_Parse($hash,
    '{"type":"deltaStatus","status":{"amp":"16"}}');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 17,
    'numeric JSON string is not accepted as an integer status field');

$hash->{READINGS}{chargingAllowed}{VAL} = 0;
for my $invalid_boolean ('1', '"1"') {
    main::Wattpilot_Parse($hash,
        '{"type":"deltaStatus","status":{"alw":' . $invalid_boolean . '}}');
    is($hash->{READINGS}{chargingAllowed}{VAL}, 0,
        'numeric or string surrogate is not accepted as a JSON boolean');
}
main::Wattpilot_Parse($hash,
    '{"type":"deltaStatus","status":{"alw":true}}');
is($hash->{READINGS}{chargingAllowed}{VAL}, 1,
    'actual JSON boolean remains accepted');

$hash->{READINGS}{power}{VAL} = '123.00';
main::Wattpilot_Parse($hash,
    '{"type":"deltaStatus","status":{"nrg":[230,231,232,0,1,2,"3",230,462,696,0,1388]}}');
is($hash->{READINGS}{power}{VAL}, '123.00',
    'numeric JSON string inside nrg invalidates the nrg update');

$hash->{READINGS}{configNextTripTime}{VAL} = '12:34';
for my $invalid_ftt (-60, 61, 86400, 90000, '"3600"', 'null') {
    main::Wattpilot_Parse($hash,
        '{"type":"deltaStatus","status":{"ftt":' . $invalid_ftt . '}}');
    is($hash->{READINGS}{configNextTripTime}{VAL}, '12:34',
        "invalid ftt value $invalid_ftt preserves the previous clock reading");
}
main::Wattpilot_Parse($hash,
    '{"type":"deltaStatus","status":{"ftt":86340}}');
is($hash->{READINGS}{configNextTripTime}{VAL}, '23:59',
    'minute-aligned in-day ftt is rendered through the shared clock helper');

my $hello_hash = fresh_device();
main::Wattpilot_Parse($hello_hash, encode_json({
    type => 'hello', devicetype => 7, protocol => '2', version => 43.4,
}));
ok(!exists $hello_hash->{helper}{deviceType}
    && !exists $hello_hash->{helper}{protocol}
    && !exists $hello_hash->{READINGS}{deviceFirmwareVersion},
    'hello fields with wrong JSON types are ignored');

my $auth_hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_' . $auth_hash->{FUUID} . '_password'} = 'example-password';
main::Wattpilot_Parse($auth_hash,
    '{"type":"authRequired","hash":"pbkdf2","token1":1,"token2":"b"}');
is($auth_hash->{STATE}, 'authChallengeInvalid',
    'authentication tokens must be actual JSON strings');

my $response_hash = fresh_device();
$response_hash->{helper}{pendingRequests}{1} = {
    key => 'amp', value => 16, sentAt => DevIo::gettimeofday(),
};
$response_hash->{READINGS}{lastCommandStatus}{VAL} = 'pending';
main::Wattpilot_Parse($response_hash,
    '{"type":"response","requestId":1,"success":1,"status":{"amp":16}}');
ok(exists $response_hash->{helper}{pendingRequests}{1},
    'response with non-boolean success does not consume the pending request');
is($response_hash->{READINGS}{lastCommandStatus}{VAL}, 'pending',
    'response with non-boolean success does not fabricate a command result');

my $partial_hash = fresh_device();
$partial_hash->{helper}{authenticated} = 1;
$partial_hash->{STATE} = 'initializing';
$partial_hash->{READINGS}{configChargingCurrent}{VAL} = 16;
main::Wattpilot_Parse($partial_hash,
    '{"type":"fullStatus","partial":1,"status":{"amp":20}}');
is($partial_hash->{READINGS}{configChargingCurrent}{VAL}, 16,
    'fullStatus with non-boolean partial is rejected before applying status');
is($partial_hash->{STATE}, 'initializing',
    'invalid partial metadata cannot complete initialization');

my $tricky = encode_json({
    type => 'deltaStatus', status => { amp => 18 },
    extra => "text }{ with braces { }, escaped quote \" and newline\nnext",
});
is(main::Wattpilot_Parse($hash, $tricky), 1, 'braces, escapes, and newlines inside strings remain one JSON document');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 18, 'tricky JSON string does not disrupt status processing');
my $joined = encode_json({ type => 'deltaStatus', status => { amp => 19 } })
    . encode_json({ type => 'deltaStatus', status => { amp => 20 } });
is(main::Wattpilot_Parse($hash, $joined), 2, 'multiple complete concatenated JSON objects are processed');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 20, 'all concatenated objects are dispatched in order');
ok(!exists $hash->{buffer}, 'module does not duplicate DevIo WebSocket fragment buffering');
$hash->{READINGS}{configChargingCurrent}{VAL} = 20;
is(main::Wattpilot_Parse($hash,
    encode_json({ type => 'deltaStatus', status => { amp => 21 } }) . '{broken}'), 0,
    'malformed suffix rejects the complete decoded batch');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 20, 'malformed batch cannot apply a valid prefix partially');
is(main::Wattpilot_Parse($hash, '{"type":"deltaStatus"'), 0, 'incomplete decoded JSON is buffered within the limit');
ok(exists $hash->{helper}{jsonBuffer}, 'incomplete JSON uses a distinct logical-message continuation buffer');
is(main::Wattpilot_Parse($hash, ',"status":{"amp":22}}'), 1, 'later decoded payload completes buffered JSON');
is($hash->{READINGS}{configChargingCurrent}{VAL}, 22, 'completed fragmented JSON is dispatched once');
ok(!exists $hash->{helper}{jsonBuffer}, 'logical JSON continuation buffer clears after completion');
is(main::Wattpilot_Parse($hash, '{not-json}'), 0, 'malformed decoded JSON is rejected');
is(main::Wattpilot_Parse($hash, ' ' x (1024 * 1024 + 1)), 0, 'oversized decoded input is rejected');

@DevIo::LOGS = ();
is(main::Wattpilot_Parse($hash, encode_json({
    type => 'futureMessage', extra => 'SYNTHETIC-SENSITIVE-VALUE'
})), 1, 'unknown message type and extra fields are non-fatal');
like(logs(), qr/Ignoring unsupported JSON message type=futureMessage/,
    'normal unknown-message log names a bounded safe type');
unlike(logs(), qr/SYNTHETIC-SENSITIVE-VALUE/,
    'normal unknown-message log suppresses extra payload fields');

$hash = fresh_device();
seed_auth_state($hash);
push @DevIo::READS, '';
main::Wattpilot_Read($hash);
ok(!auth_state_is_clear($hash), 'empty DevIo result for an incomplete raw frame is left to DevIo buffering');

for my $case (
    [disconnect => sub { push @DevIo::READS, undef; main::Wattpilot_Read($_[0]) }],
    [disable => sub { main::Wattpilot_Attr('set', $_[0]{NAME}, 'disable', '1') }],
    [password => sub {
        $DevIo::KEY_VALUES{'Wattpilot_' . $_[0]{FUUID} . '_password'} = 'old-example';
        main::Wattpilot_Set($_[0], $_[0]{NAME}, 'password', 'new-example')
    }],
    [auth_error => sub { main::Wattpilot_Parse($_[0], '{"type":"authError"}') }],
    [undefine => sub { main::Wattpilot_Undefine($_[0], $_[0]{NAME}) }],
    [delete => sub { main::Wattpilot_Delete($_[0], $_[0]{NAME}) }],
    [reconnect => sub { $_[0]{STATE} = 'disconnected'; main::Wattpilot_Ready($_[0]) }],
) {
    $hash = fresh_device();
    seed_auth_state($hash);
    $hash->{helper}{jsonBuffer} = '{"type":"deltaStatus"'
        if $case->[0] ne 'auth_error';
    $case->[1]->($hash);
    ok(auth_state_is_clear($hash), "$case->[0] clears transient authentication and command state");
}

done_testing;
