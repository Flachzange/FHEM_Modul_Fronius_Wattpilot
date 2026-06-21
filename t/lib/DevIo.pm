package DevIo;

use strict;
use warnings;

our (%KEY_VALUES, %ATTR_VALUES, %GET_KEY_ERRORS, %SET_KEY_ERRORS);
our ($OPEN_ERROR);
our (@LOGS, @WRITES, @OPENS, @CLOSES, @TIMERS, @REMOVED_TIMERS, @KEY_OPERATIONS, @READING_UPDATES);

sub reset_test_state {
    %KEY_VALUES = ();
    %ATTR_VALUES = ();
    %GET_KEY_ERRORS = ();
    %SET_KEY_ERRORS = ();
    %main::attr = ();
    $OPEN_ERROR = undef;
    @LOGS = ();
    @WRITES = ();
    @OPENS = ();
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
    *{"${caller}::attr"} = \%main::attr;
}

sub DevIo_CloseDev { push @CLOSES, $_[0]; return }
sub DevIo_IsOpen { return 0 }
sub DevIo_OpenDev {
    my ($hash, $reopen, $initfn, $callback) = @_;
    push @OPENS, [@_];
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    if (!$reopen) {
        my $shown = AttrVal($name, 'privacy', 0) ? '(private)' : $dev;
        Log3($name, 3, "Opening $name device $shown");
    }
    if (defined $OPEN_ERROR) {
        Log3($name, 1, "$name: Can't connect to $dev: $OPEN_ERROR") if !$reopen;
        $callback->($hash, $OPEN_ERROR) if $callback;
        return;
    }
    Log3($name, $hash->{devioLoglevel} || 1, "$dev reappeared ($name)") if $reopen;
    $callback->($hash, undef) if $callback;
    return;
}
sub DevIo_SimpleRead { return undef }
sub DevIo_SimpleWrite {
    my ($hash, $msg, $type, $addnl) = @_;
    my $shown = $type ? $msg : unpack('H*', $msg);
    Log3($hash->{NAME}, 5, "DevIo_SimpleWrite $hash->{NAME}: $shown");
    push @WRITES, [@_];
    return;
}
sub Log3 {
    my ($target, $level, $message) = @_;
    my $name = ref($target) eq 'HASH' ? $target->{NAME} : $target;
    return if $level > AttrVal($name, 'verbose', 3);
    push @LOGS, [@_];
    return;
}
sub AttrVal {
    my ($name, $attribute, $default) = @_;
    return $main::attr{$name}{$attribute} if exists $main::attr{$name}{$attribute};
    return $ATTR_VALUES{"$name|$attribute"} if exists $ATTR_VALUES{"$name|$attribute"};
    return $default;
}
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
