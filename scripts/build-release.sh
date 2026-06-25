#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

version=$(awk -F"'" '/^my \$WATTPILOT_VERSION = / { print $2; exit }' 72_Wattpilot.pm)
[ -n "$version" ] || { echo "Cannot determine module version" >&2; exit 1; }

release_files=scripts/release-files.txt
[ -f "$release_files" ] || { echo "Missing release file manifest: $release_files" >&2; exit 1; }

epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
package="Wattpilot_v$version"
package_dir="dist/$package"
standalone="dist/72_Wattpilot_v$version.pm"
archive="dist/$package.zip"

rm -rf dist
mkdir -p "$package_dir"

if [ "${WATTPILOT_SKIP_SOURCE_CI:-0}" = 1 ]; then
    printf '%s\n' 'source_ci=prevalidated' > "$package_dir/validation-ci.txt"
else
    ci_raw="$package_dir/.validation-ci.raw"
    if ! sh scripts/ci.sh > "$ci_raw" 2>&1; then
        cat "$ci_raw"
        exit 1
    fi
    sed -E 's/^(Files=[0-9]+, Tests=[0-9]+),.*$/\1/' "$ci_raw" > "$package_dir/validation-ci.txt"
    rm "$ci_raw"
fi
cat "$package_dir/validation-ci.txt"

while IFS= read -r file || [ -n "$file" ]; do
    case "$file" in ''|'#'*) continue ;; esac
    [ -f "$file" ] || { echo "Missing release source: $file" >&2; exit 1; }
    mkdir -p "$package_dir/$(dirname "$file")"
    cp "$file" "$package_dir/$file"
done < "$release_files"
cp 72_Wattpilot.pm "$standalone"

cat > "$package_dir/validation-build.txt" <<EOF2
version=$version
source_date_epoch=$epoch
source_commit=$(git rev-parse HEAD)
EOF2

{
    sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d' "$release_files"
    printf '%s\n' validation-ci.txt validation-build.txt MANIFEST SHA256SUMS
} | LC_ALL=C sort -u > "$package_dir/MANIFEST"

(
    cd "$package_dir"
    while IFS= read -r file; do
        [ "$file" = SHA256SUMS ] && continue
        sha256sum "$file"
    done < MANIFEST
) > "$package_dir/SHA256SUMS"

find dist -exec touch -d "@$epoch" {} +
perl scripts/create_zip.pl "$package_dir" "$archive" "$epoch"
sha256sum "$archive" > "$archive.sha256"

if ! WATTPILOT_SKIP_SOURCE_CI=1 sh scripts/verify-release.sh "$version" > "dist/verification-output.txt" 2>&1; then
    cat "dist/verification-output.txt"
    exit 1
fi
cat "dist/verification-output.txt"

printf 'Release artifacts created:\n%s\n%s\n%s\n' "$standalone" "$archive" "$archive.sha256"
sha256sum "$standalone" "$archive"
