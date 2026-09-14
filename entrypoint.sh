#!/bin/sh
# Entrypoint wrapper: makes sure every yt-dlp invocation inside the bot produces a
# container/codec pair that Telegram can actually play (H.264 + AAC in MP4).
#
# How it works:
#   * the bot locates the yt-dlp binary with exec.LookPath("yt-dlp"), i.e. via PATH
#   * yt-dlp is an argparse CLI where the LAST --format wins, and options may follow the URL
#   => a shim earlier in PATH that appends `--format <h264> --merge-output-format mp4`
#      overrides the selector hardcoded in the bot, without patching any upstream code.
#
# Optional knobs (defaults are production values):
#   YTDLP_FORMAT_OVERRIDE  yt-dlp format selector to force (default: H.264/AAC first)
#   YTDLP_EXTRA_ARGS       extra yt-dlp args appended after the selector
#   YTDLP_BIN              real yt-dlp binary the shim must call (default: /bin/yt-dlp)
#   BOT_BINARY             binary to exec instead of the bot (used by the CI smoke test)

set -eu

FORMAT="${YTDLP_FORMAT_OVERRIDE:-bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1]/b[ext=mp4]/b}"
EXTRA="${YTDLP_EXTRA_ARGS:---merge-output-format mp4}"
BIN="${YTDLP_BIN:-/bin/yt-dlp}"

# never let an override break out of the generated shim script
OVERRIDE="${FORMAT}${EXTRA}${BIN}"
BAD=""
case "$OVERRIDE" in *'"'*) BAD=quote ;; *"'"*) BAD=quote ;; esac
if [ "$(printf '%s' "$OVERRIDE" | wc -l)" -gt 0 ]; then BAD=newline; fi
if [ -n "$BAD" ]; then
    echo "entrypoint: YTDLP_* values must not contain quotes or newlines" >&2
    exit 1
fi

SHIM_DIR="${TMPDIR:-/tmp}/yt-dlp-shim"
mkdir -p "$SHIM_DIR"

cat > "$SHIM_DIR/yt-dlp" <<EOF
#!/bin/sh
exec "$BIN" "\$@" --format "$FORMAT" $EXTRA
EOF
chmod 0755 "$SHIM_DIR/yt-dlp"

PATH="$SHIM_DIR:$PATH"
export PATH

exec "${BOT_BINARY:-/bin/video-dl-bot}" "$@"
