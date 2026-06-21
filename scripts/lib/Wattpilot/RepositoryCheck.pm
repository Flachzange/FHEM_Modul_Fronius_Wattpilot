package Wattpilot::RepositoryCheck;

use strict;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(contains_mojibake);

sub contains_mojibake {
    my ($text) = @_;
    return 0 unless defined $text;

    return $text =~ /(?:
        \x{00C3}
        | \x{00C2}
        | \x{00E2}\x{20AC}
        | \x{00EF}\x{00BF}\x{00BD}
        | \x{FFFD}
    )/x ? 1 : 0;
}

1;
