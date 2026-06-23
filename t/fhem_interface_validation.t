use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Storable qw(dclone);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
require $module;

sub fresh_device {
    my ($name) = @_;
    $name //= 'testWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME       => $name,
        TYPE       => 'Wattpilot',
        FUUID      => '00000000-0000-0000-0000-000000000037',
        DeviceName => 'ws:192.0.2.37:80/ws',
        STATE      => 'connected',
        TEST_OPEN  => 1,
        helper     => {
            authenticated                  => 1,
            authPending                    => 1,
            authHashMode                   => 'pbkdf2',
            jsonBuffer                     => '{',
            idleRefreshPending             => 1,
            idleRefreshAwaitingReconnectNrg => 1,
            pendingRequests                => {
                37 => { key => 'amp', value => 16, sentAt => 1 },
            },
        },
    };
    $defs{$name} = $hash;
    $modules{Wattpilot}{defptr}{$name} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-hash';
    return $hash;
}

sub definition_hash {
    my ($name) = @_;
    $name //= 'newWallbox';
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    $modules{Wattpilot}{defptr} = { sentinel => { NAME => 'sentinel' } };
    my $hash = {
        NAME  => $name,
        TYPE  => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000038',
        helper => { preexisting => 'unchanged' },
    };
    $defs{$name} = $hash;
    return $hash;
}

my %registration;
main::Wattpilot_Initialize(\%registration);
ok(!exists $registration{GetFn}, 'module does not register an empty GetFn');
ok(!defined &main::Wattpilot_Get, 'unused Wattpilot_Get callback is absent');

my %valid_existing_value = (
    debug             => '0',
    interval          => '30',
    update_while_idle => '0',
    defaultAmp        => '16',
    disable           => '0',
    rawJsonLog        => '0',
    authHash          => 'auto',
    authHashCost      => '8',
);

my @invalid_attributes = (
    [debug             => '2',        qr/debug must be 0 or 1/],
    [debug             => undef,      qr/debug must be 0 or 1/],
    [interval          => '-1',       qr/interval must be an integer from 0 to 300/],
    [interval          => '301',      qr/interval must be an integer from 0 to 300/],
    [interval          => '1.5',      qr/interval must be an integer from 0 to 300/],
    [interval          => 'not-a-number', qr/interval must be an integer from 0 to 300/],
    [update_while_idle => '7',        qr/update_while_idle must be 0 or 1/],
    [defaultAmp        => '5',        qr/defaultAmp must be an integer from 6 to 32/],
    [defaultAmp        => '33',       qr/defaultAmp must be an integer from 6 to 32/],
    [defaultAmp        => '6.5',      qr/defaultAmp must be an integer from 6 to 32/],
    [disable           => 'true',     qr/disable must be 0 or 1/],
    [rawJsonLog        => 'yes',      qr/rawJsonLog must be 0 or 1/],
    [authHash          => 'sha256',   qr/authHash must be one of auto, pbkdf2, bcrypt/],
    [authHashCost      => '3',        qr/authHashCost must be an integer from 4 to 14/],
    [authHashCost      => '15',       qr/authHashCost must be an integer from 4 to 14/],
    [authHashCost      => '8.0',      qr/authHashCost must be an integer from 4 to 14/],
);

for my $case (@invalid_attributes) {
    my ($attribute, $value, $error_re) = @$case;
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{$attribute} = $valid_existing_value{$attribute};
    my $hash_before = dclone($hash);
    my $keys_before = dclone(\%DevIo::KEY_VALUES);
    my $attr_before = dclone(\%attr);

    my $error = DevIo::command_attr($hash->{NAME}, $attribute, $value);
    like($error, $error_re, "$attribute rejects invalid set value");
    is_deeply($hash, $hash_before, "$attribute invalid value leaves device state unchanged");
    is_deeply(\%DevIo::KEY_VALUES, $keys_before,
        "$attribute invalid value leaves credentials unchanged");
    is_deeply(\%attr, $attr_before,
        "$attribute invalid value is rejected before FHEM attribute storage");
    is(scalar @DevIo::KEY_OPERATIONS, 0,
        "$attribute invalid value performs no credential I/O");
    is(scalar @DevIo::ACTIVE_TIMERS, 0,
        "$attribute invalid value creates no timer");
    is(scalar @DevIo::REMOVED_TIMERS, 0,
        "$attribute invalid value removes no timer");
    is(scalar @DevIo::CLOSES, 0,
        "$attribute invalid value does not close DevIo");
    is(scalar @DevIo::OPENS, 0,
        "$attribute invalid value does not open DevIo");
    is(scalar @DevIo::READING_UPDATES, 0,
        "$attribute invalid value creates no reading event");
    is(scalar @DevIo::LOGS, 0,
        "$attribute invalid value creates no misleading diagnostic");
}

my @valid_attributes = (
    [debug             => '0'],
    [debug             => '1'],
    [interval          => '0'],
    [interval          => '300'],
    [update_while_idle => '0'],
    [update_while_idle => '1'],
    [defaultAmp        => '6'],
    [defaultAmp        => '32'],
    [disable           => '0'],
    [disable           => '1'],
    [rawJsonLog        => '0'],
    [rawJsonLog        => '1'],
    [authHash          => 'auto'],
    [authHash          => 'pbkdf2'],
    [authHash          => 'bcrypt'],
    [authHashCost      => '4'],
    [authHashCost      => '14'],
);

for my $case (@valid_attributes) {
    my ($attribute, $value) = @$case;
    my $hash = fresh_device();
    is(DevIo::command_attr($hash->{NAME}, $attribute, $value), undef,
        "$attribute accepts documented value $value");
    is($attr{$hash->{NAME}}{$attribute}, $value,
        "$attribute documented value $value is stored after AttrFn accepts it");
}

for my $attribute (qw(
    debug interval update_while_idle defaultAmp disable rawJsonLog authHash authHashCost
)) {
    my $hash = fresh_device();
    is(main::Wattpilot_Attr('del', $hash->{NAME}, $attribute, undef), undef,
        "$attribute deletion bypasses set-value validation");
}

{
    my $hash = fresh_device();
    my $before = dclone($hash);
    is(DevIo::command_attr($hash->{NAME}, 'room', 'Garage'), undef,
        'generic readingFnAttribute remains outside module validation');
    is($attr{$hash->{NAME}}{room}, 'Garage',
        'generic attribute is stored after the module callback accepts it');
    is_deeply($hash, $before, 'generic attribute callback has no module side effects');
}

my @invalid_definitions = (
    ['newWallbox Wattpilot', qr/^Usage: define <name> Wattpilot <IP> \[Serial\]$/,
        'missing host is rejected with usage'],
    ['newWallbox Wattpilot 192.0.2.37 123456 extra',
        qr/^Usage: define <name> Wattpilot <IP> \[Serial\]$/,
        'additional argument is rejected with usage'],
    ['newWallbox Wattpilot 192.0.2.37 ABC123',
        qr/^Serial must contain digits only$/,
        'alphanumeric serial is rejected'],
    ['newWallbox Wattpilot 192.0.2.37 12-34',
        qr/^Serial must contain digits only$/,
        'punctuated serial is rejected'],
);

for my $case (@invalid_definitions) {
    my ($definition, $error_re, $label) = @$case;
    my $hash = definition_hash();
    my $hash_before = dclone($hash);
    my $defptr_before = dclone($modules{Wattpilot}{defptr});
    my $error = main::Wattpilot_Define($hash, $definition);
    like($error, $error_re, $label);
    is_deeply($hash, $hash_before, "$label without mutating the device hash");
    is_deeply($modules{Wattpilot}{defptr}, $defptr_before,
        "$label without mutating defptr");
    is(scalar @DevIo::KEY_OPERATIONS, 0, "$label without credential access");
    is(scalar @DevIo::ACTIVE_TIMERS, 0, "$label without scheduling timers");
    is(scalar @DevIo::CLOSES, 0, "$label without closing DevIo");
    is(scalar @DevIo::OPENS, 0, "$label without opening DevIo");
    is(scalar @DevIo::READING_UPDATES, 0, "$label without reading updates");
    is(scalar @DevIo::LOGS, 0, "$label without runtime diagnostics");
}

{
    my $hash = definition_hash();
    is(main::Wattpilot_Define(
        $hash, 'newWallbox Wattpilot wallbox.example.invalid'), undef,
        'three-field Define accepts a DevIo-compatible hostname');
    is($hash->{DeviceName}, 'ws:wallbox.example.invalid:80/ws',
        'Define constructs the expected WebSocket endpoint');
    ok(!defined $hash->{SERIAL}, 'serial remains undefined when omitted');
    is($modules{Wattpilot}{defptr}{newWallbox}, $hash,
        'valid Define registers defptr');
    is($hash->{STATE}, 'passwordMissing',
        'valid Define without a credential reports passwordMissing');
}

{
    my $hash = definition_hash();
    is(main::Wattpilot_Define(
        $hash, 'newWallbox Wattpilot 192.0.2.37 00123456'), undef,
        'four-field Define accepts a digits-only serial');
    is($hash->{SERIAL}, '00123456', 'Define preserves leading zeroes in the serial');
}

done_testing;
