#!/bin/sh
# Puts AetherEngine at the pinned version in Vendor/AetherEngine, with the app's patches applied
# (Patches/AetherEngine/*.patch, in name order). Run before `xcodegen generate`; CI does.
#
# The patches are kept small and on top of an upstream tag, so moving to a new engine version is
# changing AETHER_ENGINE_VERSION and checking that they still apply.
set -eu

VERSION="${AETHER_ENGINE_VERSION:-7.54.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/AetherEngine"
STAMP="$DEST/.aiostreams-prepared"
WANT="$VERSION $(cat "$ROOT"/Patches/AetherEngine/*.patch | git hash-object --stdin)"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANT" ]; then
  echo "AetherEngine $VERSION already prepared"
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$ROOT/Vendor"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$VERSION" \
  https://github.com/superuser404notfound/AetherEngine "$DEST"
for patch in "$ROOT"/Patches/AetherEngine/*.patch; do
  git -C "$DEST" apply --whitespace=nowarn "$patch"
  echo "applied $(basename "$patch")"
done
echo "$WANT" > "$STAMP"
echo "AetherEngine $VERSION prepared in Vendor/AetherEngine"
