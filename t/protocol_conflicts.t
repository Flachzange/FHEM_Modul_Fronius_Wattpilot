use strict;
use warnings;

use File::Spec;
use FindBin qw($Bin);
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir($Bin, '..'));

sub slurp_utf8 {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

my $doc = slurp_utf8(File::Spec->catfile($root, 'docs', 'WATTPILOT-FLEX-JSON-API.md'));
my $sources = slurp_utf8(File::Spec->catfile($root, 'docs', 'PROTOCOL-SOURCES.md'));

like($doc, qr/^## Known evidence conflicts$/m,
    'protocol reference contains a dedicated known-conflicts section');
like($doc, qr/4712ba3b8409fda55303870c047038b1b221d7ff/,
    'protocol reference pins the older Wattpilot source revision');
like($doc, qr/498aa8709f198fcde2b41159ad99dc02e57accc9/,
    'protocol reference pins the second Wattpilot source revision');
like($doc, qr/^\| `frc` \| number \| `0` \|[^\n]*0 Neutral[^\n]*1 Off[^\n]*2 On/m,
    'frc field row retains the conflicting Neutral/Off/On candidate');
like($doc, qr/^\| `amp` \| number \| `32` \|[^\n]*6.{0,3}16/m,
    'amp field row retains the older 6-16 range conflict');
like($doc, qr/Issue #8 targets validation of the current public command to 6.{0,3}32 A/,
    'amp conflict retains the planned 6-32 public range separately');

like($sources, qr/^## Known field-level conflicts$/m,
    'protocol provenance register preserves field-level conflicts');
like($sources, qr/`frc`:[^\n]*4712ba3b8409fda55303870c047038b1b221d7ff[^\n]*498aa8709f198fcde2b41159ad99dc02e57accc9/,
    'provenance register pins both frc conflict sources');
like($sources, qr/`amp`:[^\n]*6.{0,3}16[^\n]*Issue #8[^\n]*6.{0,3}32/,
    'provenance register retains the amp model and range conflict');

done_testing;
