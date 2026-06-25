use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
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


{
    install_module();
    is(FHEMCorePinned::CommandDefine(
        undef, 'definedWallbox Wattpilot 192.0.2.67 00670001'), undef,
        'pinned CommandDefine creates a valid Wattpilot device');
    my $hash = $defs{definedWallbox};
    ok($hash, 'real core installs the device hash before DefFn');
    is($hash->{TYPE}, 'Wattpilot', 'real core records the module type');
    is($hash->{DEF}, '192.0.2.67 00670001',
        'real core retains the type-dependent definition');
    is($hash->{DeviceName}, 'ws:192.0.2.67:80/ws',
        'module receives the framework-created hash');
    is($hash->{STATE}, 'passwordMissing',
        'definition follows the normal missing-credential lifecycle');
    ok(!exists $hash->{CL}, 'real core removes the temporary command client');
    is_deeply($FHEMCorePinned::CALLS[0], ['definedWallbox', 'DefFn'],
        'real core dispatches DefFn after installing defs');
}

{
    install_module();
    like(FHEMCorePinned::CommandDefine(
        undef, 'rejectedWallbox Wattpilot 192.0.2.67 invalid-serial'),
        qr/Serial must contain digits only/,
        'pinned CommandDefine propagates a DefFn veto');
    ok(!exists $defs{rejectedWallbox},
        'real core removes a vetoed device definition');
    ok(!exists $attr{rejectedWallbox},
        'real core removes attributes for a vetoed definition');
}

{
    install_module();
    is(FHEMCorePinned::CommandDefMod(
        undef, 'newViaDefmod Wattpilot 192.0.2.68 00670002'), undef,
        'pinned CommandDefMod routes a missing device through CommandDefine');
    is($defs{newViaDefmod}{DeviceName}, 'ws:192.0.2.68:80/ws',
        'defmod creation uses the real definition path');
}

{
    my $registration = install_module();
    existing_device();
    my $original = $registration->{AttrFn};
    my @observed;
    $modules{Wattpilot}{AttrFn} = sub {
        my ($cmd, $name, $attribute, $value) = @_;
        push @observed, [
            $cmd,
            $attribute,
            exists($attr{$name}{$attribute}) ? $attr{$name}{$attribute} : undef,
        ];
        return $original->(@_);
    };

    is(FHEMCorePinned::CommandAttr(undef, 'wallbox interval 30'), '',
        'pinned CommandAttr accepts a valid module attribute');
    is_deeply($observed[0], ['set', 'interval', undef],
        'AttrFn runs before framework attribute storage');
    is($attr{wallbox}{interval}, '30',
        'framework stores the value only after AttrFn accepts it');

    like(FHEMCorePinned::CommandAttr(undef, 'wallbox interval 301'),
        qr/integer from 0 to 300/,
        'AttrFn veto is propagated by the real core path');
    is($attr{wallbox}{interval}, '30',
        'rejected attribute value does not replace the stored value');

    @observed = ();
    is(FHEMCorePinned::CommandDeleteAttr(undef, 'wallbox interval'), '',
        'pinned CommandDeleteAttr accepts deletion');
    is_deeply($observed[0], ['del', 'interval', '30'],
        'AttrFn sees the old attribute value before deletion');
    ok(!exists $attr{wallbox}{interval},
        'framework deletes the attribute after AttrFn accepts deletion');
}

{
    my $registration = install_module();
    my $hash = existing_device();
    $hash->{VERSION} = 'stale-version';
    $hash->{helper}{reloadSentinel} = 'preserved';
    my $original_hash = $hash;
    my $original_device_name = $hash->{DeviceName};
    my $original_open = $hash->{TEST_OPEN};
    my $password_key = 'Wattpilot_' . $hash->{FUUID} . '_password';
    my $original_password = $DevIo::KEY_VALUES{$password_key};

    my $tmp = tempdir(CLEANUP => 1);
    my $fhem_dir = File::Spec->catdir($tmp, 'FHEM');
    make_path($fhem_dir);
    my $module_copy = File::Spec->catfile($fhem_dir, '72_Wattpilot.pm');
    ok(copy(File::Spec->catfile($root, '72_Wattpilot.pm'), $module_copy),
        'reload fixture contains the current module file');
    $attr{global}{modpath} = $tmp;

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    is(FHEMCorePinned::CommandReload(undef, '72_Wattpilot'), undef,
        'pinned CommandReload executes the real module reload path');
    is($defs{wallbox}, $original_hash,
        'real reload preserves the existing device hash identity');
    is($hash->{VERSION}, '2.1.2',
        'real reload refreshes the module version internal');
    is($hash->{DeviceName}, $original_device_name,
        'real reload preserves the configured endpoint');
    is($hash->{TEST_OPEN}, $original_open,
        'real reload preserves the open transport state');
    is($hash->{helper}{reloadSentinel}, 'preserved',
        'real reload preserves runtime helper state');
    is($DevIo::KEY_VALUES{$password_key}, $original_password,
        'real reload preserves stable credentials');
    is($modules{Wattpilot}{DefFn}, \&main::Wattpilot_Define,
        'real reload registers the freshly loaded DefFn');
    is($modules{Wattpilot}{ORDER}, '72',
        'real reload retains the filename order prefix');
    ok($modules{Wattpilot}{LOADED}, 'real reload marks the module loaded');
    is_deeply([grep { $_ !~ /Subroutine .* redefined/ } @warnings], [],
        'reload emits no unexpected warnings');
}

done_testing();
