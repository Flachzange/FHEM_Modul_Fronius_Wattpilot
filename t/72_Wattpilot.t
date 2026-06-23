use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');

require $module;

ok(defined &main::Wattpilot_Initialize, 'module loads with test stubs');

my %registration;
main::Wattpilot_Initialize(\%registration);

is(scalar @FHEM::Meta::INIT_MOD_CALLS, 1, 'embedded META is initialized once');
is($FHEM::Meta::INIT_MOD_CALLS[0][1], \%registration, 'META initialization receives the module hash');

for my $slot (qw(DefFn UndefFn DeleteFn RenameFn SetFn GetFn AttrFn ReadFn ReadyFn)) {
    ok(ref($registration{$slot}) eq 'CODE', "$slot registers an existing callback");
}

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME       => 'testWallbox',
        TYPE       => 'Wattpilot',
        FUUID      => '00000000-0000-0000-0000-000000000007',
        DeviceName => 'ws:192.0.2.10:80/ws',
        STATE      => 'disconnected',
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

sub mark_command_ready {
    my ($hash) = @_;
    $hash->{TEST_OPEN} = 1;
    $hash->{STATE} = 'connected';
    $hash->{helper}{authenticated} = 1;
    delete $hash->{helper}{pendingRequests};
    delete $hash->{msg_id};
}

sub synthetic_device {
    my ($name, $fuuid) = @_;
    return {
        NAME => $name, TYPE => 'Wattpilot', FUUID => $fuuid,
        DeviceName => 'ws:192.0.2.10:80/ws', STATE => 'disconnected',
    };
}

sub log_text {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

sub payload_log_count {
    my ($payload) = @_;
    return scalar grep { index(($_->[2] // ''), $payload) >= 0 } @DevIo::LOGS;
}

sub pending_names {
    my ($hash, $suffix) = @_;
    my ($error, $names) = main::Wattpilot_ReadPendingLegacyNames($hash, $suffix);
    return defined($error) ? [] : $names;
}

sub credential_value {
    my ($result) = @_;
    return $result->{status} eq 'value' ? $result->{value} : undef;
}

sub own_legacy {
    my ($hash, $name, $suffix) = @_;
    $DevIo::KEY_VALUES{main::Wattpilot_LegacyOwnerKey($name, $suffix)} = $hash->{FUUID};
}

my $hash = fresh_device();
my $stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
my $stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
main::Wattpilot_Undefine($hash, $hash->{NAME});
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password', 'UndefFn preserves stored password');
is($DevIo::KEY_VALUES{$stable_hash}, 'synthetic-derived-value', 'UndefFn preserves stored password hash');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'UndefFn removes timers');
is(scalar @DevIo::CLOSES, 1, 'UndefFn closes DevIo');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::KEY_VALUES{'Wattpilot_legacyName_passwordhash'} = 'legacy-derived-value';
own_legacy($hash, 'testWallbox', 'password');
own_legacy($hash, 'legacyName', 'passwordhash');
is(main::Wattpilot_WritePendingLegacyNames($hash, 'passwordhash', ['legacyName']), undef, 'pending legacy hash metadata is stored');
is(main::Wattpilot_Delete($hash, $hash->{NAME}), undef, 'DeleteFn reports successful credential deletion');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'DeleteFn deletes stable password');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'DeleteFn deletes stable password hash');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'DeleteFn deletes current legacy password');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_legacyName_passwordhash'}, 'DeleteFn deletes known legacy hash');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_passwordhash_names'}, 'DeleteFn clears pending legacy hash metadata');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'DeleteFn removes timers');
is(scalar @DevIo::CLOSES, 1, 'DeleteFn closes DevIo');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/, 'DeleteFn returns an error for a stable-key deletion failure');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password', 'failed stable-key deletion retains the credential');

$hash = fresh_device();
my $legacy_password = 'Wattpilot_testWallbox_password';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
own_legacy($hash, 'testWallbox', 'password');
$DevIo::SET_KEY_ERRORS{$legacy_password} = 'synthetic delete failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/, 'DeleteFn returns an error for a legacy-key deletion failure');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password', 'DeleteFn restores an earlier successfully deleted stable credential');
is($DevIo::KEY_VALUES{$legacy_password}, 'legacy-password', 'failed legacy-key deletion retains the credential');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
own_legacy($hash, 'testWallbox', 'password');
$DevIo::GET_KEY_ERRORS{'Wattpilot_testWallbox_password'} = 'synthetic snapshot failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/before changes were made/, 'DeleteFn aborts on a credential snapshot read failure');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password', 'snapshot failure leaves stable credential unchanged');
is(scalar(grep { $_->[0] eq 'set' } @DevIo::KEY_OPERATIONS), 0, 'snapshot failure performs no credential writes');

$hash = fresh_device();
$legacy_password = 'Wattpilot_formerWallbox_password';
my $pending_password_key = 'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names';
$DevIo::KEY_VALUES{$legacy_password} = 'pending-owned-password';
$DevIo::KEY_VALUES{$pending_password_key} = '["formerWallbox"]';
$DevIo::GET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_password'} =
    'synthetic snapshot read failure after ownership enumeration';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/before changes were made/,
    'DeleteFn aborts after pending ownership enumeration when the snapshot fails');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_formerWallbox_password_owner'},
    'failed DeleteFn snapshot creates no owner-marker side effect');
is($DevIo::KEY_VALUES{$legacy_password}, 'pending-owned-password',
    'failed DeleteFn snapshot preserves the pending-owned legacy credential');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$legacy_password = 'Wattpilot_testWallbox_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
own_legacy($hash, 'testWallbox', 'password');
$DevIo::SET_KEY_ERROR_QUEUE{$stable_password} = [undef, 'synthetic rollback failure'];
$DevIo::SET_KEY_ERRORS{$legacy_password} = 'synthetic delete failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/rollback incomplete/, 'DeleteFn reports rollback failure explicitly');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'failed rollback is not falsely reported as restored');
is($DevIo::KEY_VALUES{$legacy_password}, 'legacy-password', 'rollback failure does not expose or alter the key whose delete failed');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
DevIo::InternalTimer(time + 30, 'Wattpilot_Connect', $hash, 0);
$hash->{TEST_OPEN} = 1;
main::Wattpilot_Undefine($hash, $hash->{NAME});
ok(!exists $modules{Wattpilot}{defptr}{$hash->{NAME}}, 'UndefFn removes defptr before the real FHEM delete callback');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'UndefFn removes the active reconnect timer before DeleteFn');
ok(!DevIo::DevIo_IsOpen($hash), 'UndefFn closes the connection before DeleteFn');
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/, 'DeleteFn reports failure after UndefFn');
is($modules{Wattpilot}{defptr}{$hash->{NAME}}, $hash, 'failed DeleteFn restores defptr for the retained device');
is($hash->{STATE}, 'disconnected', 'failed DeleteFn restores an honest disconnected state');
is(scalar @DevIo::ACTIVE_TIMERS, 1, 'failed DeleteFn restores exactly one reconnect timer when a password exists');
ok(!DevIo::DevIo_IsOpen($hash), 'failed DeleteFn does not create a duplicate connection');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
$DevIo::ATTR_VALUES{'testWallbox|disable'} = 1;
main::Wattpilot_Undefine($hash, $hash->{NAME});
main::Wattpilot_Delete($hash, $hash->{NAME});
is($hash->{STATE}, 'disabled', 'failed DeleteFn restores disabled state for a disabled retained device');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'failed DeleteFn schedules no reconnect while disabled');

$hash = fresh_device();
$pending_password_key = 'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names';
$DevIo::KEY_VALUES{$pending_password_key} = '[]';
$DevIo::SET_KEY_ERRORS{$pending_password_key} = 'synthetic metadata delete failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
main::Wattpilot_Delete($hash, $hash->{NAME});
is($hash->{STATE}, 'password missing', 'failed DeleteFn reports missing password honestly');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'failed DeleteFn schedules no reconnect without a password');

$hash = fresh_device();
$legacy_password = 'Wattpilot_testWallbox_password';
$DevIo::KEY_VALUES{$legacy_password} = 'owned-current-password';
own_legacy($hash, 'testWallbox', 'password');
$DevIo::SET_KEY_ERRORS{$legacy_password} = 'synthetic current legacy delete failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/,
    'failed DeleteFn retains an owned current-name legacy password');
is($hash->{STATE}, 'disconnected',
    'failed DeleteFn restores from an owned current-name legacy password without claiming');
is(scalar @DevIo::ACTIVE_TIMERS, 1,
    'failed DeleteFn reconnects exactly once from an owned current-name legacy password');
is($DevIo::KEY_VALUES{$legacy_password}, 'owned-current-password',
    'failed DeleteFn preserves the owned current-name legacy password');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$pending_password_key = 'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$pending_password_key} = '["formerWallbox"]';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic stable delete failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/, 'DeleteFn fails transactionally after pending metadata was deleted');
is($DevIo::KEY_VALUES{$pending_password_key}, '["formerWallbox"]', 'DeleteFn rollback restores previously deleted pending metadata');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'} = 'legacy-derived-value';
is(DevIo::command_rename('testWallbox', 'renamedWallbox'), undef, 'CommandRename completes after invoking RenameFn');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'}, 'legacy-password', 'Rename migrates password to FUUID key');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'}, 'legacy-derived-value', 'Rename migrates password hash to FUUID key');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'Rename removes legacy password after successful migration');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'}, 'Rename removes legacy hash after successful migration');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic write failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is(main::Wattpilot_GetPassword($hash)->{status}, 'error', 'failed stable migration is reported as a recoverable credential error');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'legacy-password', 'failed migration retains legacy credential');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'failed migration does not create a partial stable credential');
delete $DevIo::SET_KEY_ERRORS{$stable_password};
is(credential_value(main::Wattpilot_GetPassword($hash)), 'legacy-password', 'password migration retries successfully after storage recovers');
is($DevIo::KEY_VALUES{$stable_password}, 'legacy-password', 'retry stores password under stable key');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'retry deletes legacy password only after stable write succeeds');

$hash = fresh_device();
my $legacy_hash = 'Wattpilot_testWallbox_passwordhash';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$legacy_hash} = 'legacy-derived-value';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic hash write failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is(main::Wattpilot_GetPasswordHash($hash)->{status}, 'error', 'failed hash migration is reported as a recoverable credential error');
delete $DevIo::SET_KEY_ERRORS{$stable_hash};
is(credential_value(main::Wattpilot_GetPasswordHash($hash)), 'legacy-derived-value', 'password-hash migration retries successfully');
is($DevIo::KEY_VALUES{$stable_hash}, 'legacy-derived-value', 'retry stores password hash under stable key');
ok(!exists $DevIo::KEY_VALUES{$legacy_hash}, 'retry removes legacy password hash after stable write');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$legacy_password = 'Wattpilot_testWallbox_password';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
$DevIo::GET_KEY_ERRORS{$legacy_password} = 'synthetic legacy read failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is_deeply(pending_names($hash, 'password'), ['testWallbox'], 'Rename read failure persists the former password name');
delete $DevIo::GET_KEY_ERRORS{$legacy_password};
is(credential_value(main::Wattpilot_GetPassword($hash)), 'legacy-password', 'later getter retries migration after legacy read recovers');
is($DevIo::KEY_VALUES{$stable_password}, 'legacy-password', 'retry after read failure creates stable password');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$legacy_password = 'Wattpilot_testWallbox_password';
$DevIo::KEY_VALUES{$stable_password} = 'stable-password';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
$DevIo::GET_KEY_ERRORS{$legacy_password} = 'synthetic cleanup read failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is(credential_value(main::Wattpilot_GetPassword($hash)), 'stable-password', 'stable value remains usable while legacy cleanup read fails');
is($DevIo::KEY_VALUES{$legacy_password}, 'legacy-password', 'cleanup read failure leaves legacy value untouched');
delete $DevIo::GET_KEY_ERRORS{$legacy_password};
is(credential_value(main::Wattpilot_GetPassword($hash)), 'stable-password', 'stable getter retries cleanup after read recovery');
ok(!exists $DevIo::KEY_VALUES{$legacy_password}, 'retry removes stale legacy value after read recovery');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$legacy_password = 'Wattpilot_testWallbox_password';
$DevIo::KEY_VALUES{$stable_password} = 'stable-password';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
$DevIo::SET_KEY_ERRORS{$legacy_password} = 'synthetic legacy cleanup failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is_deeply(pending_names($hash, 'password'), ['testWallbox'], 'failed cleanup keeps the old password name persistently pending');
is($DevIo::KEY_VALUES{$legacy_password}, 'legacy-password', 'failed cleanup retains old legacy password');
delete $DevIo::SET_KEY_ERRORS{$legacy_password};
is(main::Wattpilot_Delete($hash, $hash->{NAME}), undef, 'later Delete handles a pending legacy name');
ok(!exists $DevIo::KEY_VALUES{$legacy_password}, 'Delete removes pending legacy password after transient failure');
is_deeply(pending_names($hash, 'password'), [], 'successful Delete clears pending password metadata');

$hash = fresh_device();
$legacy_password = 'Wattpilot_testWallbox_password';
$legacy_hash = 'Wattpilot_testWallbox_passwordhash';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
$DevIo::KEY_VALUES{$legacy_hash} = 'legacy-derived-value';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic write failure';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic hash write failure';
DevIo::command_rename('testWallbox', 'renamedWallbox');
is_deeply(pending_names($hash, 'password'), ['testWallbox'], 'password pending metadata is stored separately');
is_deeply(pending_names($hash, 'passwordhash'), ['testWallbox'], 'password-hash pending metadata is stored separately');
my $replacement_hash = {
    NAME => 'renamedWallbox', TYPE => 'Wattpilot', FUUID => $hash->{FUUID},
    DeviceName => 'ws:192.0.2.10:80/ws', STATE => 'disconnected',
};
delete $DevIo::SET_KEY_ERRORS{$stable_password};
delete $DevIo::SET_KEY_ERRORS{$stable_hash};
is(credential_value(main::Wattpilot_GetPassword($replacement_hash)), 'legacy-password', 'new device hash with the same FUUID recovers pending migration after reload');
is(credential_value(main::Wattpilot_GetPasswordHash($replacement_hash)), 'legacy-derived-value', 'new device hash with the same FUUID recovers pending hash migration after restart');
is($DevIo::KEY_VALUES{$stable_password}, 'legacy-password', 'reload migration writes the stable password');
is($DevIo::KEY_VALUES{$stable_hash}, 'legacy-derived-value', 'restart migration writes the stable password hash');
ok(!exists $DevIo::KEY_VALUES{$legacy_password}, 'reload migration removes the former name-based password');
ok(!exists $DevIo::KEY_VALUES{$legacy_hash}, 'restart migration removes the former name-based password hash');
is_deeply(pending_names($replacement_hash, 'password'), [], 'reload migration clears persistent pending password metadata');
is_deeply(pending_names($replacement_hash, 'passwordhash'), [], 'restart migration clears persistent pending hash metadata');

$hash = fresh_device();
$legacy_password = 'Wattpilot_testWallbox_password';
$legacy_hash = 'Wattpilot_testWallbox_passwordhash';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$pending_password_key = 'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names';
my $pending_hash_key = 'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_passwordhash_names';
$DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
$DevIo::KEY_VALUES{$legacy_hash} = 'legacy-derived-value';
$DevIo::SET_KEY_ERRORS{$pending_password_key} = 'synthetic metadata persistence failure';
$DevIo::SET_KEY_ERRORS{$pending_hash_key} = 'synthetic hash metadata persistence failure';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic stable write failure';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic stable hash write failure';
is(DevIo::command_rename('testWallbox', 'renamedWallbox'), undef, 'CommandRename ignores RenameFn status and still completes');
is(scalar @DevIo::IGNORED_RENAME_REPLIES, 1, 'CommandRename test double records the discarded callback reply');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'pending metadata failure performs no untracked stable password migration');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'pending metadata failure performs no untracked stable hash migration');
is($DevIo::KEY_VALUES{$legacy_password}, 'legacy-password', 'pending metadata failure preserves the unowned legacy password');
is($DevIo::KEY_VALUES{$legacy_hash}, 'legacy-derived-value', 'pending metadata failure preserves the unowned legacy hash');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password_owner'}, 'pending metadata failure creates no owner without a durable FUUID locator');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash_owner'}, 'pending hash metadata failure creates no owner without a durable FUUID locator');
my $metadata_failure_restart = synthetic_device('renamedWallbox', $hash->{FUUID});
is(main::Wattpilot_GetPassword($metadata_failure_restart)->{status}, 'absent', 'new hash fails closed when no durable former-name locator exists');
my $metadata_failure_reuse = synthetic_device('testWallbox', '00000000-0000-0000-0000-000000000099');
is(main::Wattpilot_GetPassword($metadata_failure_reuse)->{status}, 'absent', 'reused old name cannot claim an unowned legacy password');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_00000000-0000-0000-0000-000000000099_password'}, 'old-name reuse creates no foreign stable password');
ok(!scalar(grep { $_->[0] eq 'get' && ($_->[1] eq $legacy_password || $_->[1] eq $legacy_hash) } @DevIo::KEY_OPERATIONS),
    'pending metadata failure never reads the unowned legacy secret values');

for my $order (qw(original-first replacement-first)) {
    $hash = fresh_device();
    my $fuuid_owner = $hash->{FUUID};
    my $fuuid_reuse = '00000000-0000-0000-0000-000000000099';
    $legacy_password = 'Wattpilot_testWallbox_password';
    $legacy_hash = 'Wattpilot_testWallbox_passwordhash';
    $stable_password = "Wattpilot_${fuuid_owner}_password";
    $stable_hash = "Wattpilot_${fuuid_owner}_passwordhash";
    my $password_owner_key = 'Wattpilot_testWallbox_password_owner';
    my $hash_owner_key = 'Wattpilot_testWallbox_passwordhash_owner';
    $DevIo::KEY_VALUES{$legacy_password} = 'legacy-password';
    $DevIo::KEY_VALUES{$legacy_hash} = 'legacy-derived-value';
    $DevIo::SET_KEY_ERRORS{$password_owner_key} = 'synthetic owner write failure';
    $DevIo::SET_KEY_ERRORS{$hash_owner_key} = 'synthetic hash owner write failure';
    DevIo::command_rename('testWallbox', 'renamedWallbox');
    is_deeply(pending_names($hash, 'password'), ['testWallbox'], "$order owner failure keeps password locator pending");
    is_deeply(pending_names($hash, 'passwordhash'), ['testWallbox'], "$order owner failure keeps hash locator pending");
    ok(!exists $DevIo::KEY_VALUES{$stable_password}, "$order owner failure creates no stable password");
    ok(!exists $DevIo::KEY_VALUES{$stable_hash}, "$order owner failure creates no stable hash");

    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $device_owner = synthetic_device('renamedWallbox', $fuuid_owner);
    my $device_reuse = synthetic_device('testWallbox', $fuuid_reuse);
    my @definitions = $order eq 'original-first'
        ? ([$device_owner, 'renamedWallbox Wattpilot 192.0.2.10'], [$device_reuse, 'testWallbox Wattpilot 192.0.2.11'])
        : ([$device_reuse, 'testWallbox Wattpilot 192.0.2.11'], [$device_owner, 'renamedWallbox Wattpilot 192.0.2.10']);
    is(main::Wattpilot_Define($_->[0], $_->[1]), undef, "$order define sequence completes") for @definitions;
    ok(!exists $DevIo::KEY_VALUES{"Wattpilot_${fuuid_reuse}_password"}, "$order reused name does not adopt password while owner persistence is failing");
    ok(!exists $DevIo::KEY_VALUES{"Wattpilot_${fuuid_reuse}_passwordhash"}, "$order reused name does not adopt hash while owner persistence is failing");
    delete $DevIo::SET_KEY_ERRORS{$password_owner_key};
    delete $DevIo::SET_KEY_ERRORS{$hash_owner_key};
    is(credential_value(main::Wattpilot_GetPassword($device_owner)), 'legacy-password', "$order original FUUID reclaims password through its pending locator");
    is(credential_value(main::Wattpilot_GetPasswordHash($device_owner)), 'legacy-derived-value', "$order original FUUID reclaims hash through its pending locator");
    is($DevIo::KEY_VALUES{$stable_password}, 'legacy-password', "$order recovery stores password under original FUUID");
    is($DevIo::KEY_VALUES{$stable_hash}, 'legacy-derived-value', "$order recovery stores hash under original FUUID");
    ok(!exists $DevIo::KEY_VALUES{"Wattpilot_${fuuid_reuse}_password"}, "$order recovery never creates a password for reused-name FUUID");
}

# Stable ownership: former names are locators only. A different FUUID owner
# must never be read, migrated, overwritten, or deleted through A's pending list.
for my $order (qw(original-first replacement-first)) {
    DevIo::reset_test_state();
    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $fuuid_a = '00000000-0000-0000-0000-0000000000a1';
    my $fuuid_b = '00000000-0000-0000-0000-0000000000b2';
    my $device_a = synthetic_device('renamedA', $fuuid_a);
    my $device_b = synthetic_device('oldName', $fuuid_b);
    $defs{renamedA} = $device_a;
    $defs{oldName} = $device_b;
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_password"} = 'password-a';
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_b}_password"} = 'password-b';
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_passwordhash"} = 'hash-a';
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_b}_passwordhash"} = 'hash-b';
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_pending_legacy_password_names"} = '["oldName"]';
    $DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_pending_legacy_passwordhash_names"} = '["oldName"]';
    $DevIo::KEY_VALUES{'Wattpilot_oldName_password'} = 'legacy-password-b';
    $DevIo::KEY_VALUES{'Wattpilot_oldName_password_owner'} = $fuuid_b;
    $DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash'} = 'legacy-hash-b';
    $DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash_owner'} = $fuuid_b;

    my @definitions = $order eq 'original-first'
        ? ([$device_a, 'renamedA Wattpilot 192.0.2.10'], [$device_b, 'oldName Wattpilot 192.0.2.11'])
        : ([$device_b, 'oldName Wattpilot 192.0.2.11'], [$device_a, 'renamedA Wattpilot 192.0.2.10']);
    is(main::Wattpilot_Define($_->[0], $_->[1]), undef, "$order command-level define/restart succeeds") for @definitions;
    is(credential_value(main::Wattpilot_GetPassword($device_a)), 'password-a', "$order A keeps its own stable password");
    is($DevIo::KEY_VALUES{'Wattpilot_oldName_password'}, 'legacy-password-b', "$order A does not clean B's owned legacy password");
    is($DevIo::KEY_VALUES{'Wattpilot_oldName_password_owner'}, $fuuid_b, "$order A does not alter B's ownership marker");
    is($DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash'}, 'legacy-hash-b', "$order A does not clean B's owned legacy hash");
}

for my $legacy_location (qw(current pending)) {
    DevIo::reset_test_state();
    %defs = ();
    $modules{Wattpilot}{defptr} = {};
    my $fuuid_a = '00000000-0000-0000-0000-0000000000a1';
    my $fuuid_b = '00000000-0000-0000-0000-0000000000b2';
    my $name_b = $legacy_location eq 'current' ? 'oldName' : 'reusedName';
    my $legacy_name = $legacy_location eq 'current' ? $name_b : 'formerName';
    my $device_b = synthetic_device($name_b, $fuuid_b);
    $defs{$name_b} = $device_b;
    my $stable_password_b = "Wattpilot_${fuuid_b}_password";
    my $stable_hash_b = "Wattpilot_${fuuid_b}_passwordhash";
    my $legacy_hash_a = "Wattpilot_${legacy_name}_passwordhash";
    my $legacy_owner_a = "${legacy_hash_a}_owner";
    $DevIo::KEY_VALUES{$stable_password_b} = 'password-b';
    $DevIo::KEY_VALUES{$legacy_hash_a} = 'legacy-hash-a';
    $DevIo::KEY_VALUES{$legacy_owner_a} = $fuuid_a;
    if ($legacy_location eq 'pending') {
        $DevIo::KEY_VALUES{"Wattpilot_${fuuid_b}_pending_legacy_passwordhash_names"} =
            '["formerName"]';
    }

    is(main::Wattpilot_Define($device_b, "$name_b Wattpilot 192.0.2.11"), undef,
        "$legacy_location foreign hash does not fail Define");
    is($device_b->{STATE}, 'disconnected',
        "$legacy_location foreign hash leaves B waiting for one scheduled connection from its stable password");
    is(scalar @DevIo::ACTIVE_TIMERS, 1,
        "$legacy_location foreign hash schedules exactly one connection timer for B");
    is($DevIo::KEY_VALUES{$legacy_hash_a}, 'legacy-hash-a',
        "$legacy_location foreign hash remains unchanged during Define");
    is($DevIo::KEY_VALUES{$legacy_owner_a}, $fuuid_a,
        "$legacy_location foreign hash owner remains unchanged during Define");
    ok(!exists $DevIo::KEY_VALUES{$stable_hash_b},
        "$legacy_location scenario starts without a stable B hash");

    $device_b->{SERIAL} = '0000000000000002';
    main::Wattpilot_SendAuth($device_b,
        { hash => 'pbkdf2', token1 => 'TOKEN-B-ONE', token2 => 'TOKEN-B-TWO' });
    ok(defined $DevIo::KEY_VALUES{$stable_hash_b} && $DevIo::KEY_VALUES{$stable_hash_b} ne '',
        "$legacy_location authentication stores B's own FUUID hash");
    is($DevIo::KEY_VALUES{$legacy_hash_a}, 'legacy-hash-a',
        "$legacy_location authentication preserves A's legacy hash");
    is($DevIo::KEY_VALUES{$legacy_owner_a}, $fuuid_a,
        "$legacy_location authentication preserves A's owner marker");
}

DevIo::reset_test_state();
%defs = ();
$modules{Wattpilot}{defptr} = {};
my $fuuid_a = '00000000-0000-0000-0000-0000000000a1';
my $fuuid_b = '00000000-0000-0000-0000-0000000000b2';
my $device_a = synthetic_device('renamedA', $fuuid_a);
my $device_b = synthetic_device('oldName', $fuuid_b);
$defs{renamedA} = $device_a;
$defs{oldName} = $device_b;
$DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_pending_legacy_password_names"} = '["oldName"]';
$DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_pending_legacy_passwordhash_names"} = '["oldName"]';
$DevIo::KEY_VALUES{'Wattpilot_oldName_password'} = 'legacy-password-b';
$DevIo::KEY_VALUES{'Wattpilot_oldName_password_owner'} = $fuuid_b;
$DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash'} = 'legacy-hash-b';
$DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash_owner'} = $fuuid_b;
is(main::Wattpilot_GetPassword($device_a)->{status}, 'error', 'A reports an ownership conflict instead of adopting B credential');
ok(!exists $DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_password"}, 'ownership conflict creates no stable A credential');
is(main::Wattpilot_Set($device_a, 'renamedA', 'Password', 'new-password-a'), undef, 'A can set a new stable password without touching B');
is($DevIo::KEY_VALUES{'Wattpilot_oldName_password'}, 'legacy-password-b', 'password change on A preserves B legacy credential');
is($DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash'}, 'legacy-hash-b', 'password change on A preserves B legacy hash');
is(main::Wattpilot_Delete($device_a, 'renamedA'), undef, 'A can be deleted without claiming B resource');
is($DevIo::KEY_VALUES{'Wattpilot_oldName_password'}, 'legacy-password-b', 'deletion of A preserves B legacy credential');
is($DevIo::KEY_VALUES{'Wattpilot_oldName_passwordhash'}, 'legacy-hash-b', 'deletion of A preserves B legacy hash');

$DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_password"} = 'restored-password-a';
$DevIo::KEY_VALUES{"Wattpilot_${fuuid_b}_password"} = 'password-b';
is(main::Wattpilot_Set($device_b, 'oldName', 'Password', 'changed-password-b'), undef, 'B password change succeeds for B-owned resources');
is($DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_password"}, 'restored-password-a', 'B password change does not damage A stable credential');
$DevIo::KEY_VALUES{'Wattpilot_oldName_password'} = 'legacy-password-b';
$DevIo::KEY_VALUES{'Wattpilot_oldName_password_owner'} = $fuuid_b;
is(main::Wattpilot_Delete($device_b, 'oldName'), undef, 'B deletion removes only B-owned resources');
is($DevIo::KEY_VALUES{"Wattpilot_${fuuid_a}_password"}, 'restored-password-a', 'B deletion does not damage A stable credential');

DevIo::reset_test_state();
my $unowned_current = synthetic_device('unverifiedName', $fuuid_a);
$DevIo::KEY_VALUES{'Wattpilot_unverifiedName_password'} = 'ambiguous-password';
my $ambiguous_result = main::Wattpilot_GetPassword($unowned_current);
is($ambiguous_result->{status}, 'absent', 'an unowned current-name legacy credential is not claimed from the mutable name');
is($DevIo::KEY_VALUES{'Wattpilot_unverifiedName_password'}, 'ambiguous-password', 'unowned legacy credential is preserved');
ok(!scalar(grep { $_->[0] eq 'get' && $_->[1] eq 'Wattpilot_unverifiedName_password' } @DevIo::KEY_OPERATIONS), 'getter does not read an unowned secret value');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_unverifiedName_password_owner'}, 'getter creates no owner marker from the current name alone');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic read failure';
is(main::Wattpilot_GetPassword($hash)->{status}, 'error', 'stable credential read failure is preserved explicitly');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'legacy-password', 'read failure does not touch the legacy credential');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic define read failure';
is(main::Wattpilot_Define($hash, 'testWallbox Wattpilot 192.0.2.10'), undef, 'Define remains structurally successful during credential storage outage');
is($hash->{STATE}, 'credential error', 'Define reports credential read failure honestly');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'Define schedules no reconnect after credential read failure');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic enable read failure';
main::Wattpilot_Attr('set', 'testWallbox', 'disable', '0');
is($hash->{STATE}, 'credential error', 'enable reports credential read failure honestly');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'enable schedules no reconnect after credential read failure');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::GET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names'} = 'synthetic metadata read failure';
main::Wattpilot_Define($hash, 'testWallbox Wattpilot 192.0.2.10');
is($hash->{STATE}, 'credential error', 'Define distinguishes metadata failure from a missing password');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic delete snapshot failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/before changes were made/, 'DeleteFn returns the snapshot failure after UndefFn');
is($hash->{STATE}, 'credential error', 'failed-delete restoration preserves the credential read error state');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'failed-delete restoration does not reconnect on credential read failure');

$hash = fresh_device();
my $incoming = '{"type":"authRequired","token1":"TOKEN-SYNTHETIC","token2":"TOKEN-SECOND","serial":"SERIAL-SYNTHETIC","endpoint":"wss://192.0.2.10/ws","hash":"HASH-SYNTHETIC","hmac":"HMAC-SYNTHETIC"}';
main::Wattpilot_Parse($hash, $incoming);
my $normal_logs = log_text();
unlike($normal_logs, qr/TOKEN-SYNTHETIC|TOKEN-SECOND|SERIAL-SYNTHETIC|HASH-SYNTHETIC|HMAC-SYNTHETIC|192\.0\.2\.10|\Q$incoming\E/, 'normal logs redact inbound payload and sensitive fields');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
my $normal_outgoing = $DevIo::WRITES[0][1];
unlike(log_text(), qr/\Q$normal_outgoing\E|synthetic-command-key|"hmac"/, 'normal logs redact outbound secured payload, key, and HMAC');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::ATTR_VALUES{'testWallbox|privacy'} = 1;
main::Wattpilot_Connect($hash);
is(scalar @DevIo::OPENS, 1, 'initial connection uses the centralized DevIo open path');
is($DevIo::OPENS[0][1], 0, 'initial connection preserves DevIo reopen=0 semantics');
like(log_text(), qr/HttpUtils url=http:\/\/192\.0\.2\.10:80\/ws/, 'negative control reproduces transitive HttpUtils URL logging at verbose 5');
ok(scalar(grep { $_->[1] == 5 && $_->[2] =~ /HttpUtils url=/ } @DevIo::LOGS), 'HttpUtils URL side effect is modeled at level 5');
ok(scalar(grep { $_->[1] == 4 && $_->[2] =~ /IP: 192\.0\.2\.10/ } @DevIo::LOGS), 'HttpUtils DNS/IP side effect is modeled at level 4');
ok(scalar(grep { $_ eq 'CONNECTED' } @DevIo::TRIGGERS), 'initial successful connect emits CONNECTED');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::OPEN_MODE = 'sync_error';
main::Wattpilot_Connect($hash);
like(log_text(), qr/HttpUtils: connect to http:\/\/192\.0\.2\.10/, 'synchronous HttpUtils connection failure is modeled');
like(log_text(), qr/WebSocket connection failed/, 'connection error remains visible as a redacted diagnostic');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::OPEN_MODE = 'dns_error';
main::Wattpilot_Connect($hash);
like(log_text(), qr/gethostbyname 192\.0\.2\.10 failed/, 'DNS failure and callback path are modeled');
ok(scalar(grep { $_ eq 'DISCONNECTED' } @DevIo::TRIGGERS), 'initial asynchronous DNS failure emits DISCONNECTED');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::OPEN_MODE = 'async_error';
main::Wattpilot_Connect($hash);
like(log_text(), qr/connection refused/, 'asynchronous HttpUtils connect failure is modeled');
ok(scalar(grep { $_ eq 'DISCONNECTED' } @DevIo::TRIGGERS), 'initial asynchronous connect failure emits DISCONNECTED');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::OPEN_MODE = 'timeout';
main::Wattpilot_Connect($hash);
like($DevIo::OPEN_CALLBACKS[-1][1], qr/timed out/, 'HttpUtils timeout reaches the DevIo callback');
ok(scalar(grep { $_ eq 'DISCONNECTED' } @DevIo::TRIGGERS), 'initial timeout emits DISCONNECTED');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$hash->{STATE} = 'disconnected';
main::Wattpilot_Ready($hash);
is($DevIo::OPENS[0][1], 1, 'ReadyFn reconnect preserves DevIo reopen=1 semantics');
ok(scalar(grep { $_ eq 'CONNECTED' } @DevIo::TRIGGERS), 'successful reconnect emits CONNECTED');

$hash = fresh_device();
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::OPEN_MODE = 'async_error';
$hash->{STATE} = 'disconnected';
main::Wattpilot_Ready($hash);
ok(!scalar(grep { $_ eq 'DISCONNECTED' } @DevIo::TRIGGERS), 'failed reconnect does not forge an initial DISCONNECTED event');

DevIo::reset_test_state();
my $invalid = '{"token":"TOKEN-IN-INVALID-JSON",}';
main::Wattpilot_Parse($hash, $invalid);
unlike(log_text(), qr/TOKEN-IN-INVALID-JSON|\Q$invalid\E/, 'JSON errors suppress the untrusted payload');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 4;
main::Wattpilot_Parse($hash, $incoming);
unlike(log_text(), qr/\Q$incoming\E/, 'rawJsonLog alone does not log inbound payload below verbose 5');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
main::Wattpilot_Parse($hash, $incoming);
like(log_text(), qr/\Q$incoming\E/, 'rawJsonLog with verbose 5 logs exact inbound payload');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 0;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
my $secured_outgoing = $DevIo::WRITES[0][1];
my $secured_hex = unpack('H*', $secured_outgoing);
is(payload_log_count($secured_outgoing), 0, 'securedMsg is not logged in clear text when rawJsonLog is disabled at verbose 5');
unlike(log_text(), qr/\Q$secured_hex\E/, 'securedMsg is not logged in hex when rawJsonLog is disabled at verbose 5');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 4;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
$secured_outgoing = $DevIo::WRITES[0][1];
is(payload_log_count($secured_outgoing), 0, 'securedMsg is not logged when rawJsonLog is enabled below verbose 5');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
$secured_outgoing = $DevIo::WRITES[0][1];
is(payload_log_count($secured_outgoing), 1, 'securedMsg has exactly one intentional raw log entry');
like(log_text(), qr/RAW JSON OUT: \Q$secured_outgoing\E/, 'securedMsg raw log entry is clearly marked');
is($DevIo::WRITES[0][2], 2, 'securedMsg is passed to DevIo as unpacked text; DevIo selects the WebSocket opcode');
ok(!exists $main::attr{testWallbox}{verbose}, 'JSON write restores the prior absence of a device verbose attribute');

DevIo::reset_test_state();
$main::attr{testWallbox}{verbose} = 5;
main::Wattpilot_WriteJson($hash, '{"type":"syntheticTextFrame"}');
is($main::attr{testWallbox}{verbose}, 5, 'JSON write restores an existing device verbose attribute exactly');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 0;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$hash->{SERIAL} = '0000000000000001';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
my $auth_outgoing = $DevIo::WRITES[0][1];
my $auth_hex = unpack('H*', $auth_outgoing);
is(payload_log_count($auth_outgoing), 0, 'authentication frame is not logged in clear text when rawJsonLog is disabled at verbose 5');
unlike(log_text(), qr/\Q$auth_hex\E/, 'authentication frame is not logged in hex when rawJsonLog is disabled at verbose 5');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 4;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
$auth_outgoing = $DevIo::WRITES[0][1];
is(payload_log_count($auth_outgoing), 0, 'authentication frame is not logged when rawJsonLog is enabled below verbose 5');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
$auth_outgoing = $DevIo::WRITES[0][1];
is(payload_log_count($auth_outgoing), 1, 'authentication frame has exactly one intentional raw log entry');
like(log_text(), qr/RAW JSON OUT: \Q$auth_outgoing\E/, 'authentication raw log entry is clearly marked');
is($DevIo::WRITES[0][2], 2, 'authentication is passed to DevIo as unpacked text; DevIo selects the WebSocket opcode');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic hash storage failure';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
is(scalar @DevIo::WRITES, 0, 'authentication is not sent when password-hash persistence fails');
is($DevIo::READING_UPDATES[-1][2], 'auth_hash_store_failed', 'hash persistence failure sets an explicit authentication status');
unlike(log_text(), qr/TOKEN-ONE|TOKEN-TWO|synthetic-password/, 'hash persistence failure logs no sensitive authentication values');

$hash = fresh_device();
$hash->{SERIAL} = '0000000000000001';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic auth credential read failure';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
is(scalar @DevIo::WRITES, 0, 'authentication sends nothing after credential read failure');
is($hash->{STATE}, 'credential error', 'authentication reports credential storage failure honestly');
unlike(log_text(), qr/TOKEN-ONE|TOKEN-TWO/, 'authentication credential error logs no challenge material');

$hash = fresh_device();
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::GET_KEY_ERRORS{$stable_hash} = 'synthetic secure credential read failure';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
is(scalar @DevIo::WRITES, 0, 'secured command sends nothing after credential read failure');
is($hash->{STATE}, 'credential error', 'secured command reports credential storage failure honestly');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'} = 'legacy-derived-value';
is(main::Wattpilot_GetStoredSecret($hash, 'password', { include_owned_current => 1 })->{status}, 'absent', 'unowned pre-FUUID password is not migrated from a mutable name');
is(main::Wattpilot_GetStoredSecret($hash, 'passwordhash', { include_owned_current => 1 })->{status}, 'absent', 'unowned pre-FUUID hash is not migrated from a mutable name');
is(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), undef, 'password can be changed before first successful authentication');
is($DevIo::KEY_VALUES{$stable_password}, 'new-synthetic-password', 'password change stores the new stable password');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'password change leaves no stable derived hash');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'}, 'legacy-derived-value', 'password change preserves an unverifiable legacy hash');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'legacy-password', 'password change preserves an unverifiable legacy password');
is(main::Wattpilot_GetPasswordHash($hash)->{status}, 'absent', 'unowned legacy hash remains unusable after password change');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic stable hash delete failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), qr/failed to invalidate/, 'stable hash deletion failure rejects password change');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password', 'stable hash deletion failure keeps old password');
is($DevIo::KEY_VALUES{$stable_hash}, 'old-stable-hash', 'stable hash deletion failure keeps old hash');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::GET_KEY_ERRORS{$stable_hash} = 'synthetic password snapshot failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), qr/failed to inspect/, 'password update aborts on snapshot read failure');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password', 'password snapshot failure performs no update');
is(scalar(grep { $_->[0] eq 'set' } @DevIo::KEY_OPERATIONS), 0, 'password snapshot failure performs no writes');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic password store failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), qr/failed to store new password/, 'password store failure aborts update');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password', 'password store failure preserves old password');
is($DevIo::KEY_VALUES{$stable_hash}, 'old-stable-hash', 'password store failure restores invalidated hash');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic password store failure';
$DevIo::SET_KEY_ERROR_QUEUE{$stable_hash} = [undef, 'synthetic password rollback failure'];
like(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), qr/rollback incomplete/, 'password update reports rollback failure explicitly');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'password rollback failure is not falsely reported as restored');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'old-stable-hash';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'} = 'old-legacy-hash';
own_legacy($hash, 'testWallbox', 'passwordhash');
$DevIo::SET_KEY_ERRORS{'Wattpilot_testWallbox_passwordhash'} = 'synthetic legacy hash delete failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), qr/failed to invalidate/, 'legacy hash deletion failure rejects password change');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password', 'legacy hash deletion failure keeps old stable password');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'}, 'old-stable-hash', 'legacy hash deletion failure rolls back an already invalidated stable hash');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'}, 'old-legacy-hash', 'legacy hash deletion failure keeps old legacy hash');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'old-legacy-password';
own_legacy($hash, 'testWallbox', 'password');
is(main::Wattpilot_Set($hash, 'testWallbox', 'Password', 'new-synthetic-password'), undef, 'stable and legacy password values are cleaned up transactionally');
is($DevIo::KEY_VALUES{$stable_password}, 'new-synthetic-password', 'controlled cleanup keeps the new stable value');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'controlled cleanup removes the remaining legacy value');

DevIo::reset_test_state();
main::Wattpilot_Attr('set', 'testWallbox', 'rawJsonLog', '1');
like(log_text(), qr/WARNING.*sensitive authentication, network, device, and operational data/, 'enabling raw JSON logging emits a security warning');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_Attr('set', 'testWallbox', 'disable', '1');
is(scalar @DevIo::ACTIVE_TIMERS, 0, 'disable removes timers');
is(scalar @DevIo::CLOSES, 1, 'disable closes DevIo');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'}, 'synthetic-password', 'disable preserves credentials');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_Undefine($hash, $hash->{NAME});
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'}, 'synthetic-password', 'rereadcfg-style UndefFn preserves credentials');
main::Wattpilot_Undefine($hash, $hash->{NAME});
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'}, 'synthetic-password', 'module reload-style UndefFn preserves credentials');

open my $module_fh, '<', $module or die "Cannot read $module: $!";
local $/;
my $source = <$module_fh>;
close $module_fh;

my @subs = $source =~ /^sub\s+([A-Za-z_]\w*)/gm;
my %seen;
my @duplicates = grep { $seen{$_}++ } @subs;
is_deeply(\@duplicates, [], 'global subroutine names are unique');

my @unprefixed = grep { $_ !~ /^Wattpilot_/ } @subs;
is_deeply(\@unprefixed, [], 'global module subroutines use the Wattpilot_ prefix');

for my $fixture (qw(fullStatus-flex-43.4.json deltaStatus-flex-43.4.json)) {
    my $path = File::Spec->catfile($root, 't', 'fixtures', $fixture);
    open my $fixture_fh, '<', $path or die "Cannot read $path: $!";
    local $/;
    my $decoded = eval { decode_json(<$fixture_fh>) };
    close $fixture_fh;
    ok(!$@ && ref($decoded) eq 'HASH', "$fixture is valid JSON");
}

done_testing;

