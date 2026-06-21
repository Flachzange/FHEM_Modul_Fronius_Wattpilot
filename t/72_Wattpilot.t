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

sub log_text {
    return join "\n", map { $_->[2] // '' } @DevIo::LOGS;
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
main::Wattpilot_Delete($hash);
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'DeleteFn deletes stable password');
ok(!exists $DevIo::KEY_VALUES{$stable_hash}, 'DeleteFn deletes stable password hash');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'DeleteFn deletes current legacy password');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'DeleteFn removes timers');
is(scalar @DevIo::CLOSES, 1, 'DeleteFn closes DevIo');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'} = 'legacy-derived-value';
delete $defs{testWallbox};
$hash->{NAME} = 'renamedWallbox';
$defs{renamedWallbox} = $hash;
main::Wattpilot_Rename('renamedWallbox', 'testWallbox');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'}, 'legacy-password', 'Rename migrates password to FUUID key');
is($DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'}, 'legacy-derived-value', 'Rename migrates password hash to FUUID key');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'Rename removes legacy password after successful migration');
ok(!exists $DevIo::KEY_VALUES{'Wattpilot_testWallbox_passwordhash'}, 'Rename removes legacy hash after successful migration');

$hash = fresh_device();
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::SET_KEY_ERRORS{$stable_password} = 'synthetic write failure';
is(main::Wattpilot_GetPassword($hash), 'legacy-password', 'failed migration still returns legacy credential');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'legacy-password', 'failed migration retains legacy credential');
ok(!exists $DevIo::KEY_VALUES{$stable_password}, 'failed migration does not create a partial stable credential');

$hash = fresh_device();
$stable_password = 'Wattpilot_' . $hash->{FUUID} . '_password';
$DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'} = 'legacy-password';
$DevIo::GET_KEY_ERRORS{$stable_password} = 'synthetic read failure';
ok(!defined main::Wattpilot_GetPassword($hash), 'stable credential read failure is reported as unavailable');
is($DevIo::KEY_VALUES{'Wattpilot_testWallbox_password'}, 'legacy-password', 'read failure does not touch the legacy credential');

$hash = fresh_device();
my $incoming = '{"type":"authRequired","token1":"TOKEN-SYNTHETIC","token2":"TOKEN-SECOND","serial":"SERIAL-SYNTHETIC","endpoint":"wss://192.0.2.10/ws","hash":"HASH-SYNTHETIC","hmac":"HMAC-SYNTHETIC"}';
main::Wattpilot_Parse($hash, $incoming);
my $normal_logs = log_text();
unlike($normal_logs, qr/TOKEN-SYNTHETIC|TOKEN-SECOND|SERIAL-SYNTHETIC|HASH-SYNTHETIC|HMAC-SYNTHETIC|192\.0\.2\.10|\Q$incoming\E/, 'normal logs redact inbound payload and sensitive fields');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
main::Wattpilot_SendSecure($hash, 'amp', 16);
my $normal_outgoing = $DevIo::WRITES[0][1];
unlike(log_text(), qr/\Q$normal_outgoing\E|synthetic-command-key|"hmac"/, 'normal logs redact outbound secured payload, key, and HMAC');

DevIo::reset_test_state();
my $invalid = '{"token":"TOKEN-IN-INVALID-JSON"';
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
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-command-key';
main::Wattpilot_SendSecure($hash, 'amp', 16);
my $secured_outgoing = $DevIo::WRITES[0][1];
like(log_text(), qr/\Q$secured_outgoing\E/, 'raw mode logs the exact outbound securedMsg frame');

DevIo::reset_test_state();
$DevIo::ATTR_VALUES{'testWallbox|rawJsonLog'} = 1;
$DevIo::ATTR_VALUES{'testWallbox|verbose'} = 5;
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
$hash->{SERIAL} = '0000000000000001';
main::Wattpilot_SendAuth($hash, { hash => 'pbkdf2', token1 => 'TOKEN-ONE', token2 => 'TOKEN-TWO' });
my $auth_outgoing = $DevIo::WRITES[0][1];
like(log_text(), qr/\Q$auth_outgoing\E/, 'raw mode logs the exact outbound authentication frame');

DevIo::reset_test_state();
main::Wattpilot_Attr('set', 'testWallbox', 'rawJsonLog', '1');
like(log_text(), qr/WARNING.*sensitive authentication, network, device, and operational data/, 'enabling raw JSON logging emits a security warning');

DevIo::reset_test_state();
$DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
main::Wattpilot_Attr('set', 'testWallbox', 'disable', '1');
is(scalar @DevIo::REMOVED_TIMERS, 1, 'disable removes timers');
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

