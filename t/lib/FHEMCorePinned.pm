package FHEMCorePinned;

use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

our $FHEM_REVISION = '0ae38bf79d19d8d598c065bf84b3990b33063c4b';
our $FHEM_PL_BLOB_SHA = '0c03b2989d2e5be6f019cfb07a6a3e53db62050b';
our $DEVIO_BLOB_SHA = 'ce94276bb9d3e4963ebc514a93a86b442984e72f';

our (%defs, %modules, %attr, %ntfyHash, %oldvalue, %selectlist, %readyfnlist);
our (%ra, %attrSource, %defaultattr);
our ($featurelevel, $init_done, $namedef, $AttrList, $fhemdebug);
our ($currcfgfile, $devcountPrioSave, $devcountTemp, $devcount);
our $UUID_COUNTER;
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
    $AttrList = '';
    $fhemdebug = 0;
    $currcfgfile = '';
    $devcountPrioSave = 10;
    $devcountTemp = 1000;
    $devcount = 100;
    $UUID_COUNTER = 0;
    %ra = ();
    %attrSource = ();
    %defaultattr = ();
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
sub AttrVal {
    my ($name, $attribute, $default) = @_;
    return $default if !exists($attr{$name}) || !exists($attr{$name}{$attribute});
    return $attr{$name}{$attribute};
}
sub configDBUsed { return 0; }
sub _cfgDB_Fileexport { return '0'; }
sub LoadModule {
    my ($module) = @_;
    return exists($modules{$module}) ? $module : 'UNDEFINED';
}
sub genUUID { return sprintf('00000000-0000-0000-0000-%012d', ++$UUID_COUNTER); }
sub goodReadingName { return defined($_[0]) && $_[0] =~ m{^[A-Za-z0-9_./-]+$}; }
sub resolveAttrRename { return $_[1]; }
sub getAllAttr {
    my ($name) = @_;
    return '' if !$defs{$name};
    return $modules{$defs{$name}{TYPE}}{AttrList} // '';
}
sub perlSyntaxCheck { return undef; }
sub evalStateFormat { return undef; }
sub fhem_setIoDev { return undef; }
sub Log { return DevIo::Log3('FHEMCorePinned', @_); }
sub Wattpilot_Initialize { goto &main::Wattpilot_Initialize; }
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

# fhem.pl lines 2125-2221 at the pinned revision.
sub CommandDefine($$)
{
  my ($cl, $def) = @_;

  # ignoreErr ist used by RSS in fhem.cfg.demo, with no GD installed
  # temporary #39610 #46640
  # silent    #57691
  my %opt;
  my $optRegexp = '-ignoreErr|-temporary|-silent';
  $def = cmd_parseOpts($def, $optRegexp, \%opt);
  my @a = split("[ \t]+", $def, 3);

  my $name = $a[0];
  return "Usage: define [$optRegexp] <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  return "$name already defined, delete it first" if(defined($defs{$name}));
  return "Invalid characters in name (not A-Za-z0-9._): $name"
                        if(!goodDeviceName($name));

  my $m = $a[1];
  if(!$modules{$m}) {                           # Perhaps just wrong case?
    foreach my $i (keys %modules) {
      if(uc($m) eq uc($i)) {
        $m = $i;
        last;
      }
    }
  }

  my $newm = LoadModule($m, $opt{ignoreErr});
  return "Cannot load module $m" if($newm eq "UNDEFINED");
  $m = $newm;

  return "Unknown module $m" if(!$modules{$m} || !$modules{$m}{DefFn});

  my %hash;

  $hash{NAME}  = $name;
  $hash{FUUID} = genUUID();
  $hash{TYPE}  = $m;
  $hash{STATE} = "???";
  $hash{DEF}   = $a[2] if(int(@a) > 2);
  #130588: start early after next save, for a small SubProcess size
  $hash{NR}    = ($modules{$m}{prioSave} && $devcountPrioSave < 30) ?
                    $devcountPrioSave++ :
                    ($opt{temporary} ? $devcountTemp++ : $devcount++);
  $hash{CFGFN} = $currcfgfile
        if($currcfgfile ne AttrVal("global", "configfile", "") &&
          !configDBUsed());
  $hash{CL}    = $cl;
  $hash{TEMPORARY} = 1 if($opt{temporary});

  # If the device wants to issue initialization gets/sets, then it needs to be
  # in the global hash.
  $defs{$name} = \%hash;

  my $ret = CallFn($name, "DefFn", \%hash,
                $modules{$m}->{parseParams} ? parseParams($def) : $def);
  if($ret) {
    Log 1, "define $def: $ret" if(!$opt{ignoreErr});
    delete $defs{$name};                            # Veto
    delete $attr{$name};

  } else {
    delete $hash{CL};
    foreach my $da (sort keys (%defaultattr)) {     # Default attributes
      CommandAttr($cl, "$name $da $defaultattr{$da}");
    }
    if($modules{$m}{NotifyFn} && !$hash{NTFY_ORDER}) {
      $hash{NTFY_ORDER} = ($modules{$m}{NotifyOrderPrefix} ?
                $modules{$m}{NotifyOrderPrefix} : "50-") . $name;
    }
    %ntfyHash = ();
    if(!$opt{temporary} && $init_done) {
      addStructChange("define", $name, $def) if(!$opt{silent});
      DoTrigger("global", "DEFINED $name", 1);
    }

    if($init_done && $modules{$m}{Match}) { # reset multiple IOdev, #127565
      foreach my $an (keys %defs) {
        my $ah = $defs{$an};
        my $cl = $ah->{Clients};
        $cl = $modules{$ah->{TYPE}}{Clients} if(!$cl);
        next if(!$cl || !$ah->{'.clientArray'});
        foreach my $cmRe ( split(/:/, $cl) ) {
          if($m =~ m/^$cmRe$/) {
            delete($ah->{'.clientArray'});
            last;
          }
        }
      }
    }

  }
  return ($ret && $opt{ignoreErr} ?
        "Cannot define $name, remove -ignoreErr for details" : $ret);
}

# fhem.pl lines 2407-2458 at the pinned revision.
sub CommandDeleteAttr($$)
{
  my ($cl, $def) = @_;

  my $optRegexp = '-silent';
  my %opt;
  $def = cmd_parseOpts($def, $optRegexp, \%opt);

  my @a = split(" ", $def, 2);
  return "Usage: deleteattr <name> [<attrname>]\n$namedef" if(@a < 1);

  my @rets;
  foreach my $sdev (devspec2array($a[0], $cl)) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;

    if($a[1]) {
      if($a[1] eq "userReadings") {
        delete($defs{$sdev}{'.userReadings'});
      } elsif($ra{$a[1]}) {
        my $cache = $ra{$a[1]}{c};
        delete $defs{$sdev}{$cache} if( $cache );
      }
    }

    my $ret = CallFn($sdev, "AttrFn", "del", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    if(@a == 1) { # Delete all attributes of a device
      delete($attr{$sdev});

    } else { # delete specified attribute(s)
      if(defined($attr{$sdev})) {
        map { delete($attr{$sdev}{$_}) if($_ =~ m/^$a[1]$/) }
            keys %{$attr{$sdev}};
      }

    }
    addStructChange("deleteAttr", $sdev, join(" ", @a)) if(!$opt{silent});
    DoTrigger("global", "DELETEATTR ".join(" ",@a), 1) if($init_done);

  }

  return join("\n", @rets);
}

# fhem.pl lines 3071-3251 at the pinned revision.
sub CommandAttr($$)
{
  my ($cl, $param) = @_;
  my ($ret, $append, $remove, @a);
  my %opt;
  my $optRegexp = '-a|-r|-silent';
  $param = cmd_parseOpts($param, $optRegexp, \%opt);

  @a = split(" ", $param, 3) if($param);

  return "Usage: attr [$optRegexp] <name> <attrname> [<attrvalue>]\n$namedef"
           if(@a < 2 || ($opt{a} && $opt{r}));
  my $a1 = $a[1];
  return "$a[0]: bad attribute name '$a1' (allowed chars: A-Za-z/\\d_\\.-)"
           if($featurelevel > 5.9 && !goodReadingName($a1) && $a1 ne "?");
  return "attr $param: attribute value is missing" if($#a < 2 && $a1 ne "?");

  my @rets;
  foreach my $sdev (devspec2array($a[0], $a1 && $a1 eq "?" ? undef : $cl)) {

    my $hash = $defs{$sdev};
    my $attrName = $a1;
    my $attrVal = $a[2];
    if(!defined($hash)) {
      push @rets, "Please define $sdev first" if($init_done);#define -ignoreErr
      next;
    }

    my $list = getAllAttr($sdev);
    if($attrName eq "?") {
      push @rets, "$sdev: unknown attribute $attrName, choose one of $list";
      next;
    }

    $attrName = resolveAttrRename($sdev,$attrName);

    if(" $list " !~ m/ ${attrName}[ :;]/) {
       my $found = 0;
       foreach my $atr (split("[ \t]", $list)) { # is it a regexp?
         $atr =~ /^([^;:]+)(:.*)?$/;
         my $base = $1;
         if(${attrName} =~ m/^$base$/) {
           $found++;
           last;
         }
      }
      if(!$found) {
        push @rets, "$sdev: unknown attribute $attrName. ".
                        "Type 'attr $sdev ?' for a detailed list.";
        next;
      }
    }

    if($opt{a} && $attr{$sdev} && $attr{$sdev}{$attrName}) {
      $attrVal = $attr{$sdev}{$attrName} .
                        ($attrVal =~ m/^,/ ? $attrVal : " $attrVal");
    }
    if($opt{r} && $attr{$sdev} && $attr{$sdev}{$attrName}) {
      my $v = $attr{$sdev}{$attrName};
      $v =~ s/\b$attrVal\b//;
      $attrVal = $v;
    }

    if($attrName eq 'disable' && $attrVal eq 'toggle') {
       $attrVal = IsDisabled($sdev) ? 0 : 1;
    }

    if($attrName eq "userReadings") {

      my @userReadings;
      # myReading1[:trigger1] [modifier1] { codecodecode1 }, ...
      my $arg= $attrVal;

      # matches myReading1[:trigger2] { codecode1 }
      my $regexi= '\s*([\w.-]+)(:\S*)?\s+((\w+)\s+)?(\{.*?\})\s*';
      my $regexo= '^(' . $regexi . ')(,\s*(.*))*$';
      my $rNo=0;

      while($arg =~ /$regexo/s) {
        my $reading= $2;
        my $trigger= $3 ? $3 : undef;
        my $modifier= $5 ? $5 : "none";
        my $perlCode= $6;
        #Log 1, sprintf("userReading %s has perlCode %s with modifier %s%s",
        # $userReading,$perlCode,$modifier,$trigger?" and trigger $trigger":"");
        if(grep { /$modifier/ }
                qw(none difference differential offset monotonic integral)) {
          $trigger =~ s/^:// if($trigger);
          my %userReading = ( reading => $reading,
                              trigger => $trigger,
                              modifier => $modifier,
                              perlCode => $perlCode );
          push @userReadings, \%userReading;
        } else {
          push @rets, "$sdev: unknown modifier $modifier for ".
                "userReading $reading, this userReading will be ignored";
        }
        $arg= defined($8) ? $8 : "";
      }
      $hash->{'.userReadings'}= \@userReadings;
    }

    my $oVal = ($attr{$sdev} ? $attr{$sdev}{$attrName} : "");

    if($attrName eq "eventMap") {
      delete $hash->{".eventMapHash"};
      delete $hash->{".eventMapCmd"};
      $attr{$sdev}{eventMap} = $attrVal;
      my $r = ReplaceEventMap($sdev, "test", 1); # refresh eventMapCmd
      if($r =~ m/^ERROR in eventMap for /) {
        delete($attr{$sdev}{eventMap});
        return $r;
      }
    }

    if($ra{$attrName}) {
      my ($lval,$rp,$cache) = ($attrVal, $ra{$attrName}{p}, $ra{$attrName}{c});

      if($rp && $lval =~ m/$rp/s) {
        my $err = perlSyntaxCheck($attrVal, %{$ra{$attrName}{pv}});
        return "attr $sdev $attrName: $err" if($err);

      } else {
        delete $hash->{$cache} if( $cache );

        my @a = split($ra{$attrName}{s}, $lval) ;
        for my $v (@a) {
          my $v = $v; # resolve the reference to avoid changing @a itself
          if($ra{$attrName}{isNum}) {
            my @va = split(":", $v);
            return "attr $sdev $attrName $v: argument is not a number"
                if(!defined($va[1]) || !looks_like_number($va[1]));
          }
          $v =~ s/$ra{$attrName}{r}// if($ra{$attrName}{r});
          my $err ="Argument $v for attr $sdev $attrName is not a valid regexp";
          return "$err: use .* instead of *" if($v =~ /^\*/); # no err in eval!?
          eval { "Hallo" =~ m/^$v$/ };
          return "$err: $@" if($@);
        }
        $hash->{$cache} = \@a if( $cache );
      }
    }

    if($fhemdebug && $sdev eq "global") {
      $attrVal = "-" if($attrName eq "logfile");
      $attrVal = 5   if($attrName eq "verbose");
    }
    $defs{$sdev}->{CL} = $cl;
    my $ci = $attrSource{$attrName} ? $attrSource{$attrName}{ci} : undef;
    $ret = CallFn($ci || $sdev, "AttrFn", "set", $sdev, $attrName, $attrVal);
    delete($defs{$sdev}->{CL});
    if($ret) {
      push @rets, $ret;
      next;
    }

    $attr{$sdev}{$attrName} = $attrVal;

    if($attrName eq "IODev") {
      my $ret = fhem_setIoDev($hash, $attrVal);
      if($ret) {
        push @rets, $ret if($init_done);
        next;
      }
    }

    if($attrName eq "stateFormat" && $init_done) {
      my $err = perlSyntaxCheck($attrVal, ("%name"=>""));
      return $err if($err);
      evalStateFormat($hash);
    }
    addStructChange("attr", $sdev, "$sdev $attrName $attrVal")
        if(!$opt{silent} && (!defined($oVal) || $oVal ne $attrVal));
    DoTrigger("global", "ATTR $sdev $attrName $attrVal", 1) if($init_done);

  }

  Log 3, join(" ", @rets) if(!$cl && @rets);
  return join("\n", @rets);
}

# fhem.pl lines 2761-2824 at the pinned revision.
sub CommandReload($$;$)
{
  my ($cl, $param, $ignoreErr) = @_;
  my %hash;
  $param =~ s,/,,g;
  $param =~ s,\.pm$,,g;
  my $file = "$attr{global}{modpath}/FHEM/$param.pm";
  my $cfgDB = '-';
  if( ! -r "$file" ) {
    if(configDBUsed()) {
      # try to find the file in configDB
      my $r = _cfgDB_Fileexport($file); # create file temporarily
      return "Can't read $file from configDB." if ($r =~ m/^0/);
      $cfgDB = 'X';
    } else {
      # configDB not used and file not found: it's a real error!
      return "Can't read $file";
    }
  }

  my $m = $param;
  $m =~ s,^([0-9][0-9])_,,;
  my $order = (defined($1) ? $1 : "00");
  Log 5, "Loading $file";

  no strict "refs";
  my $ret = eval {
    my $ret=do "$file";
    unlink($file) if($cfgDB eq 'X'); # delete temp file
    if(!$ret) {
      Log 1, "reload: Error:Modul $param deactivated:\n $@" if(!$ignoreErr);
      return $@;
    }

    # Get the name of the initialize function. This may differ from the
    # filename as sometimes we live on a FAT fs with wrong case.
    my $fnname = $m;
    foreach my $i (keys %main::) {
      if($i =~ m/^(${m})_initialize$/i) {
        $fnname = $1;
        last;
      }
    }
    &{ "${fnname}_Initialize" }(\%hash);
    $m = $fnname;
    return undef;
  };
  use strict "refs";

  return "$@" if($@);
  return $ret if($ret);

  my ($defptr, $ldata);
  if($modules{$m}) {
    $defptr = $modules{$m}{defptr};
    $ldata = $modules{$m}{ldata};
  }
  $modules{$m} = \%hash;
  $modules{$m}{ORDER} = $order;
  $modules{$m}{LOADED} = 1;
  $modules{$m}{defptr} = $defptr if($defptr);
  $modules{$m}{ldata} = $ldata if($ldata);

  return undef;
}

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
