# eye-break

**English** · [中文](README.zh-CN.md)

A 20-20-20 reminder for macOS that counts **actual screen time**, not wall-clock time.

> The 20-20-20 rule: every 20 minutes, look at something 20 feet (~6 m) away for 20 seconds.
> It relaxes the ciliary muscle, which is what gets tired from sustained near focus.

No Homebrew, no Electron, no menu-bar app. Two shell scripts, a 40 KB AppleScript
notifier, and a launchd job. Everything it touches lives in `~/.eye-break`.

## Why not just a 20-minute timer?

Because a fixed timer doesn't know whether you were actually looking at the screen.
Lock your laptop at minute 5, come back at minute 19, and a naive timer nags you
after one minute of screen time — then keeps drifting out of phase all day.

`eye-break` ticks once a minute and only accumulates time you were really there:

| Situation | Behaviour |
|---|---|
| Actively working (idle < 90 s) | timer accumulates |
| Brief pause (90 s – 5 min) | timer **pauses** — you're probably still reading |
| Screen locked / away > 5 min | timer **resets** — that already was an eye break |
| Lid closed, machine slept | timer **resets** — no ambush reminder on wake |
| Quota reached outside active hours | skipped, logged, next round starts clean |

## Install

```sh
git clone https://github.com/chenyuqin98/eye-break.git
cd eye-break
./install.sh              # or: ./install.sh --lang zh
```

The first notification may ask for permission. The notifier is a real app bundle
with its own identity, so it shows up in **System Settings → Notifications** as
"Eye Break" (or 护眼提醒) and you can set it to *Alerts* instead of *Banners* —
alerts stay on screen until dismissed, which is much harder to ignore.

## Usage

```sh
~/.eye-break/eye-break.sh --status   # Screen time this round: 7m 1s / 20m — 12m 59s to go
~/.eye-break/eye-break.sh --now      # fire a reminder immediately
~/.eye-break/eye-break.sh --help
```

## Configuration

Edit `~/.eye-break/config` — changes take effect on the next tick, no reload needed.

| Key | Default | Meaning |
|---|---|---|
| `LANG_PREF` | `auto` | `auto` / `zh` / `en`. `auto` follows your macOS locale |
| `ACTIVE_START` / `ACTIVE_END` | `9` / `23` | only remind between these hours |
| `INTERVAL` | `1200` | seconds of screen time per round |
| `BREAK_RESET` | `300` | away this long → reset the timer |
| `IDLE_PAUSE` | `90` | idle this long → pause accumulating |
| `BREAK_SECONDS` | `20` | how long to look away |
| `START_SOUND` / `END_SOUND` | `Glass` / `Ping` | any name from `/System/Library/Sounds` |

Each reminder is drawn at random from a pool of 14 opening lines and 8 closing
lines, in both languages. Add your own by appending to the arrays at the top of
`eye-break.sh` — format is `"title|body"`.

## How it works

```
launchd (every 60s)  ->  eye-break.sh  ->  reads HIDIdleTime from ioreg
                              |
                              +-- idle >= 300s ........ reset state, exit
                              +-- idle >= 90s ......... pause, exit
                              +-- otherwise ........... accumulate elapsed
                              |
                              +-- accumulated >= 1200s  -> notify, sleep 20s,
                                                           notify, reset state
```

State is two integers in `~/.eye-break/state`: accumulated seconds, and the
timestamp of the last tick. A tick gap larger than `BREAK_RESET` is how sleep/wake
is detected — no extra plumbing needed.

Notifications are delivered by `EyeBreak.app`, built at install time by
`osacompile`. The shell writes `title|body|sound` into `~/.eye-break/msg.txt`,
then `open -n`s the app, which reads the file and posts the notification.

## Notes

- **macOS ships bash 3.2.57** (2007, a GPLv3 casualty). No namerefs, no associative
  arrays. `bash -n` will happily accept `local -n` and then fail at runtime, so
  test against `/bin/bash` specifically, not your Homebrew bash.
- Editing an applet's `Info.plist` invalidates its code signature and it will
  silently refuse to launch. `install.sh` re-signs ad-hoc afterwards.
- Do Not Disturb / Focus will suppress the notification. That's usually what you
  want — it means no reminders mid-meeting.
- Testing hooks: `EYE_BREAK_FAKE_IDLE`, `EYE_BREAK_LOG`, `EYE_BREAK_STATE` let you
  drive the state machine without touching real data or waiting 20 minutes.

## Uninstall

```sh
./uninstall.sh            # remove the agent and the app
./uninstall.sh --purge    # also delete ~/.eye-break
```

## License

MIT
