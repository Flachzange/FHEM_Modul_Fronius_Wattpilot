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
        NAME => 'pvStartWallbox',
        TYPE => 'Wattpilot',
        FUUID => '00000000-0000-0000-0000-000000000043',
        DeviceName => 'ws:192.0.2.43:80/ws',
        STATE => 'connected',
        TEST_OPEN => 1,
        helper => { authenticated => 1 },
    };
    $defs{$hash->{NAME}} = $hash;
    $modules{Wattpilot}{defptr}{$hash->{NAME}} = $hash;
    $DevIo::KEY_VALUES{'Wattpilot_' . $hash->{FUUID} . '_passwordhash'} =
        'synthetic-pv-start-key';
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
    type => 'fullStatus', partial => JSON::false,
    status => { fst => 1400 },
})), 'fullStatus with fst is accepted');
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'fullStatus exposes fst as configPvSurplusStartPower');

ok(main::Wattpilot_Parse($hash, encode_json({
    type => 'deltaStatus', status => { fst => 1550.5 },
})), 'deltaStatus with decimal fst is accepted');
is(reading_value($hash, 'configPvSurplusStartPower'), 1550.5,
    'deltaStatus preserves the device-confirmed decimal value');

for my $case (
    [ 'missing', {} ],
    [ 'null', { fst => undef } ],
    [ 'negative', { fst => -1 } ],
    [ 'text', { fst => 'not-a-number' } ],
    [ 'array', { fst => [] } ],
    [ 'overflow', { fst => '1e9999' } ],
) {
    my ($label, $status) = @$case;
    ok(main::Wattpilot_Parse($hash, encode_json({
        type => 'deltaStatus', status => $status,
    })), "$label delta is processed safely");
    is(reading_value($hash, 'configPvSurplusStartPower'), 1550.5,
        "$label delta leaves the existing start-power reading unchanged");
}

for my $case (
    [ 0, 0 ],
    [ 1400, 1400 ],
    [ '1500.5', 1500.5 ],
    [ '1e3', 1000 ],
) {
    my ($input, $expected) = @$case;
    $hash = fresh_device();
    is(main::Wattpilot_Set(
        $hash, 'pvStartWallbox', 'pvSurplusStartPower', $input),
        undef, "pvSurplusStartPower Set accepts $input");
    my ($outer, $inner) = inner_payload($DevIo::WRITES[0]);
    is($inner->{key}, 'fst', 'setter writes the fst protocol key');
    is($inner->{value}, $expected,
        "setter encodes $input as the expected finite numeric value");
    is($outer->{requestId}, '1sm',
        'setter uses the normal secured request correlation');
}

$hash = fresh_device();
like(main::Wattpilot_Set(
        $hash, 'pvStartWallbox', 'pvSurplusStartPower', 1400, 'extra'),
    qr/^Usage:/,
    'pvSurplusStartPower Set rejects an extra argument');
is(scalar @DevIo::WRITES, 0,
    'extra pvSurplusStartPower Set argument sends no frame');

for my $invalid (undef, -1, 'NaN', 'Inf', '-Inf', 'abc', '1e9999') {
    $hash = fresh_device();
    my @args = ('pvStartWallbox', 'pvSurplusStartPower');
    push @args, $invalid if defined $invalid;
    like(main::Wattpilot_Set($hash, @args), qr/<watts>/,
        'invalid or missing pvSurplusStartPower Set value is rejected');
    is(scalar @DevIo::WRITES, 0,
        'rejected pvSurplusStartPower Set value sends no frame');
}

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { fst => 1400 });
is(main::Wattpilot_Set(
    $hash, 'pvStartWallbox', 'pvSurplusStartPower', 1600),
    undef, 'valid write is queued');
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'pending write does not optimistically fabricate the reading');
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { fst => 1600 },
}));
is(reading_value($hash, 'configPvSurplusStartPower'), 1600,
    'successful response updates the reading through the normal status path');
is(reading_value($hash, 'lastCommandStatus'), 'success',
    'successful setter response completes the request');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { fst => 1400 });
main::Wattpilot_Set($hash, 'pvStartWallbox', 'pvSurplusStartPower', 1700);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::false,
    message => 'synthetic rejection detail',
}));
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'failed response does not fabricate the requested start power');
is(reading_value($hash, 'lastCommandStatus'), 'failed',
    'device rejection is exposed through command status');
is(reading_value($hash, 'lastCommandError'), 'device rejected fst',
    'device rejection identifies the fst key without exposing payload details');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { fst => 1400 });
main::Wattpilot_Set($hash, 'pvStartWallbox', 'pvSurplusStartPower', 1800);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { amp => 16 },
}));
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'successful response without fst leaves the prior reading unchanged');

$hash = fresh_device();
main::Wattpilot_UpdateReadings($hash, { fst => 1400 });
main::Wattpilot_Set($hash, 'pvStartWallbox', 'pvSurplusStartPower', 1900);
main::Wattpilot_Parse($hash, encode_json({
    type => 'response', requestId => 1, success => JSON::true,
    status => { fst => 'invalid' },
}));
is(reading_value($hash, 'configPvSurplusStartPower'), 1400,
    'type-invalid confirmed status cannot replace the previous reading');

done_testing;
