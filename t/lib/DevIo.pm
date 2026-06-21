package DevIo;

use strict;
use warnings;

sub import {
    my ($class) = @_;
    my $caller = caller;

    $main::readingFnAttributes = '' unless defined $main::readingFnAttributes;

    no strict 'refs';
    for my $name (qw(
        DevIo_CloseDev DevIo_IsOpen DevIo_OpenDev DevIo_SimpleRead
        DevIo_SimpleWrite Log3 AttrVal InternalTimer RemoveInternalTimer
        gettimeofday readingsSingleUpdate readingsBeginUpdate
        readingsBulkUpdate readingsEndUpdate getKeyValue setKeyValue
    )) {
        *{"${caller}::$name"} = \&{$name};
    }

    *{"${caller}::readingFnAttributes"} = \$main::readingFnAttributes;
    *{"${caller}::modules"} = \%main::modules;
    *{"${caller}::defs"} = \%main::defs;
}

sub DevIo_CloseDev { return }
sub DevIo_IsOpen { return 0 }
sub DevIo_OpenDev { return }
sub DevIo_SimpleRead { return undef }
sub DevIo_SimpleWrite { return }
sub Log3 { return }
sub AttrVal { return $_[2] }
sub InternalTimer { return }
sub RemoveInternalTimer { return }
sub gettimeofday { return time }
sub readingsSingleUpdate { return }
sub readingsBeginUpdate { return }
sub readingsBulkUpdate { return }
sub readingsEndUpdate { return }
sub getKeyValue { return (undef, undef) }
sub setKeyValue { return undef }

1;
