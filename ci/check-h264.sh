#!/bin/sh
# CI smoke test. Runs INSIDE the built image, so it validates the real artifact.
#
#   check-h264.sh --offline   deterministic contract only (no network)
#   check-h264.sh [url]       same, plus a real resolution that must yield H.264/mp4
#
# The deterministic part is the gate: it proves the wrapper's assumptions still hold
# after an upstream update (PATH lookup wins, the shim really overrides the selector).
# The network part proves the selector yields a Telegram-playable file in practice.

set -eu

OFFLINE=0
if [ "${1:-}" = "--offline" ]; then
    OFFLINE=1
    URL="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
else
    URL="${1:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"
fi

SHIM="$(command -v yt-dlp)"
echo "yt-dlp resolves to: ${SHIM}"

fail() { echo "FAIL: $1" >&2; exit 1; }

[ "$SHIM" = "/tmp/yt-dlp-shim/yt-dlp" ] || fail "shim is not first in PATH"
[ -x "$SHIM" ] || fail "shim is not executable"
grep -qF -- '--format' "$SHIM" || fail "shim does not override --format"
grep -qF 'vcodec^=avc1' "$SHIM" || fail "shim does not force H.264 video"
grep -qF 'acodec^=mp4a' "$SHIM" || fail "shim does not force AAC audio"
grep -qF -- '--merge-output-format mp4' "$SHIM" || fail "shim does not force mp4 merging"
echo "OK: shim injects H.264/AAC + mp4 ahead of the bot's own selector"

if [ "$OFFLINE" = "1" ]; then
    echo "OK (offline gate passed)"
    exit 0
fi

# Network-dependent part.
command -v python3 >/dev/null 2>&1 || fail "python3 is not available in the image (required by this check)"
yt-dlp --version

json="$(yt-dlp --simulate -J --no-warnings "$URL")"
printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ext, vcodec, acodec = d.get("ext"), d.get("vcodec"), d.get("acodec")
print("resolved: ext=%s vcodec=%s acodec=%s" % (ext, vcodec, acodec))
assert ext == "mp4", "container is not mp4 -> Telegram would send a file"
assert (vcodec or "").startswith("avc1"), "selector override did not take effect (not H.264)"
assert (acodec or "").startswith("mp4a"), "audio is not AAC -> Telegram compatibility is not guaranteed"
print("OK: Telegram-playable mp4/H.264/AAC")
'
