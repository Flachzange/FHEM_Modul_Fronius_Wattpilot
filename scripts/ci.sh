#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

perl -I t/lib -c 72_Wattpilot.pm
PERL5LIB=t/lib prove -v t/*.t
perl scripts/check_meta.pl
perl scripts/check_commandref.pl
perl scripts/check_repository.pl
