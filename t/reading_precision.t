use strict;
use warnings;
no warnings 'once';

use File::Basename qw(dirname);
use File::Spec;
use JSON qw(encode_json);
use Test::More;

our ($readingFnAttributes, %modules, %defs, %attr);

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
require File::Spec->catfile($root, '72_Wattpilot.pm');

sub fresh_device {
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'precisionWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000053',
        DeviceName => 'ws:192.0.2.53:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $attr{$hash->{NAME}}{interval} = 0;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-precision-key';
    return $hash;
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

sub parse_status {
    my ($hash, $type, $status) = @_;
    return main::Wattpilot_Parse($hash, encode_json({
        type => $type,
        status => $status,
    }));
}

sub nrg_values {
    return [
        230, 231.2, 232.346, 0,
        6, 6.25, 6.256,
        1380, 1443.75, 1454.976,
        0, -0.004,
    ];
}

subtest 'reading inventory declares one intentional public format per reading' => sub {
    my $interface = main::Wattpilot_InterfaceSnapshot();
    my $policy = $interface->{readingPolicy};
    is_deeply(
        [sort grep { $policy->{$_}{formatter} eq 'decimal2' } keys %$policy],
        [sort qw(
            pv_surplus_start_power three_phase_switch_power
            energy_total energy_since_plug_in
            voltage_l1 voltage_l2 voltage_l3
            current_l1 current_l2 current_l3
            power_l1 power_l2 power_l3 power
        )],
        'all two-decimal public readings are explicit in the existing inventory');
    is_deeply(
        [sort grep { $policy->{$_}{formatter} eq 'diagnostic2' } keys %$policy],
        [sort qw(
            diag_fbuf_akku_soc diag_fbuf_p_akku diag_fbuf_p_grid
            diag_fbuf_p_pv diag_pvopt_average_p_grid
            diag_pvopt_average_p_pv diag_pvopt_average_p_akku
            diag_pvopt_average_p_ohmpilot diag_pvopt_delta_p
            diag_pvopt_delta_a diag_pvopt_special_case
            diag_fbuf_p_ac_total diag_fbuf_ohmpilot_state
            diag_fbuf_ohmpilot_temperature
        )],
        'all optional diagnostics use scalar-aware two-decimal formatting');
    is_deeply(
        [sort grep { $policy->{$_}{formatter} eq 'hours_minutes_ms' } keys %$policy],
        ['device_uptime'],
        'uptime is the explicit millisecond-to-hours-and-minutes formatter');
    is(scalar(grep {
            !defined($policy->{$_}{formatter})
            || $policy->{$_}{formatter} eq ''
        } keys %$policy), 0,
        'every public reading has an intentional formatter classification');
    my %known_formatter = map { $_ => 1 } qw(
        lifecycle text integer boolean seconds clock enum percentage
        decimal2 diagnostic2 hours_minutes_ms
    );
    is_deeply(
        [sort grep { !$known_formatter{$policy->{$_}{formatter}} }
            keys %$policy],
        [],
        'every declared formatter belongs to the supported central set');
};

subtest 'decimal formatter retains trailing zeroes and removes rounded negative zero' => sub {
    is(main::Wattpilot_FormatDecimal(230, 2), '230.00',
        'whole values retain two trailing decimal places');
    is(main::Wattpilot_FormatDecimal(1.236, 2), '1.24',
        'fractional values round to two decimal places');
    is(main::Wattpilot_FormatDecimal(-1.236, 2), '-1.24',
        'negative fractional values round consistently');
    is(main::Wattpilot_FormatDecimal(-0.004, 2), '0.00',
        'rounded negative zero is normalized');
    is(main::Wattpilot_FormatDecimal(-0.006, 2), '-0.01',
        'a genuinely negative rounded value keeps its sign');
    is(main::Wattpilot_FormatDecimal(42.54, 1), '42.5',
        'the decimal helper still supports one decimal place');
    is(main::Wattpilot_FormatReadingValue('device_uptime', 62_070_123),
        '17:14',
        'uptime converts milliseconds to cumulative hours and minutes');
    is(main::Wattpilot_FormatReadingValue('diag_fbuf_p_grid', 1.236),
        '1.24',
        'numeric diagnostics round to two decimal places');
    is(main::Wattpilot_FormatReadingValue('diag_fbuf_p_grid', -0.004),
        '0.00',
        'numeric diagnostics normalize rounded negative zero');
    is(main::Wattpilot_FormatReadingValue('diag_fbuf_p_ac_total', 'raw'),
        'raw',
        'diagnostic strings remain unchanged');
    is(main::Wattpilot_FormatReadingValue(
            'diag_fbuf_ohmpilot_state', JSON::true()),
        1,
        'diagnostic booleans remain zero-or-one values');
    is(main::Wattpilot_FormatReadingValue('auth_hash_mode', 'pbkdf2'),
        'pbkdf2',
        'event-sourced enum text also uses the central formatter safely');
    my $unknown_error = eval {
        main::Wattpilot_FormatReadingValue('not_a_public_reading', 1);
        '';
    };
    like($@, qr/Unknown Wattpilot reading key/,
        'unknown reading keys cannot silently bypass central formatting');
};

subtest 'fullStatus formats physical readings without changing discrete settings' => sub {
    my $hash = fresh_device();
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fst => 1400,
        spl3 => 6900.5,
        eto => 123456,
        wh => 7,
        nrg => nrg_values(),
        amp => 16,
        amt => 15,
        fam => 80,
        mpwst => 1500,
    }), 'representative fullStatus is accepted');

    my %expected = (
        configPvSurplusStartPower => '1400.00',
        configThreePhaseSwitchPower => '6900.50',
        energyTotal => '123.46',
        energySincePlugIn => '7.00',
        voltageL1 => '230.00',
        voltageL2 => '231.20',
        voltageL3 => '232.35',
        currentL1 => '6.00',
        currentL2 => '6.25',
        currentL3 => '6.26',
        powerL1 => '1380.00',
        powerL2 => '1443.75',
        powerL3 => '1454.98',
        power => '0.00',
    );
    for my $reading (sort keys %expected) {
        is(reading_value($hash, $reading), $expected{$reading},
            "$reading has its exact public string format");
    }

    is(reading_value($hash, 'configChargingCurrent'), 16,
        'integer charging-current configuration remains integral');
    is(reading_value($hash, 'temperatureCurrentLimit'), 15,
        'integer runtime current limit remains an explicit integral exception');
    is(reading_value($hash, 'configPvBatteryChargeAboveSoC'), 80,
        'percentage configuration remains an explicit percentage exception');
    is(reading_value($hash, 'configPhaseSwitchDelay'), 1.5,
        'duration configuration retains its seconds representation');
};

subtest 'deltaStatus and matched response use the same formatting path' => sub {
    my $hash = fresh_device();
    ok(parse_status($hash, 'fullStatus', {
        car => 2,
        fst => 1000,
        spl3 => 5000,
        nrg => nrg_values(),
    }), 'baseline fullStatus is accepted');

    ok(parse_status($hash, 'deltaStatus', {
        fst => 1500.555,
        spl3 => 6000.555,
    }), 'fractional deltaStatus is accepted');
    is(reading_value($hash, 'configPvSurplusStartPower'), '1500.56',
        'deltaStatus start power uses two decimals');
    is(reading_value($hash, 'configThreePhaseSwitchPower'), '6000.56',
        'deltaStatus switching power uses two decimals');

    $DevIo::NOW = 2_000;
    $hash->{helper}{pendingRequests}{7} = {
        key => 'syntheticPrecisionReadback', sentAt => $DevIo::NOW,
    };
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'response',
        requestId => 7,
        success => JSON::true(),
        status => {
            fst => 1e3,
            spl3 => 7000,
        },
    })), 'matched response status is accepted');
    is(reading_value($hash, 'configPvSurplusStartPower'), '1000.00',
        'scientific numeric response input formats identically');
    is(reading_value($hash, 'configThreePhaseSwitchPower'), '7000.00',
        'whole response input retains trailing zeroes');
};

subtest 'fresh initialization and invalid input preserve the public contract' => sub {
    my $first = fresh_device();
    ok(parse_status($first, 'fullStatus', {
        car => 2, fst => 1550.5, spl3 => 5200.5,
        nrg => nrg_values(),
    }), 'first initialization is accepted');

    my $second = fresh_device();
    ok(parse_status($second, 'fullStatus', {
        car => 2, fst => 1550.5, spl3 => 5200.5,
        nrg => nrg_values(),
    }), 'fresh post-reconnect initialization is accepted');
    for my $reading (qw(
        configPvSurplusStartPower configThreePhaseSwitchPower
        voltageL1 currentL1 power
    )) {
        is(reading_value($second, $reading), reading_value($first, $reading),
            "$reading is formatted identically after fresh initialization");
    }

    ok(parse_status($second, 'deltaStatus', {
        fst => '1000',
        spl3 => '5200.5',
    }), 'type-invalid numeric strings are processed safely');
    is(reading_value($second, 'configPvSurplusStartPower'), '1550.50',
        'invalid start power preserves the confirmed reading');
    is(reading_value($second, 'configThreePhaseSwitchPower'), '5200.50',
        'invalid switching power preserves the confirmed reading');
};

done_testing;
