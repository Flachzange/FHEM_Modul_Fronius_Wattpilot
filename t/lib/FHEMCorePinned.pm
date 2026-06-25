package FHEMCorePinned;

use strict;
use warnings;

our $FHEM_REVISION = '0ae38bf79d19d8d598c065bf84b3990b33063c4b';
our $FHEM_PL_BLOB_SHA = '0c03b2989d2e5be6f019cfb07a6a3e53db62050b';
our $DEVIO_BLOB_SHA = 'ce94276bb9d3e4963ebc514a93a86b442984e72f';

our (%defs, %modules, %attr, %ntfyHash, %oldvalue, %selectlist, %readyfnlist);
our ($featurelevel, $init_done, $namedef);
our (@CALLS, @STRUCT_CHANGES, @TRIGGERS);

BEGIN {
    no strict 'refs';
    *defs = \%main::defs;
    *modules = \%main::modules;
    *attr = \%main::attr;
}

sub reset {
    %main::defs = ();
    %main::modules = ();
    %main::attr = ();
    %ntfyHash = ();
    %oldvalue = ();
    %selectlist = ();
    %readyfnlist = ();
    @CALLS = ();
    @STRUCT_CHANGES = ();
    @TRIGGERS = ();
    $featurelevel = 6.4;
    $init_done = 1;
    $namedef = '';
    DevIo::reset_test_state();
}

sub install_module {
    my ($type, $registration) = @_;
    $modules{$type} = { %{$registration} };
}

sub CallFn {
    my ($name, $fn, @args) = @_;
    push @CALLS, [$name, $fn];
    my $hash = $defs{$name};
    return undef if !$hash;
    my $callback = $modules{$hash->{TYPE}}{$fn};
    return undef if !$callback;
    return $callback->(@args) if ref($callback) eq 'CODE';
    no strict 'refs';
    return &{"main::$callback"}(@args);
}

sub parseParams { return @{$_[0]}; }
sub ReplaceEventMap { return @{$_[1]}; }
sub ReplaceSetMagic { return (undef, @_ > 2 ? @_[2 .. $#_] : ()); }
sub DoTrigger { push @TRIGGERS, [@_]; return undef; }
sub addStructChange { push @STRUCT_CHANGES, [@_]; return undef; }
sub removeFromNtfyHash { return undef; }
sub goodDeviceName { return defined($_[0]) && $_[0] =~ m/^[A-Za-z0-9._]+$/; }
sub devspec2array { return defined($defs{$_[0]}) ? ($_[0]) : (); }
sub IsDisabled { return $attr{$_[0]}{disable} ? 1 : 0; }
sub TimeNow { return '2026-06-25 19:00:00'; }
sub ReadingsVal {
    my ($name, $reading, $default) = @_;
    return $default if !$defs{$name}{READINGS}{$reading};
    return $defs{$name}{READINGS}{$reading}{VAL};
}
sub setReadingsVal {
    my ($hash, $reading, $value, $time) = @_;
    $hash->{READINGS}{$reading} = { VAL => $value, TIME => $time };
    return undef;
}

# The functions below are copied without semantic changes from fhem.pl at
# $FHEM_REVISION. Only their external dependencies are provided by the small
# controlled adapter above. This keeps the real callback order under test.

# fhem.pl lines 1966-2004 at the pinned revision.
sub DoSet(@)
{
  my @a = @_;

  my $dev = $a[0];
  my $hash = $defs{$dev};
  return "Please define $dev first" if(!$hash);
  return "Bogus entry $dev without TYPE" if(!$hash->{TYPE});
  return "No set implemented for $dev" if(!$modules{$hash->{TYPE}}{SetFn});

  # No special handling needed fo the Usage check
  return CallFn($dev, "SetFn", $hash,
        $modules{$hash->{TYPE}}->{parseParams} ? parseParams(\@a) : @a)
    if($a[1] && $a[1] eq "?");

  @a = ReplaceEventMap($dev, \@a, 0) if($attr{$dev}{eventMap});
  my $err;
  ($err, @a) = ReplaceSetMagic($hash, 0, @a) if($featurelevel >= 5.7);
  return $err if($err);

  $hash->{".triggerUsed"} = 0;
  my ($ret, $skipTrigger) = CallFn($dev, "SetFn", $hash,
                $modules{$hash->{TYPE}}->{parseParams} ? parseParams(\@a) : @a);
  return $ret if($ret);
  return undef if($skipTrigger);

  # Backward compatibility. Use readingsUpdate in SetFn now
  # case: DoSet is called from a notify triggered by DoSet with same dev
  if(defined($hash->{".triggerUsed"}) && $hash->{".triggerUsed"} == 0) {
    shift @a;
    # set arg if the module did not triggered events
    my $arg;
    $arg = join(" ", @a) if(!$hash->{CHANGED} || !int(@{$hash->{CHANGED}}));
    DoTrigger($dev, $arg, 0);
  }
  delete($hash->{".triggerUsed"});

  return undef;
}

# fhem.pl lines 2222-2256 at the pinned revision.
sub CommandModify($$)
{
  my ($cl, $def) = @_;

  my %opt;
  $def = cmd_parseOpts($def, '-silent', \%opt);
  my @a = split("[ \t]+", $def, 2);

  return "Usage: modify <name> <type dependent arguments>"
                if(int(@a) < 1);

  # Return a list of modules
  return "Define $a[0] first" if(!defined($defs{$a[0]}));
  my $hash = $defs{$a[0]};
  %ntfyHash = () if($hash->{NTFY_ORDER});

  $hash->{OLDDEF} = $hash->{DEF};
  $hash->{DEF} = $a[1];
  $hash->{CL} = $cl;
  my $ret = CallFn($a[0], "DefFn", $hash,
              $modules{$hash->{TYPE}}->{parseParams} ?
              parseParams("$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]":"")):
              "$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]" : ""));
  delete $hash->{CL};
  if($ret) {
    $hash->{DEF} = $hash->{OLDDEF};
  } else {
    addStructChange("modify", $a[0], $def) if(!$opt{silent});
    DoTrigger("global", "MODIFIED $a[0]", 1) if($init_done);
  }

  delete($hash->{OLDDEF});
  return $ret;
}

# fhem.pl lines 2259-2280 at the pinned revision.
sub CommandDefMod($$)
{
  my ($cl, $def) = @_;
  my %opt;
  my $optRegexp = '-ignoreErr|-temporary|-silent';
  $def = cmd_parseOpts($def, $optRegexp, \%opt);
  my @a = split("[ \t]+", $def, 3);

  return "Usage: defmod [$optRegexp] <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  if($defs{$a[0]}) {
    $def = $a[2] ? "$a[0] $a[2]" : $a[0];
    return "defmod $a[0]: Cannot change the TYPE of an existing definition"
        if($a[1] ne $defs{$a[0]}{TYPE});
    $def = "-".join(" -", keys %opt)." ".$def if(%opt);
    return CommandModify($cl, $def);
  } else {
    $def = "-".join(" -", keys %opt)." ".$def if(%opt);
    return CommandDefine($cl, $def);
  }
}

# Definition creation is added in the next bounded stage. Keeping the missing
# path explicit prevents the initial harness from pretending to cover it.
sub CommandDefine { die 'pinned CommandDefine path not installed yet'; }

# fhem.pl lines 2826-2865 at the pinned revision.
sub CommandRename($$)
{
  my ($cl, $param) = @_;
  my ($old, $new) = split(" ", $param);

  return "old name is empty" if(!defined($old));
  return "new name is empty" if(!defined($new));

  return "Please define $old first" if(!defined($defs{$old}));
  return "$new already defined" if(defined($defs{$new}));
  return "Invalid characters in name (not A-Za-z0-9._): $new"
                        if(!goodDeviceName($new));
  return "Cannot rename global" if($old eq "global");
  return "Cannot rename $old from itself"
        if($cl && $cl->{SNAME} && $cl->{SNAME} eq $old);

  %ntfyHash = ();
  $defs{$new} = $defs{$old};
  $defs{$new}{NAME} = $new;
  delete($defs{$old});          # The new pointer will preserve the hash

  $attr{$new} = $attr{$old} if(defined($attr{$old}));
  delete($attr{$old});

  $oldvalue{$new} = $oldvalue{$old} if(defined($oldvalue{$old}));
  delete($oldvalue{$old});

  CallFn($new, "RenameFn", $new,$old);# ignore replies
  for my $d (keys %defs) {
    my $aw = ReadingsVal($d, "associatedWith", "");
    next if($aw !~ m/\b$old\b/);
    $aw =~ s/\b$old\b/$new/;
    setReadingsVal($defs{$d}, "associatedWith", $aw, TimeNow()) if($defs{$d});
  }

  addStructChange("rename", $new, $param);
  DoTrigger("global", "RENAMED $old $new", 1);
  return undef;
}

# fhem.pl lines 2355-2403 at the pinned revision.
sub CommandDelete($$)
{
  my ($cl, $def) = @_;
  return "Usage: delete <name>$namedef\n" if(!$def);

  my @rets;
  foreach my $sdev (devspec2array($def, $cl)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $defs{$sdev}->{CL} = $cl;
    my $ret = CallFn($sdev, "UndefFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      delete $defs{$sdev}->{CL};
      next;
    }
    $ret = CallFn($sdev, "DeleteFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      delete $defs{$sdev}->{CL};
      next;
    }
    delete $defs{$sdev}->{CL};
    removeFromNtfyHash($sdev);

    # Delete releated hashes
    foreach my $p (keys %selectlist) {
      if($selectlist{$p} && $selectlist{$p}{NAME} eq $sdev) {
        delete $selectlist{$p};
      }
    }
    foreach my $p (keys %readyfnlist) {
      delete $readyfnlist{$p}
        if($readyfnlist{$p} && $readyfnlist{$p}{NAME} eq $sdev);
    }

    my $temporary = $defs{$sdev}{TEMPORARY};
    addStructChange("delete", $sdev, $sdev) if(!$temporary);
    delete($attr{$sdev});
    delete($defs{$sdev});
    DoTrigger("global", "DELETED $sdev", 1) if(!$temporary);

  }
  return join("\n", @rets);
}

sub cmd_parseOpts($$$)
{
  my ($def, $optRegexp, $res) = @_;
  while($def) {
    last if($def !~ m/^\s*($optRegexp)\s+/);
    my $o = $1;
    $def =~ s/^\s*$o\s+//;
    $o =~ s/^-//;
    $res->{$o} = 1;
  }
  return $def;
}

1;
