package DevIo;

use strict;
use warnings;

our (%KEY_VALUES, %ATTR_VALUES, %GET_KEY_ERRORS, %SET_KEY_ERRORS);
our (@LOGS, @WRITES, @CLOSES, @TIMERS, @REMOVED_TIMERS, @KEY_OPERATIONS, @READING_UPDATES);

sub reset_test_state {
    %KEY_VALUES = ();
    %ATTR_VALUES = ();
    %GET_KEY_ERRORS = ();
    %SET_KEY_ERRORS = ();
    @LOGS = ();
    @WRITES = ();
    @CLOSES = ();
    @TIMERS = ();
    @REMOVED_TIMERS = ();
    @KEY_OPERATIONS = ();
    @READING_UPDATES = ();
}

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

sub DevIo_CloseDev { push @CLOSES, $_[0]; return }
sub DevIo_IsOpen { return 0 }
sub DevIo_OpenDev { return }
sub DevIo_SimpleRead { return undef }
sub DevIo_SimpleWrite { push @WRITES, [@_]; return }
sub Log3 { push @LOGS, [@_]; return }
sub AttrVal { return exists $ATTR_VALUES{"$_[0]|$_[1]"} ? $ATTR_VALUES{"$_[0]|$_[1]"} : $_[2] }
sub InternalTimer { push @TIMERS, [@_]; return }
sub RemoveInternalTimer { push @REMOVED_TIMERS, $_[0]; return }
sub gettimeofday { return time }
sub readingsSingleUpdate { push @READING_UPDATES, [@_]; return }
sub readingsBeginUpdate { return }
sub readingsBulkUpdate { return }
sub readingsEndUpdate { return }
sub getKeyValue {
    push @KEY_OPERATIONS, [get => $_[0]];
    return ($GET_KEY_ERRORS{$_[0]}, undef) if exists $GET_KEY_ERRORS{$_[0]};
    return (undef, $KEY_VALUES{$_[0]});
}
sub setKeyValue {
    my ($key, $value) = @_;
    push @KEY_OPERATIONS, [set => $key, $value];
    return $SET_KEY_ERRORS{$key} if exists $SET_KEY_ERRORS{$key};
    if (defined $value) { $KEY_VALUES{$key} = $value } else { delete $KEY_VALUES{$key} }
    return undef;
}

1;
