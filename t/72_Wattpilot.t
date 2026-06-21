use strict;
use warnings;

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

for my $slot (qw(DefFn UndefFn SetFn GetFn AttrFn ReadFn ReadyFn)) {
    ok(ref($registration{$slot}) eq 'CODE', "$slot registers an existing callback");
}

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

