#!/bin/sh
# The iOS side of this package is built from the iOS SDK's own sources, copied in so the package is self-contained.
# Run it after changing sdk/ios.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
from="$here/../ios/Sources"
to="$here/ios/Zapiack"
rm -rf "$to"
mkdir -p "$to"
for f in "$from"/ZapiackCore/*.swift "$from"/ZapiackPush/*.swift; do
  grep -v -e '^import ZapiackCore$' -e '^public typealias ' "$f" > "$to/$(basename "$f")"
done
echo "copied $(ls "$to" | wc -l | tr -d ' ') files"
