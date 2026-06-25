package DevIo;

use strict;
use warnings;

our $FHEM_SOURCE_REVISION = '0ae38bf79d19d8d598c065bf84b3990b33063c4b';
our $FHEM_TIMER_SOURCE_REVISION = '0ae38bf79d19d8d598c065bf84b3990b33063c4b';
our $FHEM_ATTR_SOURCE_REVISION = '0ae38bf79d19d8d598c065bf84b3990b33063c4b';
our $NOW;
our (%KEY_VALUES, %ATTR_VALUES, %GET_KEY_ERRORS, %SET_KEY_ERRORS);
our (%GET_KEY_ERROR_QUEUE, %SET_KEY_ERROR_QUEUE);
our (%READYFNLIST, %SELECTLIST);
our ($OPEN_ERROR, $OPEN_MODE);
our (@LOGS, @WRITES, @READS, @OPENS, @OPEN_CALLBACKS, @TRIGGERS, @CLOSES, @TIMERS, @ACTIVE_TIMERS, @REMOVED_TIMERS, @KEY_OPERATIONS, @READING_UPDATES, @READING_EVENTS, @RENAMES, @IGNORED_RENAME_REPLIES);

sub reset_test_state {
    %KEY_VALUES = ();
    %ATTR_VALUES = ();
    %GET_KEY_ERRORS = ();
    %SET_KEY_ERRORS = ();
    %GET_KEY_ERROR_QUEUE = ();
    %SET_KEY_ERROR_QUEUE = ();
    %READYFNLIST = ();
    %SELECTLIST = ();
    %main::attr = ();
    $OPEN_ERROR = undef;
    $OPEN_MODE = 'success';
    @LOGS = ();
    @WRITES = ();
    @READS = ();
    @OPENS = ();
    @OPEN_CALLBACKS = ();
    @TRIGGERS = ();
    @CLOSES = ();
    @TIMERS = ();
    @ACTIVE_TIMERS = ();
    @REMOVED_TIMERS = ();
    @KEY_OPERATIONS = ();
    @READING_UPDATES = ();
    @READING_EVENTS = ();
    @RENAMES = ();
    @IGNORED_RENAME_REPLIES = ();
    $NOW = undef;
}

# Models fhem.pl CommandAttr at the pinned attribute revision: AttrFn is
# called before framework storage, and a callback error vetoes the mutation.
sub command_attr {
    my ($name, $attribute, $value) = @_;
    return "Please define $name first" if !defined $main::defs{$name};
    my $reply = main::Wattpilot_Attr('set', $name, $attribute, $value);
    return $reply if defined($reply) && $reply ne '';
    $main::attr{$name}{$attribute} = $value;
    return undef;
}

# Models fhem.pl CommandDeleteAttr at the pinned attribute revision: AttrFn is
# called while the old attribute value is still visible, then storage is removed.
sub command_delete_attr {
    my ($name, $attribute) = @_;
    return "Please define $name first" if !defined $main::defs{$name};
    my $old = $main::attr{$name}{$attribute};
    my $reply = main::Wattpilot_Attr('del', $name, $attribute, $old);
    return $reply if defined($reply) && $reply ne '';
    delete $main::attr{$name}{$attribute};
    return undef;
}

# Models fhem.pl CommandModify at the pinned revision: OLDDEF and the new DEF
# are installed before DefFn is called, and only DEF is restored on a veto.
sub command_modify {
    my ($name, $new_def) = @_;
    return "Define $name first" if !defined $main::defs{$name};
    my $hash = $main::defs{$name};
    $hash->{OLDDEF} = $hash->{DEF};
    $hash->{DEF} = $new_def;
    my $definition = "$name $hash->{TYPE}";
    $definition .= " $new_def" if defined($new_def) && $new_def ne '';
    my $reply = main::Wattpilot_Define($hash, $definition);
    $hash->{DEF} = $hash->{OLDDEF} if defined($reply) && $reply ne '';
    delete $hash->{OLDDEF};
    return $reply;
}


# Models fhem.pl CommandRename at the pinned revision: framework-owned hashes
# and attributes move before RenameFn, and the callback reply is discarded.
sub command_rename {
    my ($old, $new) = @_;
    return "Please define $old first" if !defined $main::defs{$old};
    return "$new already defined" if defined $main::defs{$new};
    $main::defs{$new} = $main::defs{$old};
    $main::defs{$new}{NAME} = $new;
    delete $main::defs{$old};
    $main::attr{$new} = $main::attr{$old} if defined $main::attr{$old};
    delete $main::attr{$old};
    push @RENAMES, [$old, $new];
    my $reply = main::Wattpilot_Rename($new, $old);
    push @IGNORED_RENAME_REPLIES, $reply;
    return undef;
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
        readingsBulkUpdate readingsBulkUpdateIfChanged readingsEndUpdate
        getKeyValue setKeyValue
    )) {
        *{"${caller}::$name"} = \&{$name};
    }

    *{"${caller}::readingFnAttributes"} = \$main::readingFnAttributes;
    *{"${caller}::modules"} = \%main::modules;
    *{"${caller}::defs"} = \%main::defs;
    *{"${caller}::attr"} = \%main::attr;
}

sub DevIo_CloseDev {
    my ($hash) = @_;
    push @CLOSES, $hash;
    my $key = join('.', $hash->{NAME} // '', $hash->{DeviceName} // '');
    $hash->{TEST_OPEN} = 0;
    delete $hash->{TCPDev};
    delete $hash->{CD};
    delete $hash->{'.WSBUF'};
    delete $hash->{WEBSOCKET};
    delete $hash->{FD};
    delete $hash->{EXCEPT_FD};
    delete $hash->{PARTIAL};
    delete $hash->{NEXT_OPEN};
    delete $READYFNLIST{$hash->{NAME}};
    delete $READYFNLIST{$key};
    delete $SELECTLIST{$key};
    return;
}
sub DevIo_IsOpen {
    return ($_[0]{TEST_OPEN} || $_[0]{TCPDev}) ? 1 : 0;
}
sub DevIo_OpenDev {
    my ($hash, $reopen, $initfn, $callback) = @_;
    push @OPENS, [@_];
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $level = $hash->{devioLoglevel} || 3;
    my $key = "$name.$dev";

    # Pinned DevIo_OpenDev consumes DevIoJustClosed before attempting a new
    # open. The ReadyFn owner remains installed and will invoke ReadyFn again.
    if ($hash->{DevIoJustClosed}) {
        delete $hash->{DevIoJustClosed};
        push @OPEN_CALLBACKS, [$reopen, undef];
        $callback->($hash, undef) if $callback;
        return;
    }
    if (!$reopen) {
        my $shown = AttrVal($name, 'privacy', 0) ? '(private)' : $dev;
        Log3($name, $level, "Opening $name device $shown");
    } else {
        # FHEM DevIo removes the old ReadyFn owner before HttpUtils_Connect.
        # A synchronous HttpUtils error can then leave only the expired
        # NEXT_OPEN value behind.
        delete $READYFNLIST{$name};
        delete $READYFNLIST{$key};
    }

    # FHEM DevIo.pm -> HttpUtils_Connect side effects at revision above.
    my ($host) = $dev =~ m{^wss?:([^:]+):};
    $host //= '192.0.2.10';
    my $url = "http://$host:80/ws";
    Log3($name, 5, "HttpUtils url=$url NonBlocking via http");

    my $mode = defined($OPEN_ERROR) ? 'sync_error' : $OPEN_MODE;
    if ($mode eq 'sync_error') {
        my $error = $OPEN_ERROR // "connect to $url failed";
        Log3($name, 4, "HttpUtils: $error");
        Log3($name, 1, "$name: Can't connect to $dev: $error") if !$reopen;
        push @OPEN_CALLBACKS, [$reopen, $error];
        $callback->($hash, $error) if $callback;
        return;
    }

    if ($mode eq 'dns_error') {
        my $error = "gethostbyname $host failed";
        Log3($name, 4, "HttpUtils: $error");
        push @TRIGGERS, 'DISCONNECTED' if !$reopen;
        Log3($name, 1, "$name: Can't connect to $dev: $error") if !$reopen;
        push @OPEN_CALLBACKS, [$reopen, $error];
        $callback->($hash, $error) if $callback;
        return;
    }

    Log3($name, 4, "IP: $host -> 192.0.2.20");
    if ($mode eq 'async_error' || $mode eq 'timeout') {
        my $error = $mode eq 'timeout'
          ? "connect to http://$host:80 timed out"
          : "$host: connection refused";
        Log3($name, 4, "HttpUtils: $error") if $mode eq 'async_error';
        DevIo_CloseDev($hash);
        $READYFNLIST{$name} = $hash;
        $READYFNLIST{$key} = $hash;
        $hash->{NEXT_OPEN} = gettimeofday() + 60;
        push @TRIGGERS, 'DISCONNECTED' if !$reopen;
        Log3($name, 1, "$name: Can't connect to $dev: $error") if !$reopen;
        push @OPEN_CALLBACKS, [$reopen, $error];
        $callback->($hash, $error) if $callback;
        return;
    }

    if ($mode eq 'deferred') {
        push @OPEN_CALLBACKS, [$reopen, undef, $callback, $hash, $name, $dev];
        return;
    }

    Log3($name, $hash->{devioLoglevel} || 1, "$dev reappeared ($name)") if $reopen;
    $hash->{TEST_OPEN} = 1;
    $hash->{TCPDev} = 1;
    $hash->{CD} = 1;
    $hash->{WEBSOCKET} = 1 if $dev =~ /^wss?:/;
    $hash->{FD} = 99;
    delete $hash->{NEXT_OPEN};
    delete $READYFNLIST{$name};
    delete $READYFNLIST{"$name.$dev"};
    $SELECTLIST{"$name.$dev"} = $hash;
    readingsSingleUpdate($hash, 'state', 'opened', 1);
    push @TRIGGERS, 'CONNECTED';
    push @OPEN_CALLBACKS, [$reopen, undef];
    $callback->($hash, undef) if $callback;
    return;
}

sub complete_deferred_open {
    my ($index, $error) = @_;
    $index //= 0;
    my $entry = $OPEN_CALLBACKS[$index];
    die "no deferred open at index $index" if ref($entry) ne 'ARRAY' || @$entry < 4;
    my ($reopen, undef, $callback, $hash, $name, $dev) = @$entry;
    $name //= $hash->{NAME};
    $dev //= $hash->{DeviceName};
    if (defined $error) {
        DevIo_CloseDev($hash);
        my $key = "$name.$dev";
        $READYFNLIST{$name} = $hash;
        $READYFNLIST{$key} = $hash;
        $hash->{NEXT_OPEN} = gettimeofday() + 60;
        push @TRIGGERS, 'DISCONNECTED' if !$reopen;
        $callback->($hash, $error) if $callback;
        return;
    }

    Log3($name, $hash->{devioLoglevel} || 1, "$dev reappeared ($name)") if $reopen;
    $hash->{TEST_OPEN} = 1;
    $hash->{TCPDev} = 1;
    $hash->{CD} = 1;
    $hash->{WEBSOCKET} = 1 if $dev =~ /^wss?:/;
    $hash->{FD} = 99;
    delete $hash->{NEXT_OPEN};
    delete $READYFNLIST{$name};
    delete $READYFNLIST{"$name.$dev"};
    $SELECTLIST{"$name.$dev"} = $hash;
    readingsSingleUpdate($hash, 'state', 'opened', 1);
    push @TRIGGERS, 'CONNECTED';
    $callback->($hash, undef) if $callback;
    return;
}
# DevIo_DecodeWS at the pinned revision owns raw-frame buffering in .WSBUF and
# DevIo_SimpleRead returns decoded payload bytes, possibly concatenated from
# complete frames. FIN is logged but not used to accumulate a logical message,
# so tests may queue JSON continuations across decoded return values here.
sub DevIo_SimpleRead {
    my ($hash) = @_;
    my $value = shift @READS;

    # A WebSocket Close control frame is decoded inside DevIo_DecodeWS. At the
    # pinned revision it calls DevIo_CloseDev directly and returns undef, so no
    # ReadyFn/NEXT_OPEN reconnect owner and no DevIoJustClosed marker exist.
    if (ref($value) eq 'HASH' && ($value->{kind} // '') eq 'websocket_close') {
        DevIo_CloseDev($hash);
        return undef;
    }

    # Ordinary EOF/read loss is owned by DevIo_Disconnected: close, install a
    # ReadyFn owner, publish disconnected and set DevIoJustClosed so the first
    # ReadyFn OpenDev call is consumed without opening immediately.
    if (!defined $value) {
        return undef if !defined $hash->{FD};
        DevIo_CloseDev($hash);
        $READYFNLIST{$hash->{NAME}} = $hash;
        $READYFNLIST{($hash->{NAME} // '') . '.' . ($hash->{DeviceName} // '')} = $hash;
        readingsSingleUpdate($hash, 'state', 'disconnected', 1);
        $hash->{DevIoJustClosed} = 1;
        push @TRIGGERS, 'DISCONNECTED';
    }
    return $value;
}
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
sub InternalTimer {
    my $timer = [@_];
    push @TIMERS, $timer;
    push @ACTIVE_TIMERS, $timer;
    return;
}
sub RemoveInternalTimer {
    my ($argument, $function) = @_;
    push @REMOVED_TIMERS, [$argument, $function];
    @ACTIVE_TIMERS = grep {
        my ($timer_function, $timer_argument) = ($_->[1], $_->[2]);
        !(defined($timer_argument) && $timer_argument == $argument
          && (!defined($function) || $timer_function eq $function));
    } @ACTIVE_TIMERS;
    return;
}
sub run_due_timers {
    my ($now) = @_;
    $NOW = $now;
    my @due = grep { $_->[0] <= $now } @ACTIVE_TIMERS;
    @ACTIVE_TIMERS = grep { $_->[0] > $now } @ACTIVE_TIMERS;
    for my $timer (@due) {
        no strict 'refs';
        &{"main::$timer->[1]"}($timer->[2]);
        use strict 'refs';
    }
}
sub gettimeofday { return defined($NOW) ? $NOW : time }
# Models the pinned fhem.pl reading transaction helpers. In particular,
# readingsBulkUpdateIfChanged returns before setReadingsVal/addEvent when the
# public value is unchanged, preserving both reading timestamp and event list.
sub readingsSingleUpdate {
    my ($hash, $reading, $value) = @_;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, $reading, $value);
    readingsEndUpdate($hash, 1);
    $hash->{STATE} = $value if $reading eq 'state';
    return;
}
sub readingsBeginUpdate {
    my ($hash) = @_;
    my $now = gettimeofday();
    $hash->{'.updateTime'} = $now;
    $hash->{'.updateTimestamp'} = "$now";
    $hash->{CHANGED} = [] if !defined $hash->{CHANGED};
    return $hash->{'.updateTimestamp'};
}
sub readingsBulkUpdateIfChanged {
    my ($hash, $reading, $value, $changed) = @_;
    return undef
        if exists($hash->{READINGS}{$reading}{VAL})
        && $hash->{READINGS}{$reading}{VAL} eq $value;
    return readingsBulkUpdate($hash, $reading, $value, $changed);
}
sub readingsBulkUpdate {
    my ($hash, $reading, $value, $changed) = @_;
    die "readingsBulkUpdate without readingsBeginUpdate"
        if !exists $hash->{'.updateTimestamp'};
    push @READING_UPDATES, [@_];
    $hash->{READINGS}{$reading}{VAL} = $value;
    $hash->{READINGS}{$reading}{TIME} = $hash->{'.updateTimestamp'};
    $changed = 1 if !defined $changed && substr($reading, 0, 1) ne '.';
    if ($changed) {
        my $event = "$reading: $value";
        push @{$hash->{CHANGED}}, $event;
        push @READING_EVENTS, [$hash, $reading, $value, $event];
    }
    return "$reading: $value";
}
sub readingsEndUpdate {
    my ($hash) = @_;
    delete $hash->{'.updateTimestamp'};
    delete $hash->{'.updateTime'};
    return;
}
sub getKeyValue {
    push @KEY_OPERATIONS, [get => $_[0]];
    if (exists $GET_KEY_ERROR_QUEUE{$_[0]} && @{$GET_KEY_ERROR_QUEUE{$_[0]}}) {
        my $error = shift @{$GET_KEY_ERROR_QUEUE{$_[0]}};
        delete $GET_KEY_ERROR_QUEUE{$_[0]} if !@{$GET_KEY_ERROR_QUEUE{$_[0]}};
        return ($error, undef) if defined $error;
    }
    return ($GET_KEY_ERRORS{$_[0]}, undef) if exists $GET_KEY_ERRORS{$_[0]};
    return (undef, $KEY_VALUES{$_[0]});
}
sub setKeyValue {
    my ($key, $value) = @_;
    push @KEY_OPERATIONS, [set => $key, $value];
    if (exists $SET_KEY_ERROR_QUEUE{$key} && @{$SET_KEY_ERROR_QUEUE{$key}}) {
        my $error = shift @{$SET_KEY_ERROR_QUEUE{$key}};
        delete $SET_KEY_ERROR_QUEUE{$key} if !@{$SET_KEY_ERROR_QUEUE{$key}};
        return $error if defined $error;
    }
    return $SET_KEY_ERRORS{$key} if exists $SET_KEY_ERRORS{$key};
    if (defined $value) { $KEY_VALUES{$key} = $value } else { delete $KEY_VALUES{$key} }
    return undef;
}

1;
