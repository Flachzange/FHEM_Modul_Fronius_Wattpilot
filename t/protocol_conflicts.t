use strict;
use warnings;
use File::Spec;
use FindBin qw($Bin);
use Test::More;

sub read_text {
    my ($name) = @_;
    my $path = File::Spec->catfile($Bin, '..', 'docs', $name);
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}

my $api = read_text('WATTPILOT-FLEX-JSON-API.md');
my $conflicts = read_text('PROTOCOL-CONFLICTS.md');

like($api, qr/^## Known evidence conflicts$/m, 'known-conflicts section is present');
like($api, qr/4712ba3b[0-9a-f]{32}/, 'first pinned source revision remains documented');
like($api, qr/498aa870[0-9a-f]{32}/, 'second pinned source revision remains documented');
like($api, qr/^\| `frc` \| number \| `0` \|[^\n]*Neutral[^\n]*Off[^\n]*On/m,
    'frc table row preserves the conflicting enum candidate');
like($api, qr/^\| `amp` \| number \| `32` \|[^\n]*6.{0,3}16/m,
    'amp table row preserves the older range candidate');
like($api, qr/Issue #8[^\n]*6.{0,3}32 A/, 'planned amp range remains separate');
like($conflicts, qr/^# Known Wattpilot protocol evidence conflicts$/m,
    'dedicated conflict document is present');
like($conflicts, qr/0=Neutral.*1=Off.*2=On/s, 'frc disagreement is preserved');
like($conflicts, qr/6.{0,3}16 A.*6.{0,3}32 A/s, 'amp disagreement is preserved');

done_testing;
