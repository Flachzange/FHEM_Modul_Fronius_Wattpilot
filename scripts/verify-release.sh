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
    "$package_dir/SHA256SUMS" "$package_dir/docs/PROTOCOL-SOURCES.md" \
    "$package_dir/docs/PROTOCOL-CONFLICTS.md" \
    "$package_dir/docs/WATTPILOT-FLEX-JSON-API.md" \
    "$package_dir/t/fixtures/README.md" \
    "$package_dir/t/fixtures/fullStatus-flex-observed.json" \
    "$archive" "$archive.sha256"; do
    [ -f "$path" ] || { echo "Missing release artifact: $path" >&2; exit 1; }
done

sh scripts/ci.sh
perl -I t/lib -c "$standalone"
perl -I t/lib -c "$package_dir/72_Wattpilot.pm"

expected=$(mktemp)
actual=$(mktemp)
zip_module=$(mktemp)
zip_protocol_doc=$(mktemp)
zip_protocol_conflicts=$(mktemp)
zip_observed_fixture=$(mktemp)
trap 'rm -f "$expected" "$actual" "$zip_module" "$zip_protocol_doc" "$zip_protocol_conflicts" "$zip_observed_fixture"' EXIT HUP INT TERM

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
cmp docs/WATTPILOT-FLEX-JSON-API.md "$package_dir/docs/WATTPILOT-FLEX-JSON-API.md"
cmp docs/PROTOCOL-CONFLICTS.md "$package_dir/docs/PROTOCOL-CONFLICTS.md"
cmp t/fixtures/fullStatus-flex-observed.json "$package_dir/t/fixtures/fullStatus-flex-observed.json"
unzip -p "$archive" "$package/docs/WATTPILOT-FLEX-JSON-API.md" > "$zip_protocol_doc"
unzip -p "$archive" "$package/docs/PROTOCOL-CONFLICTS.md" > "$zip_protocol_conflicts"
unzip -p "$archive" "$package/t/fixtures/fullStatus-flex-observed.json" > "$zip_observed_fixture"
cmp docs/WATTPILOT-FLEX-JSON-API.md "$zip_protocol_doc"
cmp docs/PROTOCOL-CONFLICTS.md "$zip_protocol_conflicts"
cmp t/fixtures/fullStatus-flex-observed.json "$zip_observed_fixture"

grep -F "## [v$version]" CHANGELOG.md >/dev/null
grep -F '"version": "v'"$version"'"' 72_Wattpilot.pm >/dev/null
grep -F "version=$version" "$package_dir/validation-build.txt" >/dev/null

echo "Release verification passed for $package"
