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
| Screen locked > 20 s | timer **resets** — that already was the eye break |
| Screen locked < 20 s | timer **pauses**, progress kept |
| No keyboard/mouse > 2 min (unlocked) | timer **resets** |
| Lid closed, machine slept | timer **resets** — no ambush reminder on wake |
| Quota reached outside active hours | skipped, logged, next round starts clean |

Lock state is read from `IOConsoleLocked` in the IORegistry, **not** inferred from
idle time. This matters: while the screen is locked, `HIDIdleTime` keeps getting
reset by the lock screen itself and sits near zero the entire time you are away,
so any idle-based heuristic silently believes you never left.

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
~/.eye-break/eye-break.sh --status     # Screen time this round: 7m 1s / 20m — 12m 59s to go
                                       # At the screen since 09:12 today — 3h 40m total, 9 reminders
~/.eye-break/eye-break.sh --stats      # daily table, last 7 days
~/.eye-break/eye-break.sh --stats 30   # ...last 30 days
~/.eye-break/eye-break.sh --now        # fire a reminder immediately
~/.eye-break/eye-break.sh --help
```

## Daily stats

```
  Eye Break stats · last 7 days
  ──────────────────────────────────────────────────────────────────
  Date         Screen     Away     Fired  Took  Rate    Cut    Load
  2026-08-14   5h20m      1h04m    16     11    68%     7      ████████··
  2026-08-15   6h40m      52m      20     13    65%     9      ██████████
  2026-08-16   1h20m      18m      4      4     100%    2      ██········
  ──────────────────────────────────────────────────────────────────
   3 days      13h20m     2h14m    40     28    70%
  daily avg    4h26m      44m      13 reminders
```

| Column | Meaning |
|---|---|
| **Screen** | time that counted toward the 20-minute quota — the headline number |
| **Away** | locked + long idle, counted only inside your active hours |
| **Fired** | reminders delivered |
| **Took** | ...of which you went hands-off for the whole break |
| **Rate** | Took / Fired |
| **Cut** | how many times the timer was reset (locked, idle, or slept) |

**"Took" is a proxy, not proof.** No API can see where your eyes are pointing, so
the only thing measurable is whether you stopped touching the keyboard and mouse
for the full break. Sitting still and staring at the same screen scores as a pass;
typing straight through the nudge scores as a fail, and that part is unambiguous.

One `key=value` file per day under `~/.eye-break/daily/`, rewritten every tick, so
a crash costs at most one minute. Upgrading from a version without stats? `install.sh`
runs `backfill.sh`, which recovers what the old log can prove — reminder counts and
lock durations are exact, screen time becomes a lower bound (reminders × `INTERVAL`),
and those days are marked `*` and excluded from the compliance rate.

## Configuration

Edit `~/.eye-break/config` — changes take effect on the next tick, no reload needed.

| Key | Default | Meaning |
|---|---|---|
| `LANG_PREF` | `auto` | `auto` / `zh` / `en`. `auto` follows your macOS locale |
| `ACTIVE_START` / `ACTIVE_END` | `9` / `23` | only remind between these hours |
| `INTERVAL` | `1200` | seconds of screen time per round |
| `BREAK_RESET` | `120` | no keyboard/mouse this long → reset the timer |
| `SLEEP_GAP` | `300` | tick gap this big → machine slept (floored at 180) |
| `LOCK_RESET` | `20` | screen locked this long → reset the timer |
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
                              +   and IOConsoleLocked from ioreg
                              |
                              +-- tick gap >= SLEEP_GAP  slept: reset, exit
                              +-- locked .............. add to locked time;
                              |                         >= 20s -> reset, exit
                              +-- idle >= 120s ........ reset state, exit
                              +-- idle >= 90s ......... pause, exit
                              +-- otherwise ........... accumulate elapsed
                              |
                              +-- accumulated >= 1200s  -> notify, sleep 20s,
                                                           re-read idle to score
                                                           the break, notify,
                                                           reset state
```

State is three integers in `~/.eye-break/state`: accumulated screen seconds, the
timestamp of the last tick, and how long the screen has been locked. A tick gap
larger than `SLEEP_GAP` is how sleep/wake is detected — no extra plumbing needed.
Per-day totals live separately in `~/.eye-break/daily/YYYY-MM-DD` and survive the
state resets that every reminder and every lock trigger.

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
- `bash` 3.2 is not multibyte-aware when parsing variable names: `out="$out█"`
  swallows the first UTF-8 byte into the name and dies under `set -u`. Braces are
  mandatory — `out="${out}█"`.
- `printf` pads to a width in **bytes**, not display columns, so a CJK header and
  an em dash both wreck table alignment. Every data cell in `--stats` is ASCII and
  the Chinese headers are hand-spaced.
- A Mac left locked but awake keeps ticking all night, so away-time is only
  counted inside `ACTIVE_START`–`ACTIVE_END`. Otherwise a four-hour workday
  reports thirteen hours "away".
- Testing hooks: `EYE_BREAK_FAKE_LOCKED`, `EYE_BREAK_FAKE_IDLE`, `EYE_BREAK_LOG`,
  `EYE_BREAK_STATE`, `EYE_BREAK_DAILY` let you
  drive the state machine without touching real data or waiting 20 minutes.

## Uninstall

```sh
./uninstall.sh            # remove the agent and the app
./uninstall.sh --purge    # also delete ~/.eye-break, stats history included
```

## License

MIT
