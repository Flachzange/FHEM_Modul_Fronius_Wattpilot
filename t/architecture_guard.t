use strict;
use warnings;

use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..'));
my $module = File::Spec->catfile($root, '72_Wattpilot.pm');
open my $module_fh, '<:encoding(UTF-8)', $module or die "Cannot read $module: $!";
local $/;
my $source = <$module_fh>;
close $module_fh;
my ($runtime) = split /\n1;\n/, $source, 2;

my @removed_helpers = qw(
    Wattpilot_LegacySecretKey
    Wattpilot_LegacyOwnerKey
    Wattpilot_ReadOwnedLegacySecret
    Wattpilot_GetOwnedLegacyResourceKeys
    Wattpilot_PendingLegacyKey
    Wattpilot_ReadPendingLegacyNames
    Wattpilot_WritePendingLegacyNames
    Wattpilot_AddPendingLegacyName
    Wattpilot_RemovePendingLegacyName
    Wattpilot_ReadCurrentOwnedLegacySecret
    Wattpilot_CleanupLegacyLocator
    Wattpilot_MigrateLegacySecret
    Wattpilot_CleanupPendingLegacySecrets
    Wattpilot_MigrateLegacySecrets
);

for my $helper (@removed_helpers) {
    unlike($runtime, qr/\b\Q$helper\E\b/,
        "$helper is absent from executable module code");
}

unlike($runtime, qr/pending_legacy_(?:password|passwordhash)_names/,
    'runtime constructs no pending legacy-name metadata key');
unlike($runtime, qr/_password(?:hash)?_owner/,
    'runtime constructs no legacy owner-marker key');
unlike($runtime, qr/"Wattpilot_"\s*\.\s*(?:\$name|\$hash->\{NAME\})/,
    'runtime constructs no credential key from a mutable device name');
unlike($runtime, qr/include_owned_current|\bmigrate\s*=>/,
    'stable credential getter has no migration options');
like($runtime,
    qr/sub\s+Wattpilot_SecretKey.*?\$fuuid\s*=\s*\$hash->\{FUUID\}.*?return\s+"Wattpilot_"\s*\.\s*\$fuuid/s,
    'stable credential key construction is anchored to FUUID');

my @test_files;
find(sub {
    return if !-f $_;
    push @test_files, $File::Find::name if /\.(?:t|pm)\z/;
}, File::Spec->catdir($root, 't'));
my $test_source = '';
for my $path (@test_files) {
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    $test_source .= <$fh>;
    close $fh;
}
for my $helper (@removed_helpers) {
    unlike($test_source, qr/(?:main::)?\Q$helper\E\s*\(/,
        "tests do not call removed helper $helper");
}

done_testing;
