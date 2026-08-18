#!/bin/bash
#
# eye-break — a 20-20-20 rule reminder for macOS
# 20-20-20 护眼提醒
#
# Every 20 minutes of ACTUAL screen time, look at something 20 feet (6 m) away
# for 20 seconds. Driven by launchd, ticking once a minute.
#
# https://github.com/chenyuqin98/eye-break

set -uo pipefail

BASE="$HOME/.eye-break"
CONF="$BASE/config"
APP="$BASE/EyeBreak.app"
MSG="$BASE/msg.txt"
LOG="${EYE_BREAK_LOG:-$BASE/eye-break.log}"
STATE="${EYE_BREAK_STATE:-$BASE/state}"

# ─── Defaults · 默认配置 (override in ~/.eye-break/config) ───────────────
LANG_PREF=auto        # auto | zh | en
ACTIVE_START=9        # only remind after 09:00        · 只在 09:00 之后提醒
ACTIVE_END=23         # only remind before 23:00       · 只在 23:00 之前提醒
INTERVAL=1200         # screen-time seconds per round  · 攒够多少秒用眼时间提醒一次
BREAK_RESET=120       # away this long => reset timer  · 离开这么久就清零重来
SLEEP_GAP=300         # tick gap this big => machine slept · tick 间隔这么大=机器睡过
                      # must stay well above the 60s tick interval, or every
                      # normal tick looks like a sleep · 必须远大于 60 秒 tick
                      # 间隔，否则每个正常 tick 都会被误判成睡眠
LOCK_RESET=20         # locked this long => reset timer · 锁屏这么久就清零重来
IDLE_PAUSE=90         # idle this long => stop adding  · 空闲这么久就暂停累加（不清零）
BREAK_SECONDS=20      # how long to look away          · 远眺时长
START_SOUND="Glass"
END_SOUND="Ping"
[ -f "$CONF" ] && . "$CONF"

if [ "$LANG_PREF" = "auto" ]; then
  _loc=$(defaults read -g AppleLocale 2>/dev/null || echo "${LANG:-en_US}")
  case "$_loc" in zh*) LANG_PREF=zh ;; *) LANG_PREF=en ;; esac
fi

# ═══════════════════════════════════════════════════════════════════════
#  Message pools · 文案池      format "title|body"  ·  格式 "标题|正文"
#  Add your own — just append to the array. 想加自己的词直接往数组里塞。
# ═══════════════════════════════════════════════════════════════════════
START_MSGS_EN=(
  "👀 Your eyes need a field trip|Pick something 20 feet away and stare at it for 20 seconds"
  "🌿 Ciliary muscle on strike|It's been clenched for 20 minutes straight. Let it go."
  "🔭 Switching to the wide shot|Window, hallway, anywhere far. 20 seconds."
  "🫧 Blink quota running low|You blink half as often at a screen. Catch up — and look far."
  "🐟 Your eyeballs want to swim|Let them wander 20 feet out for 20 seconds"
  "☁️ Distance o'clock|Find a cloud, a tree, a distant coworker"
  "🧘 Yoga for your eyes|20 feet out, 20 seconds, and breathe"
  "📵 The screen needs space|Take 20 seconds apart. Both of you, cool off."
  "🦉 Owl mode engaged|Roll your neck, look into the distance"
  "🍵 Visual tea break|20 seconds of distance — cheaper than coffee"
  "🎯 Focus to infinity|Give your lens a 20-second rest"
  "🌅 Your eyes need a horizon|Anything 20 feet out will do"
  "🪟 Windows are for looking through|Not for checking your reflection. Look far."
  "🥱 Don't rub your eyes|Looking into the distance works better"
)
END_MSGS_EN=(
  "✅ Back to it|Eyes recharged"
  "🎉 20 seconds, done|Your ciliary muscle thanks you. See you in 20."
  "🔙 Pull the camera back|Nicely done, carry on"
  "💚 Maintenance complete|Next round in 20 minutes"
  "🫡 Distance mission accomplished|Eyes: much better now"
  "⚡ Full HP restored|The screen missed you"
  "🐣 Eyeballs refreshed|continue ▶"
  "🌟 All good|Break's over — the eye kind, anyway"
)
START_MSGS_ZH=(
  "👀 眼睛要放风了|抬头，挑个 6 米外的倒霉蛋盯 20 秒"
  "🌿 睫状肌正在罢工|它绷了整整 20 分钟，放它松一下"
  "🔭 切到远景镜头|窗外、走廊尽头、随便哪儿，20 秒"
  "🫧 眨眼配额不足|盯屏幕时眨眼少一半，补一补，顺便看远点"
  "🐟 你的眼球想游泳|先放它去 6 米外逛 20 秒"
  "☁️ 望远时间到|找片云、找棵树、找个远处的同事"
  "🧘 眼睛做个瑜伽|20 英尺外，20 秒，顺便深呼吸"
  "📵 屏幕说想静静|你俩先分开 20 秒，冷静一下"
  "🦉 猫头鹰模式启动|转转脖子，看看远方"
  "🍵 视觉茶歇|20 秒远眺，比咖啡便宜多了"
  "🎯 对焦到无穷远|让你的镜头歇 20 秒"
  "🌅 眼睛需要一个远方|6 米外随便什么都行"
  "🪟 窗户是拿来看的|不是拿来反光当镜子的，看远点"
  "🥱 别揉眼睛|抬头看远处，比揉管用"
)
END_MSGS_ZH=(
  "✅ 归位|眼睛已充电，去干活吧"
  "🎉 20 秒达成|睫状肌感谢你，20 分钟后再会"
  "🔙 镜头拉回来|干得漂亮，继续"
  "💚 保养完毕|下一场 20 分钟后"
  "🫡 远眺任务完成|眼睛：舒服了"
  "⚡ 满血回归|回来吧，屏幕想你了"
  "🐣 眼球已刷新|continue ▶"
  "🌟 好了好了|摸鱼时间结束（划掉）护眼时间结束"
)

# macOS ships bash 3.2 (no namerefs), so copy the chosen pool by value.
# macOS 自带 bash 3.2 没有 nameref，只能整份复制。
if [ "$LANG_PREF" = "zh" ]; then
  START_MSGS=( "${START_MSGS_ZH[@]}" ); END_MSGS=( "${END_MSGS_ZH[@]}" )
else
  START_MSGS=( "${START_MSGS_EN[@]}" ); END_MSGS=( "${END_MSGS_EN[@]}" )
fi

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

notify() { # notify <title> <body> <sound>
  if [ -d "$APP" ]; then
    printf '%s|%s|%s' "$1" "$2" "$3" > "$MSG"
    /usr/bin/open -n -a "$APP"
  else
    # Fallback if the notifier app is missing · 兜底
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" >/dev/null 2>&1
  fi
}

fire() { # one full round: look away -> wait -> all clear
  local entry
  entry="${START_MSGS[$((RANDOM % ${#START_MSGS[@]}))]}"
  notify "${entry%%|*}" "${entry#*|}" "$START_SOUND"
  log "notify: start  <${entry%%|*}>"
  sleep "$BREAK_SECONDS"
  entry="${END_MSGS[$((RANDOM % ${#END_MSGS[@]}))]}"
  notify "${entry%%|*}" "${entry#*|}" "$END_SOUND"
  log "notify: end    <${entry%%|*}>"
}

usage() {
  cat <<'USAGE'
eye-break — 20-20-20 rule reminder for macOS · 20-20-20 护眼提醒

  eye-break.sh            one tick; launchd calls this every minute
                          跑一次 tick，launchd 每分钟调用
  eye-break.sh --now      fire a reminder right now (test)
                          立刻发一轮提醒（测试用）
  eye-break.sh --status   how much screen time has accumulated
                          看已累计多少用眼时间
  eye-break.sh --help     this text · 本帮助

Config · 配置:  ~/.eye-break/config     Log · 日志:  ~/.eye-break/eye-break.log
USAGE
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --now)     fire;  exit 0 ;;
esac

# ─── Read state · 读状态 ────────────────────────────────────────────
# state file: "<accumulated screen seconds> <last tick epoch> <locked seconds>"
# 状态文件三个整数：累计用眼秒数、上次 tick 时间戳、已锁屏秒数
now=$(date +%s)
accum=0; last=$now; away=0
if [ -f "$STATE" ]; then read -r accum last away < "$STATE" 2>/dev/null; fi
accum=${accum:-0}; last=${last:-$now}; away=${away:-0}

if [ "${1:-}" = "--status" ]; then
  left=$((INTERVAL - accum)); [ "$left" -lt 0 ] && left=0
  if [ "$LANG_PREF" = "zh" ]; then
    printf '已累计用眼 %d 分 %d 秒 / %d 分，还差 %d 分 %d 秒\n' \
      $((accum/60)) $((accum%60)) $((INTERVAL/60)) $((left/60)) $((left%60))
    [ "$away" -gt 0 ] && printf '当前锁屏中，已锁 %d 分 %d 秒\n' $((away/60)) $((away%60))
  else
    printf 'Screen time this round: %dm %ds / %dm  —  %dm %ds to go\n' \
      $((accum/60)) $((accum%60)) $((INTERVAL/60)) $((left/60)) $((left%60))
    [ "$away" -gt 0 ] && printf 'Screen is locked, %dm %ds so far\n' $((away/60)) $((away%60))
  fi
  exit 0
fi

# ─── One tick · 每分钟一次 ──────────────────────────────────────────────
# Is the screen locked? This is the authoritative signal — idle time is NOT,
# because the lock screen keeps generating HID events and HIDIdleTime stays
# near zero the whole time you are away.
# 锁屏状态才是权威信号。空闲时间靠不住：锁屏界面本身会产生 HID 事件，
# 你人不在的整段时间里 HIDIdleTime 都贴着 0。
locked=${EYE_BREAK_FAKE_LOCKED:-$(/usr/sbin/ioreg -n Root -d1 -k IOConsoleLocked 2>/dev/null \
        | /usr/bin/awk -F'= ' '/"IOConsoleLocked"/{gsub(/[^A-Za-z]/,"",$2); print tolower($2); exit}')}
case "$locked" in yes|1|true) locked=1 ;; *) locked=0 ;; esac

# Keyboard/mouse idle seconds — still useful for "sitting there but not typing".
# 键鼠空闲秒数 —— 仍然有用，用来判断「人在但没动」。
idle=${EYE_BREAK_FAKE_IDLE:-$(/usr/sbin/ioreg -c IOHIDSystem 2>/dev/null \
       | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')}
idle=${idle:-0}

elapsed=$((now - last))
[ "$elapsed" -lt 0 ] && elapsed=0

# A long gap between ticks means the machine slept. That was a real break.
# This threshold is deliberately NOT BREAK_RESET: they measure different things,
# and tying them together means any BREAK_RESET below the tick interval makes
# every normal tick look like a sleep, so the timer never accumulates at all.
# 这个阈值刻意不复用 BREAK_RESET：两者量的是不同的东西。绑在一起的话，
# 只要 BREAK_RESET 小于 tick 间隔，每个正常 tick 都会被当成睡眠，永远攒不起来。
[ "$SLEEP_GAP" -lt 180 ] && SLEEP_GAP=180     # floor · 下限保护
if [ "$elapsed" -ge "$SLEEP_GAP" ]; then
  [ "$accum" -gt 0 ] && log "reset: tick gap ${elapsed}s (machine slept) — timer cleared"
  printf '0 %s 0\n' "$now" > "$STATE"
  exit 0
fi

if [ "$locked" = "1" ]; then
  away=$((away + elapsed))
  if [ "$away" -ge "$LOCK_RESET" ] && [ "$accum" -gt 0 ]; then
    log "reset: screen locked ${away}s — timer cleared"
    accum=0
  fi
  printf '%s %s %s\n' "$accum" "$now" "$away" > "$STATE"
  exit 0
fi

# Just came back from the lock screen · 刚从锁屏回来
if [ "$away" -gt 0 ]; then
  log "resume: unlocked after ${away}s (screen time kept: ${accum}s)"
  away=0
fi

# Away from the keyboard without locking · 没锁屏但长时间没碰
if [ "$idle" -ge "$BREAK_RESET" ]; then
  [ "$accum" -gt 0 ] && log "reset: idle ${idle}s — timer cleared"
  printf '0 %s 0\n' "$now" > "$STATE"
  exit 0
fi

# A short pause still counts as screen time (you are probably reading).
# 短暂发呆仍算在看屏幕；超过 IDLE_PAUSE 就暂停累加，但不清零。
[ "$idle" -lt "$IDLE_PAUSE" ] && accum=$((accum + elapsed))

if [ "$accum" -ge "$INTERVAL" ]; then
  printf '0 %s 0\n' "$now" > "$STATE"
  hour=$(date +%-H)
  if [ "$hour" -lt "$ACTIVE_START" ] || [ "$hour" -ge "$ACTIVE_END" ]; then
    log "skip: quota reached but outside active hours (${hour}h)"; exit 0
  fi
  fire
else
  printf '%s %s %s\n' "$accum" "$now" "$away" > "$STATE"
fi
