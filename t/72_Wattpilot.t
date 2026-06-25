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

for my $slot (qw(DefFn UndefFn DeleteFn RenameFn SetFn AttrFn ReadFn ReadyFn ShutdownFn)) {
    ok(ref($registration{$slot}) eq 'CODE', "$slot registers an existing callback");
}
ok(!exists $registration{GetFn}, 'no GetFn is registered when no get commands exist');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    my $hash = {
        NAME       => 'testWallbox',
        TYPE       => 'Wattpilot',
        FUUID      => '00000000-0000-0000-0000-000000000007',
        DeviceName => 'ws:192.0.2.10:80/ws',
        STATE      => 'disconnected',
    };
    $defs{$hash->{NAME}} = $hash;
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

sub log_text {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
}

sub payload_log_count {
    my ($payload) = @_;
    return scalar grep { index(($_->[2] // ''), $payload) >= 0 } @DevIo::LOGS;
}

sub stable_key {
    my ($hash, $suffix) = @_;
    return 'Wattpilot_' . $hash->{FUUID} . '_' . $suffix;
}

my $hash = fresh_device();
my $stable_password = stable_key($hash, 'password');
my $stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
main::Wattpilot_Undefine($hash, $hash->{NAME});
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password', 'UndefFn preserves stored password');
is($DevIo::KEY_VALUES{$stable_hash}, 'synthetic-derived-value', 'UndefFn preserves stored password hash');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'UndefFn removes timers');
is(scalar @DevIo::CLOSES, 1, 'UndefFn closes DevIo');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
is(main::Wattpilot_Delete($hash, $hash->{NAME}), undef,
    'DeleteFn reports successful stable credential deletion');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'DeleteFn deletes stable password');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'DeleteFn deletes stable password hash');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'DeleteFn removes timers');
is(scalar @DevIo::CLOSES, 1, 'DeleteFn closes DevIo');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/,
    'DeleteFn returns an error for a stable-key deletion failure');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password',
    'failed stable-key deletion retains the credential');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic second delete failure';
like(main::Wattpilot_DeleteStoredSecrets($hash), qr/prior values restored/,
    'second stable-key deletion failure rolls back the first deletion');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password',
    'stable password is restored after later deletion failure');
is($DevIo::KEY_VALUES{$stable_hash}, 'synthetic-derived-value',
    'failed stable hash deletion leaves the hash intact');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
$DevIo::SET_KEY_ERROR_QUEUE{$stable_password} = [undef, 'synthetic rollback failure'];
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic second delete failure';
like(main::Wattpilot_DeleteStoredSecrets($hash), qr/rollback incomplete/,
    'stable credential deletion reports rollback failure explicitly');
ok(!exists $DevIo::KEY_VALUES{$stable_password},
    'failed rollback is not falsely reported as restored');
is($DevIo::KEY_VALUES{$stable_hash}, 'synthetic-derived-value',
    'rollback failure does not alter the key whose delete failed');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic snapshot failure';
like(main::Wattpilot_DeleteStoredSecrets($hash), qr/before changes were made/,
    'DeleteFn aborts on a stable credential snapshot failure');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password',
    'snapshot failure leaves the stable credential unchanged');
is(scalar(grep { $_->[0] eq 'set' } @DevIo::KEY_OPERATIONS), 0,
    'snapshot failure performs no credential writes');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
DevIo::InternalTimer(time + 30, 'Wattpilot_Connect', $hash, 0);
$hash->{TEST_OPEN} = 1;
main::Wattpilot_Undefine($hash, $hash->{NAME});
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'UndefFn removes the active reconnect timer before DeleteFn');
ok(!DevIo::DevIo_IsOpen($hash), 'UndefFn closes the connection before DeleteFn');
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/credential deletion failed/,
    'DeleteFn reports failure after UndefFn');
is($hash->{STATE}, 'disconnected',
    'failed DeleteFn restores an honest disconnected state');
is(scalar @DevIo::ACTIVE_TIMERS, 1,
    'failed DeleteFn restores exactly one reconnect timer when a password exists');
ok(!DevIo::DevIo_IsOpen($hash),
    'failed DeleteFn does not create a duplicate connection');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic delete failure';
$DevIo::ATTR_VALUES{'testWallbox|disable'} = 1;
main::Wattpilot_Undefine($hash, $hash->{NAME});
main::Wattpilot_Delete($hash, $hash->{NAME});
is($hash->{STATE}, 'disabled',
    'failed DeleteFn restores disabled state for a disabled retained device');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'failed DeleteFn schedules no reconnect while disabled');

$hash = fresh_device();
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::GET_KEY_ERRORS{$stable_hash} = 'synthetic snapshot failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
main::Wattpilot_Delete($hash, $hash->{NAME});
is($hash->{STATE}, 'passwordMissing',
    'failed DeleteFn reports a genuinely missing stable password');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'failed DeleteFn schedules no reconnect without a password');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic snapshot failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
main::Wattpilot_Delete($hash, $hash->{NAME});
is($hash->{STATE}, 'credentialError',
    'failed DeleteFn preserves stable credential storage errors');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'failed DeleteFn does not reconnect on credential storage error');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::KEY_VALUES{$stable_hash} = 'synthetic-derived-value';
$hash->{TEST_OPEN} = 1;
is(DevIo::command_rename('testWallbox', 'renamedWallbox'), undef,
    'CommandRename completes with stable credentials');
is($DevIo::KEY_VALUES{$stable_password}, 'synthetic-password',
    'Rename preserves the stable password');
is($DevIo::KEY_VALUES{$stable_hash}, 'synthetic-derived-value',
    'Rename preserves the stable password hash');
ok(!scalar(grep { $_->[0] eq 'set' } @DevIo::KEY_OPERATIONS),
    'Rename performs no credential writes');
is(scalar @DevIo::ACTIVE_TIMERS, 1,
    'Rename leaves exactly one controlled reconnect timer');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
my @legacy_keys = (
    'Wattpilot_testWallbox_password',
    'Wattpilot_testWallbox_passwordhash',
    'Wattpilot_testWallbox_password_owner',
    'Wattpilot_testWallbox_passwordhash_owner',
    'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_password_names',
    'Wattpilot_' . $hash->{FUUID} . '_pending_legacy_passwordhash_names',
);
my %legacy_key = map { $_ => 1 } @legacy_keys;
$DevIo::KEY_VALUES{$legacy_keys[0]} = 'legacy-password';
$DevIo::KEY_VALUES{$legacy_keys[1]} = 'legacy-hash';
$DevIo::KEY_VALUES{$legacy_keys[2]} = $hash->{FUUID};
$DevIo::KEY_VALUES{$legacy_keys[3]} = $hash->{FUUID};
$DevIo::KEY_VALUES{$legacy_keys[4]} = '["formerWallbox"]';
$DevIo::KEY_VALUES{$legacy_keys[5]} = '["formerWallbox"]';
$DevIo::KEY_VALUES{$stable_password} = 'stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'stable-hash';
main::Wattpilot_Define($hash, 'testWallbox Wattpilot 192.0.2.10');
main::Wattpilot_GetPassword($hash);
main::Wattpilot_GetPasswordHash($hash);
DevIo::command_rename('testWallbox', 'renamedWallbox');
main::Wattpilot_Set($hash, 'renamedWallbox', 'password', 'changed-password');
main::Wattpilot_Delete($hash, 'renamedWallbox');
my @legacy_operations = grep { $legacy_key{$_->[1] // ''} } @DevIo::KEY_OPERATIONS;
is_deeply(\@legacy_operations, [],
    'runtime performs no read or write against name-based, owner, or pending credential keys');
for my $key (@legacy_keys) {
    ok(exists $DevIo::KEY_VALUES{$key}, "legacy resource remains untouched: $key");
}

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic define read failure';
is(main::Wattpilot_Define($hash, 'testWallbox Wattpilot 192.0.2.10'), undef,
    'Define remains structurally successful during credential storage outage');
is($hash->{STATE}, 'credentialError',
    'Define reports stable credential read failure honestly');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'Define schedules no reconnect after credential read failure');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic enable read failure';
main::Wattpilot_Attr('set', 'testWallbox', 'disable', '0');
is($hash->{STATE}, 'credentialError',
    'enable reports stable credential read failure honestly');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'enable schedules no reconnect after credential read failure');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$DevIo::KEY_VALUES{$stable_password} = 'synthetic-password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic delete snapshot failure';
main::Wattpilot_Undefine($hash, $hash->{NAME});
like(main::Wattpilot_Delete($hash, $hash->{NAME}), qr/before changes were made/,
    'DeleteFn returns stable snapshot failure after UndefFn');
is($hash->{STATE}, 'credentialError',
    'failed-delete restoration preserves the stable credential read error state');
is(scalar @DevIo::ACTIVE_TIMERS, 0,
    'failed-delete restoration does not reconnect on credential read failure');

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
is($DevIo::READING_UPDATES[-1][2], 'authHashStoreFailed', 'hash persistence failure sets an explicit authentication status');
unlike(log_text(), qr/TOKEN-ONE|TOKEN-TWO|synthetic-password/, 'hash persistence failure logs no sensitive authentication values');

$hash = fresh_device();
$hash->{SERIAL} = '0000000000000001';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic auth credential read failure';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
is(scalar @DevIo::WRITES, 0, 'authentication sends nothing after credential read failure');
is($hash->{STATE}, 'credentialError', 'authentication reports credential storage failure honestly');
unlike(log_text(), qr/TOKEN-ONE|TOKEN-TWO/, 'authentication credential error logs no challenge material');

$hash = fresh_device();
$stable_hash = 'Wattpilot_' . $hash->{FUUID} . '_passwordhash';
$DevIo::GET_KEY_ERRORS{$stable_hash} = 'synthetic secure credential read failure';
mark_command_ready($hash);
main::Wattpilot_SendSecure($hash, 'amp', 16);
is(scalar @DevIo::WRITES, 0, 'secured command sends nothing after credential read failure');
is($hash->{STATE}, 'credentialError', 'secured command reports credential storage failure honestly');


$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
my @legacy_password_keys = (
    'Wattpilot_testWallbox_password',
    'Wattpilot_testWallbox_passwordhash',
);
$DevIo::KEY_VALUES{$legacy_password_keys[0]} = 'legacy-password';
$DevIo::KEY_VALUES{$legacy_password_keys[1]} = 'legacy-derived-value';
is(main::Wattpilot_GetStoredSecret($hash, 'password')->{status}, 'absent',
    'name-based password is ignored');
is(main::Wattpilot_GetStoredSecret($hash, 'passwordhash')->{status}, 'absent',
    'name-based hash is ignored');
is(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-synthetic-password'), undef,
    'password can be changed before first successful authentication');
is($DevIo::KEY_VALUES{$stable_password}, 'new-synthetic-password',
    'password change stores the new stable password');
ok(!exists $DevIo::KEY_VALUES{$stable_hash},
    'password change leaves no stable derived hash');
is($DevIo::KEY_VALUES{$legacy_password_keys[1]}, 'legacy-derived-value',
    'password change preserves old name-based hash');
is($DevIo::KEY_VALUES{$legacy_password_keys[0]}, 'legacy-password',
    'password change preserves old name-based password');
is(main::Wattpilot_GetPasswordHash($hash)->{status}, 'absent',
    'old name-based hash remains unusable after password change');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_hash} = 'synthetic stable hash delete failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-synthetic-password'), qr/failed to invalidate/,
    'stable hash deletion failure rejects password change');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password',
    'stable hash deletion failure keeps old password');
is($DevIo::KEY_VALUES{$stable_hash}, 'old-stable-hash',
    'stable hash deletion failure keeps old hash');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::GET_KEY_ERRORS{$stable_hash} = 'synthetic password snapshot failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-synthetic-password'), qr/failed to inspect/,
    'password update aborts on stable snapshot read failure');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password',
    'password snapshot failure performs no update');
is(scalar(grep { $_->[0] eq 'set' } @DevIo::KEY_OPERATIONS), 0,
    'password snapshot failure performs no writes');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic password store failure';
like(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-synthetic-password'), qr/failed to store new password/,
    'password store failure aborts update');
is($DevIo::KEY_VALUES{$stable_password}, 'old-stable-password',
    'password store failure preserves old password');
is($DevIo::KEY_VALUES{$stable_hash}, 'old-stable-hash',
    'password store failure restores invalidated hash');

$hash = fresh_device();
$stable_password = stable_key($hash, 'password');
$stable_hash = stable_key($hash, 'passwordhash');
$DevIo::KEY_VALUES{$stable_password} = 'old-stable-password';
$DevIo::KEY_VALUES{$stable_hash} = 'old-stable-hash';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic password store failure';
$DevIo::SET_KEY_ERROR_QUEUE{$stable_hash} = [undef, 'synthetic password rollback failure'];
like(main::Wattpilot_Set($hash, 'testWallbox', 'password', 'new-synthetic-password'), qr/rollback incomplete/,
    'password update reports rollback failure explicitly');
ok(!exists $DevIo::KEY_VALUES{$stable_hash},
    'password rollback failure is not falsely reported as restored');

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

