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
    my $hash = {
        NAME => 'controlWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000044',
        DeviceName => 'ws:192.0.2.44:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-control-key';
    return $hash;
}

sub inner_payload {
    my ($write) = @_;
    my $outer = decode_json($write->[1]);
    return ($outer, decode_json($outer->{data}));
}

sub reading_value {
    my ($hash, $name) = @_;
    return $hash->{READINGS}{$name}{VAL};
}

my $hash = fresh_device();
ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'fullStatus',
    status => {
        fup => JSON::true,
        fzf => JSON::false,
        frm => 0,
        psm => 0,
        spl3 => 5200,
        mpwst => 120000,
        mptwt => 600000,
        fmt => 300000,
        fap => JSON::true,
        mcpd => 120000,
        mci => 0,
    },
})), 'fullStatus with verified control fields is accepted');

my %expected = (
    configPvSurplusEnabled => 1,
    configZeroFeedInEnabled => 0,
    configPvControlPreference => 'preferFromGrid',
    configPhaseSwitchMode => 'auto',
    configThreePhaseSwitchPower => '5200.00',
    configPhaseSwitchDelay => 120,
    configMinimumPhaseSwitchInterval => 600,
    configMinimumChargeTime => 300,
    configChargingPauseAllowed => 1,
    configMinimumChargingPauseDuration => 120,
    configMinimumChargingInterval => 0,
);
for my $reading (sort keys %expected) {
    is(reading_value($hash, $reading), $expected{$reading},
        "$reading is exposed with the public unit and value");
}

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus',
    status => {
        fup => JSON::false,
        fzf => JSON::true,
        frm => 2,
        psm => 2,
        spl3 => 6900.5,
        mpwst => 1500,
        mptwt => 2500,
        fmt => 500,
        fap => JSON::false,
        mcpd => 1250,
        mci => 750,
    },
})), 'deltaStatus updates every verified control field');
is(reading_value($hash, 'configPvSurplusEnabled'), 0,
    'boolean false becomes public 0');
is(reading_value($hash, 'configZeroFeedInEnabled'), 1,
    'boolean true becomes public 1');
is(reading_value($hash, 'configPvControlPreference'), 'preferToGrid',
    'frm=2 maps to preferToGrid');
is(reading_value($hash, 'configPhaseSwitchMode'), 'force3',
    'psm=2 maps to force3');
is(reading_value($hash, 'configThreePhaseSwitchPower'), '6900.50',
    'three-phase threshold preserves a confirmed decimal watt value');
is(reading_value($hash, 'configPhaseSwitchDelay'), 1.5,
    'phase-switch delay converts milliseconds to seconds');
is(reading_value($hash, 'configMinimumPhaseSwitchInterval'), 2.5,
    'phase-switch interval converts milliseconds to seconds');
is(reading_value($hash, 'configMinimumChargeTime'), 0.5,
    'minimum charge time converts milliseconds to seconds');
is(reading_value($hash, 'configChargingPauseAllowed'), 0,
    'charging-pause false becomes public 0');
is(reading_value($hash, 'configMinimumChargingPauseDuration'), 1.25,
    'minimum charging-pause duration converts milliseconds to seconds');
is(reading_value($hash, 'configMinimumChargingInterval'), 0.75,
    'minimum charging interval converts milliseconds to seconds');

main::Wattpilot_UpdateReadings($hash, { frm => 77, psm => -1 });
is(reading_value($hash, 'configPvControlPreference'), 'unknown:77',
    'unknown frm value remains explicit');
is(reading_value($hash, 'configPhaseSwitchMode'), 'unknown:-1',
    'unknown psm value remains explicit');

my %stable = map { $_ => reading_value($hash, $_) } keys %expected;
for my $case (
    [ 'missing', {} ],
    [ 'null', { fup => undef, spl3 => undef, mpwst => undef } ],
    [ 'wrong boolean', { fup => 2 } ],
    [ 'wrong enum type', { frm => 'default' } ],
    [ 'negative power', { spl3 => -1 } ],
    [ 'negative duration', { fmt => -1 } ],
    [ 'text duration', { mcpd => 'invalid' } ],
    [ 'overflow', { mci => '1e9999' } ],
) {
    my ($label, $status) = @$case;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'deltaStatus', status => $status,
    })), "$label delta is processed safely");
    for my $reading (sort keys %stable) {
        is(reading_value($hash, $reading), $stable{$reading},
            "$label delta leaves $reading unchanged");
    }
}

for my $case (
    [ 'pvSurplusEnabled', 1, 'fup', 1, 'boolean' ],
    [ 'pvSurplusEnabled', 0, 'fup', 0, 'boolean' ],
    [ 'zeroFeedInEnabled', 1, 'fzf', 1, 'boolean' ],
    [ 'chargingPauseAllowed', 0, 'fap', 0, 'boolean' ],
    [ 'pvControlPreference', 'preferFromGrid', 'frm', 0, 'number' ],
    [ 'pvControlPreference', 'default', 'frm', 1, 'number' ],
    [ 'pvControlPreference', 'preferToGrid', 'frm', 2, 'number' ],
    [ 'phaseSwitchMode', 'auto', 'psm', 0, 'number' ],
    [ 'phaseSwitchMode', 'force1', 'psm', 1, 'number' ],
    [ 'phaseSwitchMode', 'force3', 'psm', 2, 'number' ],
    [ 'threePhaseSwitchPower', '5200.5', 'spl3', 5200.5, 'number' ],
    [ 'phaseSwitchDelay', '1.5', 'mpwst', 1500, 'number' ],
    [ 'minimumPhaseSwitchInterval', 600, 'mptwt', 600000, 'number' ],
    [ 'minimumChargeTime', 0.5, 'fmt', 500, 'number' ],
    [ 'minimumChargingPauseDuration', 120, 'mcpd', 120000, 'number' ],
    [ 'minimumChargingInterval', 0, 'mci', 0, 'number' ],
) {
    my ($command, $input, $key, $value, $kind) = @$case;
    $hash = fresh_device();
    is(main::Wattpilot_Set($hash, 'controlWallbox', $command, $input), undef,
        "$command accepts $input");
    my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{key}, $key, "$command writes $key");
    if ($kind eq 'boolean') {
        ok(JSON::is_bool($inner->{value}),
            "$command sends a JSON boolean rather than a numeric surrogate");
        is($inner->{value} ? 1 : 0, $value,
            "$command sends the expected boolean value");
    } else {
        is($inner->{value}, $value,
            "$command sends the expected protocol value");
    }
    is($outer->{requestId}, '1sm',
        "$command uses the normal secured request correlation");
}

for my $case (
    [ 'pvSurplusEnabled', 1 ],
    [ 'zeroFeedInEnabled', 0 ],
    [ 'chargingPauseAllowed', 1 ],
    [ 'pvControlPreference', 'default' ],
    [ 'phaseSwitchMode', 'auto' ],
    [ 'threePhaseSwitchPower', 5200 ],
    [ 'phaseSwitchDelay', 120 ],
    [ 'minimumPhaseSwitchInterval', 600 ],
    [ 'minimumChargeTime', 300 ],
    [ 'minimumChargingPauseDuration', 120 ],
    [ 'minimumChargingInterval', 0 ],
) {
    my ($command, $input) = @$case;
    $hash = fresh_device();
    like(main::Wattpilot_Set(
            $hash, 'controlWallbox', $command, $input, 'extra'),
        qr/^Usage:/, "$command rejects an extra argument");
    is(scalar @DevIo::WRITES, 0,
        "$command extra argument sends no frame");
}

for my $case (
    [ 'pvSurplusEnabled', 2 ],
    [ 'zeroFeedInEnabled', 'true' ],
    [ 'chargingPauseAllowed', -1 ],
    [ 'pvControlPreference', 'grid' ],
    [ 'phaseSwitchMode', 'force2' ],
    [ 'threePhaseSwitchPower', -1 ],
    [ 'threePhaseSwitchPower', 'NaN' ],
    [ 'phaseSwitchDelay', -1 ],
    [ 'phaseSwitchDelay', '0.0001' ],
    [ 'minimumPhaseSwitchInterval', 'Inf' ],
    [ 'minimumChargeTime', 'abc' ],
    [ 'minimumChargingPauseDuration', '1e9999' ],
    [ 'minimumChargingInterval', undef ],
) {
    my ($command, $input) = @$case;
    $hash = fresh_device();
    my @args = ('controlWallbox', $command);
    push @args, $input if defined $input;
    like(main::Wattpilot_Set($hash, @args), qr/^Usage:/,
        "$command rejects invalid input");
    is(scalar @DevIo::WRITES, 0,
        "$command invalid input sends no frame");
}

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { spl3 => 5200 });
main::Wattpilot_Set($hash, 'controlWallbox', 'threePhaseSwitchPower', 6000);
is(reading_value($hash, 'configThreePhaseSwitchPower'), '5200.00',
    'pending setter does not fabricate a confirmed reading');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { spl3 => 6000 },
}));
is(reading_value($hash, 'configThreePhaseSwitchPower'), '6000.00',
    'successful response updates the reading through the status path');
is(reading_value($hash, 'lastCommandStatus'), 'success',
    'successful control response completes the request');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { fup => JSON::true });
main::Wattpilot_Set($hash, 'controlWallbox', 'pvSurplusEnabled', 0);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::false,
}));
is(reading_value($hash, 'configPvSurplusEnabled'), 1,
    'failed response leaves the confirmed boolean reading unchanged');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'failed control response is terminal');

$hash = fresh_device();
my $help = main::Wattpilot_Set($hash, 'controlWallbox', '?');
for my $command (qw(
    pvSurplusEnabled zeroFeedInEnabled pvControlPreference phaseSwitchMode
    threePhaseSwitchPower phaseSwitchDelay minimumPhaseSwitchInterval
    minimumChargeTime chargingPauseAllowed minimumChargingPauseDuration
    minimumChargingInterval
)) {
    like($help, qr/\Q$command\E/, "Set help exposes $command");
}

done_testing;
