use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(decode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    my (%options) = @_;
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'serialRecoveryWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000112',
        DeviceName => 'ws:192.0.2.112:80/ws',
        STATE => 'authenticating',
        TEST_OPEN => 1,
    };
    $hash->{helper}{lifecycleState} = 'authenticating';
    $hash->{SERIAL} = $options{serial} if defined $options{serial};
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_password'} = 'example-password'
        if !$options{without_password};
    return $hash;
}

sub challenge {
    return {
        type => 'authRequired',
        hash => 'pbkdf2',
        token1 => 'token-one',
        token2 => 'token-two',
    };
}

sub timer_count {
    my ($function) = @_;
    return scalar grep { $_->[1] eq $function } @DevIo::ACTIVE_TIMERS;
}

{
    no warnings 'redefine';
    local *main::Wattpilot_SecureRandomBytes = sub { return pack('C*', 0 .. 15) };

    my $hash = fresh_device();
    $DevIo::NOW = 100;
    main::Wattpilot_DispatchMessage($hash, challenge());

    is(scalar @DevIo::WRITES, 0,
        'authRequired without a serial does not derive or send an authentication response yet');
    is($hash->{STATE}, 'authenticating',
        'transiently missing serial does not immediately enter authConfigMissing');
    ok(ref($hash->{helper}{pendingAuthChallenge}) eq 'HASH',
        'challenge is retained only for the bounded serial wait');
    is_deeply([sort keys %{$hash->{helper}{pendingAuthChallenge}}],
        [qw(hash token1 token2)],
        'only the authentication fields needed for resume are retained');
    ok($hash->{helper}{authSerialRecoveryUsed},
        'the single serial recovery allowance is marked as used for this session');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 1,
        'exactly one bounded serial-wait timer is active');

    main::Wattpilot_DispatchMessage($hash, challenge());
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 1,
        'a duplicate challenge does not create another recovery timer');
    is($hash->{STATE}, 'authenticating',
        'a duplicate challenge remains within the existing bounded recovery');

    main::Wattpilot_DispatchMessage($hash, {
        type => 'hello',
        serial => '00112233',
        version => '43.4',
        devicetype => 'wattpilot_flex',
        protocol => 2,
    });

    is($hash->{SERIAL}, '00112233',
        'hello supplies the missing numeric serial including leading zeroes');
    is(scalar @DevIo::WRITES, 1,
        'the retained challenge resumes immediately after hello supplies the serial');
    is(decode_json($DevIo::WRITES[0][1])->{type}, 'auth',
        'resumed authentication sends the normal auth response');
    ok($hash->{helper}{authPending},
        'resumed authentication enters the ordinary pending-auth state');
    ok(!exists $hash->{helper}{pendingAuthChallenge},
        'the retained challenge is removed before normal authentication continues');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'successful resume cancels the bounded serial-wait timer');

    $hash = fresh_device();
    $DevIo::NOW = 200;
    main::Wattpilot_DispatchMessage($hash, challenge());
    DevIo::run_due_timers(202);

    is(scalar @DevIo::WRITES, 0,
        'no authentication response is sent when no serial ever arrives');
    is($hash->{STATE}, 'authConfigMissing',
        'expiry of the one bounded wait reports genuine missing authentication configuration');
    ok(!exists $hash->{helper}{pendingAuthChallenge},
        'timeout clears the retained challenge');
    ok(!exists $hash->{helper}{authSerialRecoveryUsed},
        'session abort clears the recovery marker');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'timeout leaves no serial-recovery timer behind');
    is(scalar @DevIo::CLOSES, 1,
        'genuinely missing serial closes the failed authentication session once');

    $hash = fresh_device(without_password => 1);
    main::Wattpilot_DispatchMessage($hash, challenge());
    is($hash->{STATE}, 'passwordMissing',
        'missing password remains distinct from a transiently missing serial');
    ok(!exists $hash->{helper}{pendingAuthChallenge},
        'missing password does not start serial recovery');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'missing password schedules no serial-wait timer');

    $hash = fresh_device();
    main::Wattpilot_DispatchMessage($hash, {
        type => 'authRequired',
        hash => 'pbkdf2',
        token1 => [],
        token2 => 'token-two',
    });
    is($hash->{STATE}, 'authChallengeInvalid',
        'an invalid challenge fails before serial-order recovery is considered');
    ok(!exists $hash->{helper}{pendingAuthChallenge},
        'an invalid challenge is never retained');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'an invalid challenge schedules no serial-wait timer');

    $hash = fresh_device();
    $DevIo::NOW = 300;
    main::Wattpilot_DispatchMessage($hash, challenge());
    my $stale_ctx = $hash->{helper}{timers}{auth_serial_wait};
    main::Wattpilot_InvalidateSession($hash, undef, 'test invalidation');
    ok(!exists $hash->{helper}{pendingAuthChallenge},
        'session invalidation clears the retained challenge');
    ok(!exists $hash->{helper}{authSerialRecoveryUsed},
        'session invalidation clears the recovery allowance');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'session invalidation cancels the bounded serial timer');
    my $state_after_invalidation = $hash->{STATE};
    main::Wattpilot_AuthSerialWaitTimeout($stale_ctx);
    is($hash->{STATE}, $state_after_invalidation,
        'a stale serial-wait callback cannot change the replacement lifecycle');
    is(scalar @DevIo::WRITES, 0,
        'a stale serial-wait callback cannot send authentication data');

    $hash = fresh_device();
    $DevIo::NOW = 400;
    main::Wattpilot_DispatchMessage($hash, {
        type => 'authRequired',
        token1 => 'legacy-one',
        token2 => 'legacy-two',
    });
    main::Wattpilot_DispatchMessage($hash, {
        type => 'hello',
        serial => '00112244',
        version => '36.3',
        devicetype => 'wattpilot',
        protocol => 2,
    });
    is(scalar @DevIo::WRITES, 1,
        'reversed legacy protocol-2 ordering also resumes without an announced hash');
    is($hash->{READINGS}{authHashMode}{VAL}, 'pbkdf2',
        'deferred legacy challenge selects PBKDF2 only after hello establishes the profile');

    $hash = fresh_device(serial => '00999999');
    main::Wattpilot_DispatchMessage($hash, {
        type => 'hello',
        serial => '00112233',
        version => '43.4',
        devicetype => 'wattpilot_flex',
        protocol => 2,
    });
    is($hash->{SERIAL}, '00999999',
        'an explicitly configured serial keeps precedence over hello');
    main::Wattpilot_DispatchMessage($hash, challenge());
    is(scalar @DevIo::WRITES, 1,
        'normal hello-before-authRequired order authenticates without deferral');
    ok(!exists $hash->{helper}{authSerialRecoveryUsed},
        'normal ordering consumes no serial recovery allowance');
    is(timer_count('Wattpilot_AuthSerialWaitTimeout'), 0,
        'normal ordering schedules no serial-wait timer');
}

done_testing;
