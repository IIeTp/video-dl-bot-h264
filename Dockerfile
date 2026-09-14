# Wrapper around the upstream bot image.
#
# Why a wrapper and not a fork of the source:
#   * nothing from upstream lives in this repo, so there is nothing to sync/rebase/merge
#   * the base is a floating tag + `--pull`, so every build picks up the newest upstream
#     release and all upstream changes flow through untouched
#   * the only thing this repo owns is one runtime shim, which can never be clobbered
#
# What it fixes: upstream hardcodes the yt-dlp format selector
#   bv*[ext=mp4][filesize<2G]+ba[ext=m4a].../best
# which on YouTube resolves to AV1 (av01.*) inside an mp4 container. Telegram cannot
# play AV1, so sendVideo degrades to a plain file. The shim appends a second --format
# (last one wins in yt-dlp) that prefers H.264/AAC, plus --merge-output-format mp4.

FROM ghcr.io/tarampampam/video-dl-bot:latest

ARG BASE_DIGEST="unknown"

LABEL org.opencontainers.image.title="video-dl-bot-h264" \
      org.opencontainers.image.description="Telegram yt-dlp bot wrapper: guarantees Telegram-playable H.264/AAC MP4" \
      org.opencontainers.image.source="https://github.com/IIeTp/video-dl-bot-h264" \
      org.opencontainers.image.base.name="ghcr.io/tarampampam/video-dl-bot:latest" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      org.opencontainers.image.licenses="MIT"

USER root
COPY --chmod=0755 entrypoint.sh /opt/entrypoint.sh
USER 10001:10001

# H.264 video + AAC audio when available; mp4-only fallbacks so Telegram never gets webm/mkv.
ENV YTDLP_FORMAT_OVERRIDE="bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1]/b[ext=mp4]/b" \
    YTDLP_EXTRA_ARGS="--merge-output-format mp4"

ENTRYPOINT ["/opt/entrypoint.sh"]
