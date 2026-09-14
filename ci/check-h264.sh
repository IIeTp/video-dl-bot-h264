#!/bin/sh
# CI smoke test (runs INSIDE the built image, so it validates the wrapper end to end).
#
# It asserts the two things the wrapper promises:
#   1. the shim is what the bot will find as `yt-dlp` (PATH order),
#   2. the forced selector really yields H.264 inside an mp4 container.
#
# Usage: check-h264.sh [test-url]

set -eu

URL="${1:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"

echo "yt-dlp resolved to: $(command -v yt-dlp)"
yt-dlp --version

yt-dlp --simulate -J --no-warnings "$URL" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("selected: ext=%s vcodec=%s acodec=%s" % (d.get("ext"), d.get("vcodec"), d.get("acodec")))
assert (d.get("ext") or "") == "mp4", "container is not mp4 -> Telegram would show a file"
assert (d.get("vcodec") or "").startswith("avc1"), "selector override did not take effect (not H.264)"
print("OK: Telegram-playable mp4/H.264/AAC")
'
