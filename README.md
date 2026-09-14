# video-dl-bot-h264

Thin, self-updating wrapper around [`tarampampam/video-dl-bot`](https://github.com/tarampampam/video-dl-bot)
that guarantees Telegram-playable media.

## The problem it solves

Upstream hardcodes one yt-dlp format selector:

```
bv*[ext=mp4][filesize<2G]+ba[ext=m4a][filesize<2G]/bv*[ext=mp4]+ba[ext=m4a]/best[filesize<2G]/best
```

On YouTube this resolves to **AV1** video (`av01.*`) inside an **mp4** container. Telegram cannot
decode AV1, so its Bot API falls back to sending the download as a plain **file** instead of a
playable video message.

Measured on the upstream selector:

```
mp4 | av01.0.12M.08 | mp4a.40.2 | 401+140
```

With the selector this wrapper forces:

```
mp4 | avc1.640028   | mp4a.40.2 | 137+140
```

## How the fix is applied (and why it never gets clobbered)

No upstream source lives in this repository, so there is nothing to sync, rebase or merge — and
therefore nothing that can be overwritten when upstream changes.

* `entrypoint.sh` prepends a shim to `PATH`. The bot resolves its yt-dlp binary with
  `exec.LookPath("yt-dlp")`, so our shim wins.
* The shim appends `--format <H.264/AAC first> --merge-output-format mp4` to every yt-dlp call.
  yt-dlp is an argparse CLI where the **last** `--format` wins and options may follow the URL, so
  this overrides the value hardcoded in the bot.

All other upstream changes (new bot releases, updated yt-dlp, ffmpeg, node) arrive automatically:
the base image is a floating tag and every build pulls it fresh (`--pull`). Upstream may rewrite
every line of its Go code and this image will still build.

## Auto-update chain

```
tarampampam/video-dl-bot:latest
        │  (rebased on every push + daily cron, docker build --pull)
        ▼
ghcr.io/iietp/video-dl-bot-h264:latest
        │  (/app/update on MikroTik RouterOS, or app auto-update)
        ▼
MikroTik app "tg-ytdl"
```

Image layers are content-addressed, so the daily rebuild is a no-op unless upstream actually
published something new. Every build is also tagged `sha-<commit>` for instant rollback.

## Using it

Straight docker:

```sh
docker run -d --name bot -e BOT_TOKEN='123:AA...' ghcr.io/iietp/video-dl-bot-h264:latest
```

MikroTik RouterOS app (`/app`), app store YAML entry:

```yaml
name: tg-ytdl
category: utilities
'default-credentials': none
descr: 'Telegram bot: send a link, get the video (yt-dlp, H.264/AAC mp4)'
page: 'https://github.com/IIeTp/video-dl-bot-h264'
services:
  'bot':
    dns: '8.8.8.8'
    environment:
      'BOT_TOKEN': '<token>'
    hostname: 'tg-ytdl'
    image: 'ghcr.io/iietp/video-dl-bot-h264:latest'
```

## Knobs

| Variable | Default | Purpose |
|---|---|---|
| `YTDLP_FORMAT_OVERRIDE` | H.264/AAC-first mp4 selector | the yt-dlp format selector that is forced |
| `YTDLP_EXTRA_ARGS` | `--merge-output-format mp4` | extra args appended after the selector |
| `YTDLP_BIN` | `/bin/yt-dlp` | real binary the shim must call |
| `BOT_BINARY` | `/bin/video-dl-bot` | what the entrypoint execs (used by CI smoke test) |

All upstream variables (`BOT_TOKEN`, `COOKIES_FILE`, `MAX_CONCURRENT_DOWNLOADS`, `JS_RUNTIMES`,
`LOG_LEVEL`, `LOG_FORMAT`) keep working unchanged.

## CI gates

Every build runs three checks before the image is considered good:

1. `docker run ... image --version` — entrypoint → shim → bot chain still works.
2. `command -v yt-dlp` inside the image must print the shim path — proves the `LookPath` contract.
3. `ci/check-h264.sh` — resolves a real URL and asserts `ext=mp4` + `vcodec=avc1*`
   (informational: it needs YouTube reachable from the runner).

If upstream ever changes the two runtime invariants this wrapper relies on (`LookPath` lookup and
last-`--format` precedence), gate 2 or 3 fails and the problem is visible instead of silent.

## License

MIT for the wrapper. The wrapped upstream project is MIT as well — see
[tarampampam/video-dl-bot](https://github.com/tarampampam/video-dl-bot).
