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
    DevIo::reset_test_state();
    %defs = ();
    %attr = ();
    my $hash = {
        NAME => 'schemaWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000064',
        DeviceName => 'ws:192.0.2.64:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-schema-key';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return decode_json($outer->{data});
}

my $interface = main::Wattpilot_InterfaceSnapshot();
my $commands = $interface->{commands};
my $command_schema = $interface->{commandSchema};
my $grouped_command_schema = $interface->{groupedCommandSchema};
my $status_fields = $interface->{statusFields};
my $reading_policy = $interface->{readingPolicy};

is_deeply([sort keys %$command_schema], [sort keys %$commands],
    'every public Set command has exactly one schema entry');
is(scalar(keys %$command_schema), 14,
    'command schema contains the complete 14-command public surface');
is(scalar(keys %$status_fields), 68,
    'status schema contains all 68 consumed protocol fields');
is_deeply(
    [sort grep { $command_schema->{$_}{parser} eq 'special' }
        keys %$command_schema],
    [qw(minimum_charging password phase_switch pv_battery reconnect)],
    'only grouped commands, password, pvBattery, and reconnect remain explicit Set handlers');

my (@command_schema_errors, %seen_public_name);
for my $key (sort keys %$command_schema) {
    my $schema = $command_schema->{$key};
    push @command_schema_errors, "$key name mismatch"
        if $schema->{name} ne $commands->{$key};
    push @command_schema_errors, "duplicate $schema->{name}"
        if $seen_public_name{$schema->{name}}++;
    next if $schema->{parser} eq 'special';
    push @command_schema_errors, "$key missing protocol key"
        if $schema->{protocolKey} eq 'none';
    push @command_schema_errors, "$key missing usage"
        if $schema->{usage} eq 'none';
}
is_deeply(\@command_schema_errors, [],
    'ordinary command schema metadata is complete and public names are unique');

my @ordinary_cases = (
    [force_state => 'on', 'frc', 2, 'number'],
    [charging_current => '16', 'amp', 16, 'number'],
    [charging_mode => 'eco', 'lmo', 4, 'number'],
    [pv_surplus_start_power => '1400.5', 'fst', 1400.5, 'number'],
    [pv_surplus_enabled => '1', 'fup', 1, 'boolean'],
    [zero_feed_in_enabled => '0', 'fzf', 0, 'boolean'],
    [pv_control_preference => 'default', 'frm', 1, 'number'],
    [charging_pause_allowed => '1', 'fap', 1, 'boolean'],
    [next_trip_time => '07:30', 'ftt', 27000, 'number'],
);

for my $case (@ordinary_cases) {
    my ($key, $input, $protocol_key, $expected, $kind) = @$case;
    my $schema = $command_schema->{$key};
    my $hash = fresh_device();
    is(main::Wattpilot_Set(
            $hash, $hash->{NAME}, $schema->{name}, $input),
        undef, "$schema->{name} accepts its schema-defined value");
    my $payload = inner_payload($DevIo::WRITES[0]);
    is($payload->{key}, $protocol_key,
        "$schema->{name} sends its schema-defined protocol key");
    if ($kind eq 'boolean') {
        ok(JSON::is_bool($payload->{value}),
            "$schema->{name} retains JSON boolean output type");
        is($payload->{value} ? 1 : 0, $expected,
            "$schema->{name} sends the expected boolean value");
    }
    else {
        is($payload->{value}, $expected,
            "$schema->{name} sends the expected numeric value");
    }

    $hash = fresh_device();
    like(main::Wattpilot_Set(
            $hash, $hash->{NAME}, $schema->{name}, $input, 'extra'),
        qr/^Usage:/, "$schema->{name} rejects an extra argument");
    is(scalar @DevIo::WRITES, 0,
        "$schema->{name} arity failure sends no frame");
}

is_deeply([sort keys %$grouped_command_schema],
    [qw(minimum_charging phase_switch)],
    'exactly the two requested grouped Set schemas are public');
is_deeply([sort keys %{$grouped_command_schema->{minimum_charging}}],
    [qw(duration interval pauseDuration)],
    'minimumCharging exposes the requested subcommands');
is_deeply([sort keys %{$grouped_command_schema->{phase_switch}}],
    [qw(delay minInterval mode threePhasePower)],
    'phaseSwitch exposes the requested subcommands');

my @grouped_cases = (
    [minimum_charging => duration => '0.5', 'fmt', 500],
    [minimum_charging => interval => '0', 'mci', 0],
    [minimum_charging => pauseDuration => '1.25', 'mcpd', 1250],
    [phase_switch => delay => '1.5', 'mpwst', 1500],
    [phase_switch => mode => 'force3', 'psm', 2],
    [phase_switch => minInterval => '2.5', 'mptwt', 2500],
    [phase_switch => threePhasePower => '5200.5', 'spl3', 5200.5],
);
for my $case (@grouped_cases) {
    my ($group_key, $setting, $input, $protocol_key, $expected) = @$case;
    my $group_name = $commands->{$group_key};
    my $hash = fresh_device();
    is(main::Wattpilot_Set(
            $hash, $hash->{NAME}, $group_name, $setting, $input),
        undef, "$group_name $setting accepts its schema-defined value");
    my $payload = inner_payload($DevIo::WRITES[0]);
    is($payload->{key}, $protocol_key,
        "$group_name $setting sends its schema-defined protocol key");
    is($payload->{value}, $expected,
        "$group_name $setting sends the expected protocol value");

    $hash = fresh_device();
    like(main::Wattpilot_Set(
            $hash, $hash->{NAME}, $group_name, $setting, $input, 'extra'),
        qr/^Usage:/, "$group_name $setting rejects an extra argument");
    is(scalar @DevIo::WRITES, 0,
        "$group_name $setting arity failure sends no frame");
}

for my $case (
    [minimum_charging => 'duration', 'invalid'],
    [minimum_charging => 'unknown', '1'],
    [phase_switch => 'mode', 'force2'],
    [phase_switch => 'delay', '-1'],
    [phase_switch => 'threePhasePower', '-1'],
) {
    my ($group_key, $setting, $input) = @$case;
    my $group_name = $commands->{$group_key};
    my $hash = fresh_device();
    like(main::Wattpilot_Set(
            $hash, $hash->{NAME}, $group_name, $setting, $input),
        qr/^Usage:/, "$group_name rejects invalid $setting input");
    is(scalar @DevIo::WRITES, 0,
        "$group_name invalid input sends no frame");
}

my @actual_options = sort split / /, main::Wattpilot_SetOptions();
my @expected_options = sort map {
    my $schema = $command_schema->{$_};
    $schema->{name}
        . ($schema->{widget} eq 'none' ? '' : ':' . $schema->{widget});
} keys %$command_schema;
is_deeply(\@actual_options, \@expected_options,
    'Set discovery is generated entirely from command schema metadata');

my %valid_for_kind = (
    integer => 7,
    nonnegative_integer => 2,
    number => -12.5,
    nonnegative_number => 12.5,
    percentage => 42.5,
    clock_seconds => 3600,
    boolean => JSON::true,
    nrg => [1 .. 12],
    string => 'synthetic',
    nonempty_string => 'synthetic',
    raw_scalar => 12.3456789,
);
my %invalid_for_kind = (
    integer => '7',
    nonnegative_integer => -1,
    number => 'invalid',
    nonnegative_number => -1,
    percentage => 101,
    clock_seconds => 1,
    boolean => 1,
    nrg => [1, 2],
    string => [],
    nonempty_string => '',
    raw_scalar => {},
);
sub status_with_source {
    my ($source, $value) = @_;
    return { $source => $value }
        if $source =~ /^[A-Za-z0-9_]+$/;
    if ($source =~ /^([A-Za-z0-9_]+)\[(\d+)\]$/) {
        my ($root, $index) = ($1, $2);
        my @values = (undef) x ($index + 1);
        $values[$index] = $value;
        return { $root => \@values };
    }
    if ($source =~ /^([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)$/) {
        return { $1 => { $2 => $value } };
    }
    die "Unsupported test status source: $source";
}

$attr{schemaWallbox}{diagnosticReadings} = 1;
my (@valid_failures, @invalid_failures, @mapping_errors);
for my $protocol_key (sort keys %$status_fields) {
    my $field = $status_fields->{$protocol_key};
    my $kind = $field->{kind};
    my $valid = main::Wattpilot_NormalizeStatus(
        { NAME => 'schemaWallbox' },
        status_with_source($protocol_key, $valid_for_kind{$kind}));
    push @valid_failures, $protocol_key
        if !exists $valid->{$protocol_key};
    my $invalid = main::Wattpilot_NormalizeStatus(
        { NAME => 'schemaWallbox' },
        status_with_source($protocol_key, $invalid_for_kind{$kind}));
    push @invalid_failures, $protocol_key
        if exists $invalid->{$protocol_key};
    push @mapping_errors, "$protocol_key has no readings"
        if !@{$field->{readings}};
    for my $reading_key (@{$field->{readings}}) {
        my $policy = $reading_policy->{$reading_key};
        push @mapping_errors, "$reading_key source mismatch"
            if $policy->{source}
                !~ /^status:\Q$protocol_key\E(?:\[\d+\])?$/;
        push @mapping_errors, "$reading_key missing validator"
            if $policy->{validator} eq 'none';
    }
}
is_deeply(\@valid_failures, [],
    'every status-field schema accepts its valid sample');
is_deeply(\@invalid_failures, [],
    'every status-field schema rejects its invalid sample');
is_deeply(\@mapping_errors, [],
    'status fields and public reading policies form one complete mapping');

my %enum_sample = (
    car => [1, 'idle'],
    force => [1, 'off'],
    charging_mode => [3, 'default'],
    charging_decision => [0, 'notChargingBecauseNoChargeCtrlData'],
    pv_control => [1, 'default'],
    phase_switch => [1, 'force1'],
);
my (%actual_formatter, %expected_formatter);
for my $reading_key (sort keys %$reading_policy) {
    my $policy = $reading_policy->{$reading_key};
    next if $policy->{source} !~ /^status:/;
    next if $policy->{publication} eq 'interval';

    my ($sample, $expected);
    if ($policy->{formatter} eq 'enum') {
        ($sample, $expected) = @{$enum_sample{$policy->{detail}}};
    }
    elsif ($policy->{formatter} eq 'boolean') {
        ($sample, $expected) = (JSON::true, 1);
    }
    elsif ($policy->{formatter} eq 'integer') {
        ($sample, $expected) = (7, 7);
    }
    elsif ($policy->{formatter} eq 'seconds') {
        ($sample, $expected) = (1500, 1.5);
    }
    elsif ($policy->{formatter} eq 'clock') {
        ($sample, $expected) = $policy->{detail} eq 'end_of_day'
            ? (86400, '24:00')
            : (3600, '01:00');
    }
    elsif ($policy->{formatter} eq 'decimal2') {
        ($sample, $expected) = (12.5, '12.50');
    }
    else {
        ($sample, $expected) = (12.5, 12.5);
    }
    $actual_formatter{$reading_key} =
        main::Wattpilot_FormatReadingValue($reading_key, $sample);
    $expected_formatter{$reading_key} = $expected;
}
is_deeply(\%actual_formatter, \%expected_formatter,
    'every immediate status reading executes the central schema-defined formatter');

done_testing;
