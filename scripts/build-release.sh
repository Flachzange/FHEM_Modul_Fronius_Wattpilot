#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

version=$(sed -n "s/^my \\\$WATTPILOT_VERSION = '\([^']*\)';/\1/p" 72_Wattpilot.pm)
[ -n "$version" ] || { echo "Cannot determine module version" >&2; exit 1; }

epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
package="Wattpilot_v$version"
package_dir="dist/$package"
standalone="dist/72_Wattpilot_v$version.pm"
archive="dist/$package.zip"

rm -rf dist
mkdir -p "$package_dir"

ci_raw="$package_dir/.validation-ci.raw"
if ! sh scripts/ci.sh > "$ci_raw" 2>&1; then
    cat "$ci_raw"
    exit 1
fi
sed -E 's/^(Files=[0-9]+, Tests=[0-9]+),.*$/\1/' "$ci_raw" > "$package_dir/validation-ci.txt"
rm "$ci_raw"
cat "$package_dir/validation-ci.txt"

for file in 72_Wattpilot.pm README.md README_en.md CHANGELOG.md TESTING.md REVIEW-CHECKLIST.md LICENSE; do
    cp "$file" "$package_dir/$file"
done
cp 72_Wattpilot.pm "$standalone"

cat > "$package_dir/validation-build.txt" <<EOF
version=$version
source_date_epoch=$epoch
source_commit=$(git rev-parse HEAD)
EOF

(
    cd "$package_dir"
    find . -type f -print | sed 's#^./##' | LC_ALL=C sort
    printf '%s\n' MANIFEST SHA256SUMS
) | LC_ALL=C sort -u > "$package_dir/MANIFEST"

(
    cd "$package_dir"
    find . -type f ! -name SHA256SUMS -print | sed 's#^./##' | LC_ALL=C sort |
        while IFS= read -r file; do sha256sum "$file"; done
) > "$package_dir/SHA256SUMS"

find dist -exec touch -d "@$epoch" {} +
perl scripts/create_zip.pl "$package_dir" "$archive" "$epoch"
sha256sum "$archive" > "$archive.sha256"

sh scripts/verify-release.sh "$version" > "dist/verification-output.txt" 2>&1
cat "dist/verification-output.txt"

printf 'Release artifacts created:\n%s\n%s\n%s\n' "$standalone" "$archive" "$archive.sha256"
sha256sum "$standalone" "$archive"
