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
        NAME => 'architectureWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000035',
        DeviceName => 'ws:192.0.2.35:80/ws',
        STATE => 'disconnected',
        TEST_OPEN => 1,
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

sub stable_key {
    my ($hash, $suffix) = @_;
    return 'Wattpilot_' . $hash->{FUUID} . '_' . $suffix;
}

my $interface = main::Wattpilot_InterfaceSnapshot();
is_deeply(
    $interface->{commands},
    {
        password => 'password',
        force_state => 'forceState',
        charging_current => 'chargingCurrent',
        charging_mode => 'chargingMode',
        next_trip_time => 'nextTripTime',
    },
    '2.0 public Set command names have one central definition');
is(scalar(keys %{$interface->{readings}}), 23,
    'central reading definition contains all 23 public readings');
is_deeply(
    $interface->{readings},
    {
        state => 'state',
        firmware_version => 'firmwareVersion',
        auth_hash_mode => 'authHashMode',
        car_state => 'carState',
        force_state => 'forceState',
        charging_current => 'chargingCurrent',
        charging_mode => 'chargingMode',
        next_trip_time => 'nextTripTime',
        energy_total => 'energyTotal',
        energy_since_plug_in => 'energySincePlugIn',
        voltage_l1 => 'voltageL1',
        voltage_l2 => 'voltageL2',
        voltage_l3 => 'voltageL3',
        current_l1 => 'currentL1',
        current_l2 => 'currentL2',
        current_l3 => 'currentL3',
        power_l1 => 'powerL1',
        power_l2 => 'powerL2',
        power_l3 => 'powerL3',
        power => 'power',
        last_command_request_id => 'lastCommandRequestId',
        last_command_status => 'lastCommandStatus',
        last_command_error => 'lastCommandError',
    },
    'all 23 public reading names match the 2.0 contract');
is($interface->{readings}{car_state}, 'carState',
    'central reading definition exposes the 2.0 car-state name');
is_deeply($interface->{carStates},
    { 0 => 'unknown', 1 => 'idle', 2 => 'charging', 3 => 'waitingForCar', 4 => 'complete', 5 => 'error' },
    'central car-state labels expose the 2.0 contract');
is_deeply($interface->{forceStates},
    { 0 => 'neutral', 1 => 'off', 2 => 'on' },
    'central force-state labels expose the 2.0 contract');
is_deeply($interface->{chargingModes},
    { 3 => 'default', 4 => 'eco', 5 => 'nextTrip' },
    'central charging-mode labels expose the 2.0 contract');
is($interface->{lifecycle}{credential_error}, 'credentialError',
    'central lifecycle definition exposes the 2.0 credential error value');
is_deeply(
    $interface->{lifecycle},
    {
        disabled => 'disabled',
        credential_error => 'credentialError',
        password_missing => 'passwordMissing',
        disconnected => 'disconnected',
        connecting => 'connecting',
        connection_failed => 'connectionFailed',
        authenticating => 'authenticating',
        initializing => 'initializing',
        connected => 'connected',
        auth_failed => 'authFailed',
        auth_timeout => 'authTimeout',
        initialization_timeout => 'initializationTimeout',
        auth_sequence_invalid => 'authSequenceInvalid',
        auth_config_missing => 'authConfigMissing',
        auth_challenge_invalid => 'authChallengeInvalid',
        auth_hash_unsupported => 'authHashUnsupported',
        auth_hash_failed => 'authHashFailed',
        auth_hash_store_failed => 'authHashStoreFailed',
        auth_nonce_failed => 'authNonceFailed',
    },
    'all lifecycle values match the 2.0 lowerCamelCase contract');

my $normalizer_hash = fresh_device();
my $original_status = {
    amp => 'invalid',
    car => 2,
    customField => { preserved => 1 },
};
my $normalized_status = main::Wattpilot_NormalizeStatus(
    $normalizer_hash, $original_status);
ok(exists $original_status->{amp},
    'status normalization does not mutate the caller input');
ok(!exists $normalized_status->{amp},
    'status normalization removes an invalid known field from its copy');
is($normalized_status->{car}, 2,
    'status normalization preserves a valid known field');
is_deeply($normalized_status->{customField}, { preserved => 1 },
    'status normalization preserves unknown fields');

my $hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, {
    car => 2,
    frc => 0,
    ftt => 7 * 3600 + 30 * 60,
    amp => 16,
    lmo => 4,
    eto => 123456,
    wh => 789,
    nrg => [230, 231, 232, 0, 1.1, 2.2, 3.3, 100, 200, 300, 0, 600],
});

my %expected_reading = (
    carState => 'charging',
    forceState => 'neutral',
    nextTripTime => '07:30',
    chargingCurrent => 16,
    chargingMode => 'eco',
    energyTotal => '123.46',
    energySincePlugIn => '789.00',
    voltageL1 => '230.00',
    voltageL2 => '231.00',
    voltageL3 => '232.00',
    currentL1 => '1.10',
    currentL2 => '2.20',
    currentL3 => '3.30',
    powerL1 => '100.00',
    powerL2 => '200.00',
    powerL3 => '300.00',
    power => '600.00',
);
for my $reading (sort keys %expected_reading) {
    is($hash->{READINGS}{$reading}{VAL}, $expected_reading{$reading},
        "2.0 reading contract is exposed for $reading");
}

$hash = fresh_device();
my $password_key = stable_key($hash, 'password');
my $hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'stored-password';
$DevIo::KEY_VALUES{$hash_key} = 'stored-hash';
is_deeply(main::Wattpilot_GetPassword($hash),
    { status => 'value', value => 'stored-password' },
    'stable password getter returns an explicit value result');
is_deeply(main::Wattpilot_GetPasswordHash($hash),
    { status => 'value', value => 'stored-hash' },
    'stable hash getter returns an explicit value result');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
is_deeply(main::Wattpilot_GetPassword($hash), { status => 'absent' },
    'missing stable password remains distinguishable from storage failure');
$DevIo::GET_KEY_ERRORS{$password_key} = 'synthetic read failure';
is(main::Wattpilot_GetPassword($hash)->{status}, 'error',
    'stable password storage failure remains explicit');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'old-password';
$DevIo::KEY_VALUES{$hash_key} = 'old-hash';
is(main::Wattpilot_StoreNewPassword($hash, 'new-password'), undef,
    'password replacement succeeds transactionally');
is($DevIo::KEY_VALUES{$password_key}, 'new-password',
    'password replacement stores the new stable password');
ok(!exists $DevIo::KEY_VALUES{$hash_key},
    'password replacement invalidates the stable derived hash');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'old-password';
$DevIo::KEY_VALUES{$hash_key} = 'old-hash';
$DevIo::SET_KEY_ERRORS{$password_key} = 'synthetic write failure';
like(main::Wattpilot_StoreNewPassword($hash, 'new-password'), qr/previous credentials restored/,
    'failed password write reports transactional restoration');
is($DevIo::KEY_VALUES{$password_key}, 'old-password',
    'failed password write preserves the old stable password');
is($DevIo::KEY_VALUES{$hash_key}, 'old-hash',
    'failed password write restores the old stable hash');

$hash = fresh_device();
$password_key = stable_key($hash, 'password');
$hash_key = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$password_key} = 'stored-password';
$DevIo::KEY_VALUES{$hash_key} = 'stored-hash';
$DevIo::SET_KEY_ERRORS{$hash_key} = 'synthetic second delete failure';
like(main::Wattpilot_DeleteStoredSecrets($hash), qr/prior values restored/,
    'second stable-key delete failure reports rollback');
is($DevIo::KEY_VALUES{$password_key}, 'stored-password',
    'delete rollback restores the first stable key');
is($DevIo::KEY_VALUES{$hash_key}, 'stored-hash',
    'delete failure leaves the second stable key intact');

done_testing;
