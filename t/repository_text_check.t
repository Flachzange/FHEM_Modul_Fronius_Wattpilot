use strict;
use warnings;
use utf8;

use lib 'scripts/lib';
use Test::More;
use Wattpilot::RepositoryCheck qw(contains_mojibake);

my @invalid = (
    [ 'original-author mojibake', "urspr\x{00C3}\x{00BC}nglicher" ],
    [ 'byte-equality mojibake', "Bytegleichheitspr\x{00C3}\x{00BC}fungen" ],
    [ 'uppercase A umlaut mojibake', "\x{00C3}\x{201E}" ],
    [ 'uppercase O umlaut mojibake', "\x{00C3}\x{2013}" ],
    [ 'uppercase U umlaut mojibake', "\x{00C3}\x{0153}" ],
    [ 'en dash mojibake', "\x{00E2}\x{20AC}\x{201C}" ],
    [ 'em dash mojibake', "\x{00E2}\x{20AC}\x{201D}" ],
    [ 'truncated punctuation mojibake', "\x{00E2}\x{20AC}" ],
    [ 'degree-sign mojibake', "\x{00C2}\x{00B0}" ],
    [ 'Unicode replacement character', "\x{FFFD}" ],
);

for my $case (@invalid) {
    ok(contains_mojibake($case->[1]), "detects $case->[0]");
}

my @valid = (
    [ 'original author', 'ursprünglicher' ],
    [ 'byte-equality checks', 'Bytegleichheitsprüfungen' ],
    [ 'German letters', 'ÄÖÜäöüß' ],
    [ 'Unicode dashes', 'Gedankenstrich – und Geviertstrich —' ],
);

for my $case (@valid) {
    ok(!contains_mojibake($case->[1]), "accepts $case->[0]");
}

done_testing;
