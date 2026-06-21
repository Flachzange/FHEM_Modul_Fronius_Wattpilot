package FHEM::Meta;

use strict;
use warnings;

our @INIT_MOD_CALLS;

sub InitMod {
    push @INIT_MOD_CALLS, [@_];
    return undef;
}

1;
