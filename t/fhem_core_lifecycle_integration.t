use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');
require File::Spec->catfile($root, 't', 'lib', 'FHEMCorePinned.pm');

sub install_module {
    FHEMCorePinned::reset();
    my %registration;
    main::Wattpilot_Initialize(\%registration);
    FHEMCorePinned::install_module('Wattpilot', \%registration);
    return \%registration;
}

sub existing_device {
    my ($name) = @_;
    $name //= 'wallbox';
    my $hash = {
        NAME       => $name,
        TYPE       => 'Wattpilot',
        FUUID      => '00000000-0000-0000-0000-000000000067',
        DEF        => '192.0.2.37 00123456',
        SERIAL     => '00123456',
        DeviceName => 'ws:192.0.2.37:80/ws',
        STATE      => 'connected',
        TEST_OPEN  => 1,
        helper     => { authenticated => 1 },
    };
    $defs{$name} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'synthetic-password';
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} = 'synthetic-hash';
    return $hash;
}

is($FHEMCorePinned::FHEM_REVISION,
    '0ae38bf79d19d8d598c065bf84b3990b33063c4b',
    'FHEM core revision is pinned explicitly');
is($FHEMCorePinned::FHEM_PL_BLOB_SHA,
    '0c03b2989d2e5be6f019cfb07a6a3e53db62050b',
    'pinned fhem.pl blob is explicit');
is($FHEMCorePinned::DEVIO_BLOB_SHA,
    'ce94276bb9d3e4963ebc514a93a86b442984e72f',
    'pinned DevIo.pm blob is explicit');

{
    install_module();
    my $hash = existing_device();
    is(FHEMCorePinned::CommandModify(
        undef, 'wallbox 198.51.100.44 00999999'), undef,
        'pinned CommandModify accepts a valid session replacement');
    is($hash->{DEF}, '198.51.100.44 00999999',
        'real core path keeps accepted DEF');
    is($hash->{DeviceName}, 'ws:198.51.100.44:80/ws',
        'module receives the real preinstalled new DEF');
    ok(!exists $hash->{OLDDEF}, 'real core removes OLDDEF after callback');
    is_deeply($FHEMCorePinned::CALLS[0], ['wallbox', 'DefFn'],
        'real core dispatches DefFn for modify');
}

{
    install_module();
    my $hash = existing_device();
    my $before = $hash->{DEF};
    like(FHEMCorePinned::CommandModify(
        undef, 'wallbox 198.51.100.44 invalid-serial'),
        qr/Serial must contain digits only/,
        'pinned CommandModify propagates DefFn veto');
    is($hash->{DEF}, $before, 'real core restores DEF after veto');
    is($hash->{DeviceName}, 'ws:192.0.2.37:80/ws',
        'module rollback restores the previous runtime endpoint');
    ok(!exists $hash->{OLDDEF}, 'veto path also removes OLDDEF');
}

{
    install_module();
    my $hash = existing_device();
    is(FHEMCorePinned::CommandDefMod(
        undef, 'wallbox Wattpilot 198.51.100.45 00888888'), undef,
        'pinned CommandDefMod routes an existing device through modify');
    is($hash->{DEF}, '198.51.100.45 00888888',
        'defmod retains accepted definition');
    like(FHEMCorePinned::CommandDefMod(
        undef, 'wallbox dummy 192.0.2.1'),
        qr/Cannot change the TYPE/,
        'pinned CommandDefMod rejects an existing-device type change');
}

{
    install_module();
    my $hash = existing_device('oldName');
    $attr{oldName}{room} = 'Garage';
    is(FHEMCorePinned::CommandRename(undef, 'oldName newName'), undef,
        'pinned CommandRename succeeds');
    ok(!exists $defs{oldName}, 'framework removes the old defs key before RenameFn');
    is($defs{newName}, $hash, 'framework preserves the device hash identity');
    is($defs{newName}{NAME}, 'newName', 'framework changes NAME before RenameFn');
    is($attr{newName}{room}, 'Garage', 'framework moves attributes before RenameFn');
    is_deeply($FHEMCorePinned::CALLS[0], ['newName', 'RenameFn'],
        'real core dispatches RenameFn under the new name');
}

{
    install_module();
    existing_device('deleteMe');
    is(FHEMCorePinned::CommandDelete(undef, 'deleteMe'), '',
        'pinned CommandDelete succeeds');
    is_deeply(
        [map { $_->[1] } @FHEMCorePinned::CALLS[0, 1]],
        ['UndefFn', 'DeleteFn'],
        'real core calls UndefFn before DeleteFn');
    ok(!exists $defs{deleteMe}, 'framework removes defs after both callbacks');
    ok(!exists $DevIo::KEY_VALUES{'Wattpilot_00000000-0000-0000-0000-000000000067_password'},
        'DeleteFn removes the stable password key');
    ok(!exists $DevIo::KEY_VALUES{'Wattpilot_00000000-0000-0000-0000-000000000067_passwordhash'},
        'DeleteFn removes the stable password-hash key');
}

{
    install_module();
    existing_device();
    $attr{wallbox}{disable} = 1;
    my $set_list = FHEMCorePinned::DoSet('wallbox', '?');
    like($set_list, qr/reconnect:noArg/,
        'real DoSet discovery reaches SetFn while disabled');
    like(FHEMCorePinned::DoSet('wallbox', 'reconnect'), qr/disabled/i,
        'real DoSet execution preserves disabled-device rejection');
}

{
    my $registration = install_module();
    my $hash = existing_device();
    my %reloaded;
    main::Wattpilot_Initialize(\%reloaded);
    is($defs{wallbox}, $hash,
        'reload-style Initialize preserves the existing device hash');
    is($reloaded{DefFn}, $registration->{DefFn},
        'reload-style Initialize restores the same DefFn registration');
    is($reloaded{SetFn}, $registration->{SetFn},
        'reload-style Initialize restores the same SetFn registration');
}

done_testing();
