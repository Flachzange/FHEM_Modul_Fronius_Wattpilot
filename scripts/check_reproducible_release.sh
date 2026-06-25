#!/usr/bin/env sh
set -eu

script_dir=${0%/*}
[ "$script_dir" = "$0" ] && script_dir=.
cd "$script_dir/.."

version=$(awk -F"'" '/^my \$WATTPILOT_VERSION = / { print $2; exit }' 72_Wattpilot.pm)
[ -n "$version" ] || { echo "Cannot determine module version" >&2; exit 1; }

epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}
archive="dist/Wattpilot_v$version.zip"

if [ "${WATTPILOT_SKIP_SOURCE_CI:-0}" != 1 ]; then
    sh scripts/ci.sh
fi

SOURCE_DATE_EPOCH=$epoch WATTPILOT_SKIP_SOURCE_CI=1 sh scripts/build-release.sh
first=$(sha256sum "$archive" | awk '{print $1}')

SOURCE_DATE_EPOCH=$epoch WATTPILOT_SKIP_SOURCE_CI=1 sh scripts/build-release.sh
second=$(sha256sum "$archive" | awk '{print $1}')

if [ "$first" != "$second" ]; then
    echo "Reproducibility check failed: $first != $second" >&2
    exit 1
fi

echo "Reproducible release check passed (SOURCE_DATE_EPOCH=$epoch, ZIP SHA-256=$second)"
