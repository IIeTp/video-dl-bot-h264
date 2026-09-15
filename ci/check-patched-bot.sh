#!/bin/sh
# CI smoke test, runs INSIDE the built image.
#
#   check-patched-bot.sh --offline   deterministic gates only (no network)
#   check-patched-bot.sh [url]       same, plus a real yt-dlp resolution of [url]
#
# Offline gates prove the image really carries our patches:
#   1. the video-dl-bot binary contains the forced H.264 selector (yt-dlp patch),
#   2. the bot binary starts.
# The network part proves that selector yields Telegram-playable H.264/mp4 in practice.

set -eu

OFFLINE=0
case "${1:-}" in
    --offline) OFFLINE=1 ;;
esac
URL="${2:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"

fail() { echo "FAIL: $1" >&2; exit 1; }

# ---- gate 1: the patched selector is compiled into the bot binary -------------------
python3 - <<'PY'
import sys
blob = open("/bin/video-dl-bot", "rb").read()

needle = b"vcodec^=avc1"
if needle not in blob:
    sys.exit("FAIL: the H.264 selector patch is missing from the built binary")

stale = b"bv*[ext=mp4][filesize<2G]+ba[ext=m4a][filesize<2G]"
if stale in blob:
    sys.exit("FAIL: the upstream AV1-prone selector is still compiled in")

print("OK: patched H.264 selector is compiled into the bot binary")
PY

# ---- gate 2: the bot starts ---------------------------------------------------------
/bin/video-dl-bot --version >/dev/null || fail "the bot binary does not run"
echo "OK: bot binary runs"

[ "$OFFLINE" = "1" ] && { echo "OK (offline gates passed)"; exit 0; }

# ---- gate 3: the selector resolves to H.264/mp4 in practice -------------------------
command -v python3 >/dev/null 2>&1 || fail "python3 is required by this check"
[ -d /patches ] || fail "/patches is not mounted"

SELECTOR="$(python3 - <<'PY'
import glob, re, sys
pat = re.compile(r'\+\s*"--format",\s*"([^"]+)"')
for path in sorted(glob.glob("/patches/*.patch")):
    m = pat.search(open(path).read())
    if m:
        print(m.group(1))
        break
else:
    sys.exit("could not read the forced selector out of the patch file")
PY
)"
echo "selector from the patch: ${SELECTOR}"

yt-dlp --version
json="$(yt-dlp --simulate -J --no-warnings --format "$SELECTOR" "$URL")"
printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
ext, vcodec, acodec = d.get("ext"), d.get("vcodec"), d.get("acodec")
print("resolved: ext=%s vcodec=%s acodec=%s" % (ext, vcodec, acodec))
assert ext == "mp4", "container is not mp4 -> Telegram would send a file"
assert (vcodec or "").startswith("avc1"), "selector did not pick H.264"
assert (acodec or "").startswith("mp4a"), "audio is not AAC"
print("OK: Telegram-playable mp4/H.264/AAC")
'