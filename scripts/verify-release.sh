#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

source_version=$(sed -n "s/^my \\\$WATTPILOT_VERSION = '\([^']*\)';/\1/p" 72_Wattpilot.pm)
version=${1:-$source_version}
[ "$version" = "$source_version" ] || { echo "Requested version differs from source" >&2; exit 1; }

package="Wattpilot_v$version"
package_dir="dist/$package"
standalone="dist/72_Wattpilot_v$version.pm"
archive="dist/$package.zip"

for path in "$standalone" "$package_dir/72_Wattpilot.pm" "$package_dir/MANIFEST" \
    "$package_dir/SHA256SUMS" "$archive" "$archive.sha256"; do
    [ -f "$path" ] || { echo "Missing release artifact: $path" >&2; exit 1; }
done

sh scripts/ci.sh
perl -I t/lib -c "$standalone"
perl -I t/lib -c "$package_dir/72_Wattpilot.pm"

expected=$(mktemp)
actual=$(mktemp)
zip_module=$(mktemp)
trap 'rm -f "$expected" "$actual" "$zip_module"' EXIT HUP INT TERM

(
    cd "$package_dir"
    find . -type f -print | sed 's#^./##' | LC_ALL=C sort
) > "$actual"
LC_ALL=C sort "$package_dir/MANIFEST" > "$expected"
cmp "$expected" "$actual"

(cd "$package_dir" && sha256sum -c SHA256SUMS)
unzip -tqq "$archive"
sha256sum -c "$archive.sha256"

cmp 72_Wattpilot.pm "$standalone"
cmp 72_Wattpilot.pm "$package_dir/72_Wattpilot.pm"
unzip -p "$archive" "$package/72_Wattpilot.pm" > "$zip_module"
cmp 72_Wattpilot.pm "$zip_module"

grep -F "## [v$version]" CHANGELOG.md >/dev/null
grep -F '"version": "v'"$version"'"' 72_Wattpilot.pm >/dev/null
grep -F "version=$version" "$package_dir/validation-build.txt" >/dev/null

echo "Release verification passed for $package"
