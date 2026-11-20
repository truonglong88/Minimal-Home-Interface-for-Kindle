#!/bin/sh
# Build dist/minimalhome-<version>.zip, ready to unzip into koreader/plugins/,
# and dist/latest.json, which the in-app updater reads.
# Every build raises the patch number in _meta.lua first (0.1.0 → 0.1.1), so the
# zip name and the version shown in Settings always match.
# The zip carries build.lua with its update channel: dev (default) or stable.
# Usage: tools/package.sh                                 bump, then build (dev)
#        tools/package.sh --no-bump --channel stable      build the current version (release CI)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
META="$ROOT/minimalhome.koplugin/_meta.lua"
BUMP=1
CHANNEL=dev
while [ $# -gt 0 ]; do
    case "$1" in
        --no-bump) BUMP=0 ;;
        --channel) CHANNEL="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$CHANNEL" in dev|stable) ;; *) echo "channel must be dev or stable" >&2; exit 2 ;; esac
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' "$META")"
if [ "$BUMP" = 1 ]; then
    VERSION="$(echo "$VERSION" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')"
    sed -i.bak "s/version = \"[^\"]*\"/version = \"$VERSION\"/" "$META" && rm -f "$META.bak"
fi
mkdir -p "$ROOT/dist"
NAME="minimalhome-$VERSION.zip"
OUT="$ROOT/dist/$NAME"
rm -f "$OUT" "$ROOT/dist/latest.json"
cd "$ROOT"
BUILD="minimalhome.koplugin/build.lua"
printf 'return { channel = "%s" }\n' "$CHANNEL" > "$BUILD"
zip -qr "$OUT" minimalhome.koplugin -x '*.DS_Store'
rm -f "$BUILD"
if command -v sha256sum >/dev/null 2>&1; then SUM="$(sha256sum "$OUT" | cut -d' ' -f1)"
else SUM="$(shasum -a 256 "$OUT" | cut -d' ' -f1)"; fi
SIZE="$(wc -c < "$OUT" | tr -d ' ')"
printf '{"version":"%s","file":"%s","sha256":"%s","size":%s,"channel":"%s"}\n' \
    "$VERSION" "$NAME" "$SUM" "$SIZE" "$CHANNEL" > "$ROOT/dist/latest.json"
echo "$OUT"
