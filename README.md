# video-dl-bot-h264

Telegram video bot built **from upstream source with two patches on top**, so that downloaded
videos are playable and streamable in Telegram instead of arriving as a file that must be
downloaded first.

Upstream: [`tarampampam/video-dl-bot`](https://github.com/tarampampam/video-dl-bot) (MIT).

## What the patches change

`patches/0001-streamable-h264-video.patch`

1. **Streamable `sendVideo`** (`internal/bot/bot.go`). Upstream sends
   `tele.Video{File: tele.FromReader(fp)}` — no `supports_streaming`, no dimensions, no duration.
   Telegram clients answer that with a **download button** instead of streaming. The patch sets
   `Streaming: true` and fills `Width`/`Height` (parsed from the yt-dlp `resolution` field) and
   `Duration` (already parsed by the bot).
2. **H.264 instead of AV1** (`internal/yt-dlp/yt-dlp.go`). Upstream's selector
   `bv*[ext=mp4][filesize<2G]+ba[ext=m4a].../best` resolves on YouTube to **AV1** (format `401`,
   `av01.*`) inside an mp4 container. Telegram cannot decode AV1, so the Bot API degrades the
   upload to a *document* — the file arrives without a player. The patch forces
   `bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4][vcodec^=avc1]/b[ext=mp4]/b` plus
   `--merge-output-format mp4`, which selects H.264/AAC in mp4.

Measured, upstream selector vs patched selector on the same YouTube URL:

```
mp4 | av01.0.12M.08 | mp4a.40.2 | 401+140     <- container is mp4, codec is AV1 (Telegram: document)
mp4 | avc1.640028   | mp4a.40.2 | 137+140     <- H.264/AAC (Telegram: plays, and now streams)
```

## How the upstream stays updated (and the patch cannot be clobbered)

This repository stores **no upstream source**. Every build:

1. checks out `tarampampam/video-dl-bot@master` fresh,
2. applies `patches/*.patch` with `git apply --3way`,
3. builds the image from that source with upstream's own `Dockerfile`.

So upstream code, yt-dlp, ffmpeg, node and the Go toolchain all come straight from upstream — only
the lines the patch touches are ours. If upstream rewrites those lines, the patch stops applying and
the **build fails before publishing anything** (no silent regression, no rebase babysitting). A
daily cron re-runs the build, and an unchanged upstream yields the same image.

## CI gates

* **patch applies** — a moved line upstream fails the build loudly.
* **bot runs** — `docker run --rm <image> --version`.
* **patch compiled in** — the built binary must contain the forced H.264 selector, and must no
  longer contain upstream's AV1-prone selector.
* **selector resolves** — a real URL must resolve to `ext=mp4` + `vcodec=avc1*` (informational: it
  needs YouTube reachable from the runner, and reports `::warning::` rather than failing when not).

Tags: `latest`, `sha-<our commit>`, `upstream-<upstream commit>` — the last one makes it obvious
which upstream revision an image was built from, and gives you a rollback target.

## Using it on MikroTik RouterOS (`/app`)

```yaml
name: tg-ytdl
category: utilities
'default-credentials': none
descr: 'Telegram bot: send a link, get a streaming video (yt-dlp, H.264/AAC mp4)'
page: 'https://github.com/IIeTp/video-dl-bot-h264'
services:
  'bot':
    dns: '8.8.8.8'
    environment:
      'BOT_TOKEN': '<token>'
    hostname: 'tg-ytdl'
    image: 'ghcr.io/iietp/video-dl-bot-h264:latest'
    volumes:
      - 'tg-ytdl/data:/data'
```

Gotchas learned the hard way:

* **Changing the image of an existing app** requires re-adding it — `container-command-lines` is
  derived from the YAML only at `/app/add` time, so `/app/set yaml=...` keeps the old image, and
  setting `container-command-lines` by hand double-prefixes the container name
  (`download/extract failed`). Procedure: `/app/disable` → wait → `/app/remove` → `/app/add` →
  `/app/enable`. For a newer build of the *same* image, `/app/update <app>` is enough.
* **Package visibility**: GHCR creates the package private even when the repository is public, and
  the package REST API accepts **classic PATs only** (`gh` OAuth tokens and `GITHUB_TOKEN` get 404).
  RouterOS pulls anonymously, so the package must be set to Public once in the package's own
  settings page (Danger Zone → Change visibility) — irreversibly. Alternative: keep it private and
  put a classic PAT with `read:packages` into `/container/config`.
* Making the package public drops the write access inherited from the repository, so
  `GITHUB_TOKEN` pushes then fail with `denied: permission_denied: write_package`. Either re-add the
  repository under the package's *Manage Actions access* with role **Write**, or add a repository
  secret `GHCR_PAT` (classic PAT, `write:packages`) — the workflow prefers it automatically.

## Adding another patch

```sh
git clone https://github.com/tarampampam/video-dl-bot && cd video-dl-bot
# edit, keep the diff minimal
git diff > ../video-dl-bot-h264/patches/0002-something.patch
```

Keep one commit's worth of change per patch and keep the diff small — that is what keeps the patch
applying cleanly across upstream releases.

## License

MIT, same as upstream.