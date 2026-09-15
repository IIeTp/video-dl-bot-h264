#!/bin/sh
# CI smoke test, runs INSIDE the built image.
#
#   check-patched-bot.sh --offline   deterministic gates only (no network)
#   check-patched-bot.sh [url]       same, plus an informational resolution of [url]
#
# Deterministic gates prove the image is what we think it is:
#   1. the binary carries upstream's standard format selector and no codec override,
#   2. the bot binary runs.
# The network part only reports what the standard selector resolves to - it asserts nothing
# about the codec, because format selection is intentionally left to upstream.

set -eu

OFFLINE=0
case "${1:-}" in
    --offline) OFFLINE=1 ;;
esac
URL="${2:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"

# upstream's selector, kept in sync by gate 1 below (if upstream changes it, gate 1 fails)
STD_SELECTOR="bv*[ext=mp4][filesize<2G]+ba[ext=m4a][filesize<2G]/bv*[ext=mp4]+ba[ext=m4a]/best[filesize<2G]/best"

fail() { echo "FAIL: $1" >&2; exit 1; }

# ---- gate 1: standard selector in, codec override out -------------------------------
STD_SELECTOR="$STD_SELECTOR" python3 - <<'PY'
import os, sys
blob = open("/bin/video-dl-bot", "rb").read()

std = os.environ["STD_SELECTOR"].encode()
if std not in blob:
    sys.exit("FAIL: upstream's standard selector is not compiled into the binary")

if b"vcodec^=avc1" in blob:
    sys.exit("FAIL: an H.264 selector override is compiled in - the codec patch was removed")

print("OK: binary carries upstream's standard selector, no codec override")
PY

# ---- gate 2: the bot starts ---------------------------------------------------------
/bin/video-dl-bot --version >/dev/null || fail "the bot binary does not run"
echo "OK: bot binary runs"

[ "$OFFLINE" = "1" ] && { echo "OK (offline gates passed)"; exit 0; }

# ---- informational: what the standard selector picks --------------------------------
command -v python3 >/dev/null 2>&1 || fail "python3 is required by this check"

yt-dlp --version
json="$(yt-dlp --simulate -J --no-warnings --format "$STD_SELECTOR" "$URL")"
printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("standard selector resolved: ext=%s vcodec=%s acodec=%s" % (d.get("ext"), d.get("vcodec"), d.get("acodec")))
print("note: AV1/VP9 here means Telegram will deliver such videos as documents - accepted by choice")
'