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
        password => 'Password',
        force_state => 'Laden_starten',
        charging_current => 'Strom',
        charging_mode => 'Modus',
        next_trip_time => 'Zeit_NextTrip',
    },
    'current public Set command names have one central definition');
is(scalar(keys %{$interface->{readings}}), 23,
    'central reading definition contains all 23 public readings');
is($interface->{readings}{car_state}, 'CarState',
    'central reading definition preserves the 1.6 car-state name');
is_deeply($interface->{carStates},
    { 0 => 'Unknown', 1 => 'Idle', 2 => 'Charging', 3 => 'WaitCar', 4 => 'Complete', 5 => 'Error' },
    'central car-state labels preserve the 1.6 contract');
is_deeply($interface->{forceStates},
    { 0 => 'Neutral', 1 => 'Stop', 2 => 'Start' },
    'central force-state labels preserve the 1.6 contract');
is_deeply($interface->{chargingModes},
    { 3 => 'Default', 4 => 'Eco', 5 => 'NextTrip' },
    'central charging-mode labels preserve the 1.6 contract');
is($interface->{lifecycle}{credential_error}, 'credential error',
    'central lifecycle definition preserves the 1.6 credential error value');

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
    CarState => 'Charging',
    Laden_starten => 'Neutral',
    Zeit_NextTrip => '07:30',
    Strom => 16,
    Modus => 'Eco',
    EnergyTotal => '123.46',
    Energie_seit_Anstecken => '789.00',
    Voltage_L1 => '230.00',
    Voltage_L2 => '231.00',
    Voltage_L3 => '232.00',
    Current_L1 => '1.10',
    Current_L2 => '2.20',
    Current_L3 => '3.30',
    Power_L1 => '100.00',
    Power_L2 => '200.00',
    Power_L3 => '300.00',
    power => '600.00',
);
for my $reading (sort keys %expected_reading) {
    is($hash->{READINGS}{$reading}{VAL}, $expected_reading{$reading},
        "current 1.6 reading contract remains stable for $reading");
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
