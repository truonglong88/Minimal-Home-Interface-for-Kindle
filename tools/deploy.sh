#!/bin/sh
# Copy the plugin (and screensaver images) to a Kindle over SSH.
#
# On the Kindle: KOReader menu → Network → SSH server → Start SSH server.
# Usage: tools/deploy.sh 192.168.1.25
set -eu

HOST="${1:?usage: tools/deploy.sh <kindle-ip> [port]}"
PORT="${2:-2222}"
KOREADER_DIR="${KOREADER_DIR:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$KOREADER_DIR" ]; then
    # find KOReader on the device (usually /mnt/us/koreader)
    KOREADER_DIR="$(ssh -p "$PORT" "root@$HOST" \
        'for d in /mnt/us/koreader /mnt/us/extensions/koreader; do [ -f "$d/reader.lua" ] && echo "$d" && exit; done;
         find /mnt/us -maxdepth 3 -name reader.lua 2>/dev/null | head -n 1 | xargs -r dirname')"
fi
[ -n "$KOREADER_DIR" ] || { echo "KOReader not found on the device"; exit 1; }
echo "KOReader at $KOREADER_DIR"

# Copy by streaming a tar archive over SSH: plain scp hangs against KOReader's
# SSH server on some setups. COPYFILE_DISABLE stops macOS adding "._" files.
echo "→ plugin"
(cd "$ROOT" && COPYFILE_DISABLE=1 tar -czf - minimalhome.koplugin) | ssh -p "$PORT" "root@$HOST" \
    "rm -rf '$KOREADER_DIR/plugins/minimalhome.koplugin' && cd '$KOREADER_DIR/plugins' && tar -xzf -"

# (screensaver pictures ship inside the plugin folder)

echo "Done. Restart KOReader to load the new version."
