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
    $modules{Wattpilot}{defptr} = {};
    my $hash = {
        NAME => 'nrgRegressionWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000051',
        DeviceName => 'ws:192.0.2.51:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    return $hash;
}

sub nrg {
    my ($power) = @_;
    return [230, 231, 232, 0, 1, 1, 1, 230, 231, 232, 0, $power];
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    return main::Wattpilot_Parse($hash, encode_json({
        type => $type,
        status => $status,
    }));
}

sub reading_value {
    my ($hash, $reading) = @_;
    return $hash->{READINGS}{$reading}{VAL};
}

subtest 'charging uses the current car state before nrg gating' => sub {
    for my $idle_setting (0, 1) {
        my $hash = fresh_device();
        $attr{$hash->{NAME}}{interval} = 30;
        $attr{$hash->{NAME}}{update_while_idle} = $idle_setting;

        $DevIo::NOW = 1_000;
        ok(parse_status($hash, 'fullStatus', {
            partial => JSON::false(),
            car => 2,
            nrg => nrg(690),
        }), "charging fullStatus is accepted with update_while_idle=$idle_setting");
        is(reading_value($hash, 'power'), '690.00',
            "charging nrg is processed with update_while_idle=$idle_setting");
        is($hash->{helper}{car_state}, 2,
            'car helper contains the charging state from the same message');
        is($hash->{LAST_UPDATE}, 1_000,
            'valid charging nrg establishes interval history');

        $DevIo::NOW = 1_029;
        ok(parse_status($hash, 'deltaStatus', { nrg => nrg(750) }),
            'charging delta without a car field is accepted');
        is(reading_value($hash, 'power'), '690.00',
            'charging nrg remains rate-limited before the boundary');
        is($hash->{LAST_UPDATE}, 1_000,
            'rate-limited nrg does not advance interval history');

        $DevIo::NOW = 1_030;
        ok(parse_status($hash, 'deltaStatus', { nrg => nrg(900) }),
            'charging delta at the exact interval boundary is accepted');
        is(reading_value($hash, 'power'), '900.00',
            'charging nrg updates at the exact interval boundary');
        is($hash->{LAST_UPDATE}, 1_030,
            'processed boundary nrg advances interval history');
    }
};

subtest 'idle policy remains explicit for both attribute values' => sub {
    my $suppressed = fresh_device();
    $attr{$suppressed->{NAME}}{interval} = 0;
    $attr{$suppressed->{NAME}}{update_while_idle} = 0;
    $DevIo::NOW = 2_000;
    ok(parse_status($suppressed, 'fullStatus', {
        partial => JSON::false(),
        car => 1,
        nrg => nrg(0),
    }), 'idle fullStatus is accepted while idle updates are disabled');
    ok(!exists $suppressed->{READINGS}{power},
        'idle nrg stays passive with update_while_idle=0');
    ok(!exists $suppressed->{LAST_UPDATE},
        'suppressed idle nrg does not establish interval history');

    my $enabled = fresh_device();
    $attr{$enabled->{NAME}}{interval} = 0;
    $attr{$enabled->{NAME}}{update_while_idle} = 1;
    $DevIo::NOW = 2_100;
    ok(parse_status($enabled, 'fullStatus', {
        partial => JSON::false(),
        car => 1,
        nrg => nrg(0),
    }), 'idle fullStatus is accepted while idle updates are enabled');
    is(reading_value($enabled, 'power'), '0.00',
        'real idle nrg is processed with update_while_idle=1');
    is($enabled->{LAST_UPDATE}, 2_100,
        'processed idle nrg establishes interval history');
};

subtest 'interval zero disables electrical rate limiting' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 0;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 3_000;
    ok(parse_status($hash, 'deltaStatus', { car => 2, nrg => nrg(100) }),
        'first unlimited charging delta is accepted');
    is(reading_value($hash, 'power'), '100.00',
        'first unlimited nrg value is processed');

    $DevIo::NOW = 3_001;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(200) }),
        'second unlimited charging delta is accepted');
    is(reading_value($hash, 'power'), '200.00',
        'interval=0 admits consecutive nrg values');
    is($hash->{LAST_UPDATE}, 3_001,
        'latest valid unlimited nrg records its timestamp');
};

subtest 'one shared interval cycle publishes all volatile telemetry' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 4_000;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(),
        car => 2,
        fbuf_akkuSOC => 51,
        fbuf_pAkku => -400,
        fbuf_akkuMode => 1,
        nrg => nrg(690),
    }), 'combined charging fullStatus is accepted');
    is($hash->{LAST_UPDATE}, 4_000,
        'combined status establishes the one shared telemetry timestamp');
    ok(!exists $hash->{LAST_BATTERY_UPDATE},
        'no independent battery interval history exists');

    my $updates_before_battery_delta = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 4_030;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 50,
        fbuf_pAkku => -500,
        fbuf_akkuMode => 2,
    }), 'battery-only delta at the shared boundary is accepted');
    is(reading_value($hash, 'power'), '690.00',
        'latest cached nrg is republished by the shared cycle');
    is(reading_value($hash, 'pvBatteryPower'), '-500.00',
        'fresh battery telemetry is published at the shared boundary');
    is($hash->{LAST_UPDATE}, 4_030,
        'battery-only input advances the one shared interval history after publication');
    my @battery_cycle = map { $_->[1] }
        @DevIo::READING_UPDATES[$updates_before_battery_delta .. $#DevIo::READING_UPDATES];
    ok(grep($_ eq 'power', @battery_cycle)
        && grep($_ eq 'pvBatteryPower', @battery_cycle),
        'battery input republishes nrg and battery readings in one transaction');

    my $updates_before_nrg_delta = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 4_060;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(900) }),
        'subsequent charging nrg delta is accepted at the next boundary');
    is(reading_value($hash, 'power'), '900.00',
        'fresh nrg is published at the next shared boundary');
    is(reading_value($hash, 'pvBatteryPower'), '-500.00',
        'latest cached battery telemetry is republished in the same update call');
    is($hash->{LAST_UPDATE}, 4_060,
        'the nrg input advances the same shared interval history');
    my @nrg_cycle = map { $_->[1] }
        @DevIo::READING_UPDATES[$updates_before_nrg_delta .. $#DevIo::READING_UPDATES];
    ok(grep($_ eq 'power', @nrg_cycle)
        && grep($_ eq 'pvBatteryPower', @nrg_cycle),
        'nrg input republishes nrg and battery readings in one transaction');
};

subtest 'invalid or incomplete nrg cannot consume the interval' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 0;

    $DevIo::NOW = 5_000;
    ok(parse_status($hash, 'deltaStatus', { car => 2, nrg => nrg(300) }),
        'baseline charging nrg is accepted');
    is(reading_value($hash, 'power'), '300.00',
        'baseline nrg is visible');

    $DevIo::NOW = 5_030;
    ok(parse_status($hash, 'deltaStatus', {
        amp => 16,
        nrg => [230, 231, 232],
    }), 'delta with incomplete nrg and another valid field is accepted');
    is(reading_value($hash, 'power'), '300.00',
        'incomplete nrg leaves the existing electrical readings unchanged');
    is(reading_value($hash, 'chargingCurrent'), 16,
        'another valid field in the same delta still updates');
    is($hash->{LAST_UPDATE}, 5_000,
        'incomplete nrg does not consume the interval');

    $DevIo::NOW = 5_031;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(400) }),
        'valid nrg following an incomplete array is accepted');
    is(reading_value($hash, 'power'), '400.00',
        'valid nrg following an incomplete array is processed');
    is($hash->{LAST_UPDATE}, 5_031,
        'the later valid nrg advances interval history');
};

subtest 'observed Flex 43.4 fullStatus uses the shared measurement cycle' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;

    my $fixture_path = File::Spec->catfile(
        $root, 't', 'fixtures', 'fullStatus-flex-observed.json');
    open my $fixture_fh, '<:raw', $fixture_path
        or die "Cannot read $fixture_path: $!";
    local $/;
    my $fixture = decode_json(<$fixture_fh>);
    close $fixture_fh;

    $DevIo::NOW = 5_500;
    my $cycle_start = scalar @DevIo::READING_UPDATES;
    ok(main::Wattpilot_DispatchMessage($hash, $fixture),
        'sanitized observed Flex fullStatus is accepted');
    is(reading_value($hash, 'voltageL1'), '230.00',
        'observed Flex voltage is published while idle updates are enabled');
    is(reading_value($hash, 'power'), '0.00',
        'observed Flex total power is published');
    is(reading_value($hash, 'pvBatteryPower'), '-1525.00',
        'observed Flex battery power is published in the shared cycle');
    is($hash->{LAST_UPDATE}, 5_500,
        'observed Flex fullStatus establishes the shared cadence');
    my @cycle = map { $_->[1] }
        @DevIo::READING_UPDATES[$cycle_start .. $#DevIo::READING_UPDATES];
    ok(grep($_ eq 'voltageL1', @cycle)
        && grep($_ eq 'pvBatteryPower', @cycle),
        'observed nrg and battery readings are emitted together');

    my $battery_cycle_start = scalar @DevIo::READING_UPDATES;
    $DevIo::NOW = 5_530;
    ok(parse_status($hash, 'deltaStatus', {
        fbuf_akkuSOC => 59.94,
        fbuf_pAkku => -1400,
    }), 'observed-style idle battery delta starts the next shared cycle');
    is(reading_value($hash, 'pvBatteryStateOfCharge'), '59.9',
        'idle battery SOC is rounded to one decimal place');
    is(reading_value($hash, 'voltageL1'), '230.00',
        'cached Flex voltage is republished in the same idle cycle');
    is($hash->{LAST_UPDATE}, 5_530,
        'battery input advances the shared idle cadence');
    my @battery_cycle = map { $_->[1] }
        @DevIo::READING_UPDATES[$battery_cycle_start .. $#DevIo::READING_UPDATES];
    ok(grep($_ eq 'voltageL1', @battery_cycle)
        && grep($_ eq 'pvBatteryStateOfCharge', @battery_cycle),
        'idle battery input republishes both measurement groups together');
};

subtest 'fullStatus, deltaStatus, and matched response share the nrg gate' => sub {
    my $hash = fresh_device();
    $attr{$hash->{NAME}}{interval} = 30;
    $attr{$hash->{NAME}}{update_while_idle} = 1;

    $DevIo::NOW = 6_000;
    ok(parse_status($hash, 'fullStatus', {
        partial => JSON::false(),
        car => 1,
        nrg => nrg(10),
    }), 'fullStatus nrg is accepted');
    is(reading_value($hash, 'power'), '10.00',
        'fullStatus nrg uses the electrical gate');

    $DevIo::NOW = 6_030;
    ok(parse_status($hash, 'deltaStatus', { nrg => nrg(20) }),
        'deltaStatus nrg is accepted at the boundary');
    is(reading_value($hash, 'power'), '20.00',
        'deltaStatus nrg updates through the same gate');

    $hash->{helper}{pendingRequests}{51} = {
        key => 'syntheticNrgReadback',
        sentAt => 6_060,
    };
    $DevIo::NOW = 6_060;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => 51,
        success => JSON::true(),
        status => { nrg => nrg(30) },
    })), 'matched response carrying nrg is accepted at the boundary');
    is(reading_value($hash, 'power'), '30.00',
        'matched response nrg uses the same electrical interval gate');
    is($hash->{LAST_UPDATE}, 6_060,
        'matched response advances history only after valid nrg processing');
};

done_testing;
