#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

source_version=$(awk -F"'" '/^my \$WATTPILOT_VERSION = / { print $2; exit }' 72_Wattpilot.pm)
version=${1:-$source_version}
[ "$version" = "$source_version" ] || { echo "Requested version differs from source" >&2; exit 1; }

release_files=scripts/release-files.txt
[ -f "$release_files" ] || { echo "Missing release file manifest: $release_files" >&2; exit 1; }

package="Wattpilot_v$version"
package_dir="dist/$package"
standalone="dist/72_Wattpilot_v$version.pm"
archive="dist/$package.zip"

for path in "$standalone" "$package_dir/MANIFEST" "$package_dir/SHA256SUMS" "$archive" "$archive.sha256"; do
    [ -f "$path" ] || { echo "Missing release artifact: $path" >&2; exit 1; }
done

if [ "${WATTPILOT_SKIP_SOURCE_CI:-0}" != 1 ]; then
    sh scripts/ci.sh
fi
perl -I t/lib -c "$standalone"
perl -I t/lib -c "$package_dir/72_Wattpilot.pm"

expected=$(mktemp)
actual=$(mktemp)
manifest_sorted=$(mktemp)
zip_extract=$(mktemp -d)
trap 'rm -f "$expected" "$actual" "$manifest_sorted"; rm -rf "$zip_extract"' EXIT HUP INT TERM

{
    sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d' "$release_files"
    printf '%s\n' validation-ci.txt validation-build.txt MANIFEST SHA256SUMS
} | LC_ALL=C sort -u > "$expected"

(
    cd "$package_dir"
    find . -type f -print | sed 's#^./##' | LC_ALL=C sort
) > "$actual"
cmp "$expected" "$actual"
LC_ALL=C sort "$package_dir/MANIFEST" > "$manifest_sorted"
cmp "$expected" "$manifest_sorted"

(cd "$package_dir" && sha256sum -c SHA256SUMS)
unzip -tqq "$archive"
sha256sum -c "$archive.sha256"
unzip -qq "$archive" -d "$zip_extract"

cmp 72_Wattpilot.pm "$standalone"
while IFS= read -r path || [ -n "$path" ]; do
    case "$path" in ''|'#'*) continue ;; esac
    [ -f "$package_dir/$path" ] || { echo "Missing packaged source: $package_dir/$path" >&2; exit 1; }
    cmp "$path" "$package_dir/$path"
    cmp "$path" "$zip_extract/$package/$path"
done < "$release_files"

for generated in validation-ci.txt validation-build.txt MANIFEST SHA256SUMS; do
    cmp "$package_dir/$generated" "$zip_extract/$package/$generated"
done

grep -F "## [v$version]" CHANGELOG.md >/dev/null
grep -F '"version": "v'"$version"'"' 72_Wattpilot.pm >/dev/null
grep -F "version=$version" "$package_dir/validation-build.txt" >/dev/null

echo "Release verification passed for $package"
