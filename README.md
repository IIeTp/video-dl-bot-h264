# video-dl-bot-h264

Telegram video bot built **from upstream source with one patch on top**: videos are sent as
*streamable* Telegram videos (with dimensions and duration) instead of files that must be
downloaded before they play.

Upstream: [`tarampampam/video-dl-bot`](https://github.com/tarampampam/video-dl-bot) (MIT).

> The `-h264` suffix is historical: an earlier revision of this repo also forced the H.264 format
> selector. That patch was dropped — format selection is deliberately left to upstream, so videos
> that upstream resolves to AV1/VP9 will again be delivered by Telegram as documents. Only the
> streaming patch remains.

## What the patch changes

`patches/0001-streamable-sendvideo.patch` — `internal/bot/bot.go` only:

```go
tele.Video{
    File:      tele.FromReader(fp),
    Streaming: true,                       // json: supports_streaming
    Width:     width,                      // parsed from the yt-dlp "resolution" field
    Height:    height,
    Duration:  int(dl.Duration.Seconds()), // already parsed from the info.json
}
```

Upstream sends `tele.Video{File: tele.FromReader(fp)}` — no `supports_streaming`, no dimensions, no
duration. Telegram clients answer that with a **download button** instead of streaming the video,
and render a blank bubble until the file is fetched. Per the Bot API,
`supports_streaming` is *"Pass True if the uploaded video is suitable for streaming"* and defaults to
absent; per the TDLib maintainer it asserts that audio and video streams are **interleaved**, which
is what lets a client fetch the file by byte ranges.

## How the upstream stays updated (and the patch cannot be clobbered)

This repository stores **no upstream source**. Every build:

1. checks out `tarampampam/video-dl-bot@master` fresh,
2. applies `patches/*.patch` with `git apply --3way`,
3. builds the image from that source with upstream's own `Dockerfile`.

So upstream code, yt-dlp, ffmpeg, node and the Go toolchain all come straight from upstream — only
the lines the patch touches are ours. If upstream rewrites those lines, the patch stops applying and
the **build fails before publishing anything** (no silent regression, no rebase babysitting). A daily
cron re-runs the build, and an unchanged upstream yields the same image.

## CI gates

* **patch applies** — a moved line upstream fails the build loudly.
* **patched source verified** — the applied source must contain `Streaming: true` and the
  `parseResolution` helper.
* **bot runs** — `docker run --rm <image> --version`.
* **image contract** — the binary must carry upstream's standard format selector and must *not*
  carry any H.264 override, so a re-introduced codec patch cannot slip in unnoticed.
* **resolution report** — informational: prints what the standard selector picks for a real URL
  (needs YouTube from the runner; reports `::warning::` rather than failing when unavailable).

Tags: `latest`, `sha-<our commit>`, `upstream-<upstream commit>` — the last one makes it obvious
which upstream revision an image was built from, and gives you a rollback target.

## Using it on MikroTik RouterOS (`/app`)

```yaml
name: tg-ytdl
category: utilities
'default-credentials': none
descr: 'Telegram bot: send a link, get a streaming video'
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

Keep one change per patch and keep the diff small — that is what keeps patches applying cleanly
across upstream releases. If the codec override is ever wanted again, it is a second patch on
`internal/yt-dlp/yt-dlp.go` (see the git history of this repository for the exact selector).

## License

MIT, same as upstream.