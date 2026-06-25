use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));

sub read_text {
    my ($relative) = @_;
    my $path = File::Spec->catfile($root, split m{/}, $relative);
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

my $manifest = read_text('scripts/release-files.txt');
my @release_files = grep { length && !/^\s*#/ }
    map { s/^\s+|\s+$//gr } split /\n/, $manifest;
my %seen;
is(scalar(grep { $seen{$_}++ } @release_files), 0,
    'release source manifest contains no duplicate path');
for my $required (qw(
    72_Wattpilot.pm AUTHORS.md docs/READING-CATEGORIES.md
    docs/WATTPILOT-FLEX-JSON-API.md t/fixtures/fullStatus-flex-observed.json
)) {
    ok(grep($_ eq $required, @release_files),
        "release source manifest contains $required");
}
for my $relative (@release_files) {
    ok(-f File::Spec->catfile($root, split m{/}, $relative),
        "release source exists: $relative");
}

my $build = read_text('scripts/build-release.sh');
my $verify = read_text('scripts/verify-release.sh');
my $repro = read_text('scripts/check_reproducible_release.sh');
my $workflow = read_text('.github/workflows/ci.yml');

like($build, qr/release_files=scripts\/release-files\.txt/,
    'builder consumes the authoritative release source manifest');
like($verify, qr/release_files=scripts\/release-files\.txt/,
    'verifier consumes the authoritative release source manifest');
like($verify, qr/cmp "\$path" "\$package_dir\/\$path"/,
    'verifier byte-compares repository and package copies');
like($verify, qr/cmp "\$path" "\$zip_extract\/\$package\/\$path"/,
    'verifier byte-compares repository and ZIP copies');
like($build, qr/WATTPILOT_SKIP_SOURCE_CI/,
    'builder has an explicit prevalidated source-CI mode');
like($verify, qr/WATTPILOT_SKIP_SOURCE_CI/,
    'verifier has an explicit prevalidated source-CI mode');
like($repro, qr/WATTPILOT_SKIP_SOURCE_CI=1 sh scripts\/build-release\.sh/,
    'reproducibility builds do not recursively rerun source CI');
like($workflow, qr/Run checks\s+run: sh scripts\/ci\.sh/s,
    'workflow runs source CI explicitly once');
like($workflow, qr/Build and verify release\s+run: WATTPILOT_SKIP_SOURCE_CI=1/s,
    'workflow marks release build as prevalidated');
like($workflow, qr/Verify reproducible release\s+run: WATTPILOT_SKIP_SOURCE_CI=1/s,
    'workflow marks reproducibility check as prevalidated');

is(() = $workflow =~ /run: sh scripts\/ci\.sh/g, 1,
    'workflow contains exactly one direct source-CI invocation');

done_testing;
