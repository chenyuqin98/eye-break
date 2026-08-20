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
DAILYDIR="${EYE_BREAK_DAILY:-$BASE/daily}"
OVERLAY_BIN="$BASE/eye-break-overlay"

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
OVERLAY=1             # 1 = cover the whole screen during the break
                      # 1 = 休息期间用全屏遮罩盖住屏幕，0 = 只发通知
OVERLAY_OPACITY=0.94  # 0.3 (barely dimmed) .. 1.0 (solid) · 遮罩不透明度
OVERLAY_SKIP_WHEN_PRESENTING=1
                      # don't hijack the screen while something is holding the
                      # display awake — screen shares, presentations, video
                      # 有东西正撑着屏幕不休眠时不抢屏（投屏、演示、看视频）
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

# ═══════════════════════════════════════════════════════════════════════
#  Daily accounting · 每日计量
#  One key=value file per day under ~/.eye-break/daily/. Rewritten every
#  tick, so a crash costs at most one minute of data.
#  每天一个 key=value 文件，每个 tick 重写一次，最多丢一分钟数据。
# ═══════════════════════════════════════════════════════════════════════
d_screen=0    # seconds counted as screen time  · 计入用眼的秒数
d_paused=0    # at the desk but not touching it · 人在但没碰键鼠
d_locked=0    # screen locked                   · 锁屏时长
d_breaks=0    # reminders fired                 · 发出的提醒次数
d_taken=0     # ...of which you went hands-off  · 其中真的停手了的
d_rst_idle=0  # timer cleared by idle           · 因空闲清零
d_rst_lock=0  # timer cleared by lock           · 因锁屏清零
d_rst_sleep=0 # timer cleared by machine sleep  · 因机器睡眠清零
d_first=0     # first active tick of the day    · 当天第一个活跃 tick
d_last=0      # last active tick of the day     · 当天最后一个活跃 tick
d_est=0       # 1 = the day contains reconstructed data · 该日含反推数据
d_est_breaks=0 # reminders that came from reconstruction, so they have no
               # "taken" measurement and must not drag the rate down
               # 反推来的提醒次数：它们没有「照做」实测值，不能拉低遵守率
DAYFILE=""

day_load() {
  DAYFILE="$DAILYDIR/$(date +%F)"
  [ -f "$DAYFILE" ] && . "$DAYFILE"
  return 0
}

# Away-from-screen time is only interesting inside the active window.
# A machine left locked and awake overnight otherwise reports 13 hours
# "away" on a day you sat at the desk for four.
# 离屏时长只在活跃时段才有意义。机器通宵锁屏但没睡的话，launchd 照样
# 每分钟 tick，一天能报出 13 小时「离屏」，而你其实只坐了四小时。
in_active_hours() {
  local h; h=$(date +%-H)
  [ "$h" -ge "$ACTIVE_START" ] && [ "$h" -lt "$ACTIVE_END" ]
}

day_save() {
  [ -n "$DAYFILE" ] || return 0
  /bin/mkdir -p "$DAILYDIR" 2>/dev/null
  cat > "$DAYFILE" <<EOF
d_screen=$d_screen
d_paused=$d_paused
d_locked=$d_locked
d_breaks=$d_breaks
d_taken=$d_taken
d_rst_idle=$d_rst_idle
d_rst_lock=$d_rst_lock
d_rst_sleep=$d_rst_sleep
d_first=$d_first
d_last=$d_last
d_est=$d_est
d_est_breaks=$d_est_breaks
EOF
}

notify() { # notify <title> <body> <sound>
  if [ -d "$APP" ]; then
    printf '%s|%s|%s' "$1" "$2" "$3" > "$MSG"
    /usr/bin/open -n -a "$APP"
  else
    # Fallback if the notifier app is missing · 兜底
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" >/dev/null 2>&1
  fi
}

# Is something holding the display awake? Screen sharing, Keynote in play
# mode and video playback all assert PreventUserIdleDisplaySleep. Covering
# the screen mid-presentation is the one failure mode worth avoiding.
# 有没有东西正撑着屏幕不休眠？投屏、Keynote 演示、播视频都会持有
# PreventUserIdleDisplaySleep。演示到一半被全屏遮罩盖住是最难堪的翻车。
presenting() {
  [ "$OVERLAY_SKIP_WHEN_PRESENTING" = "1" ] || return 1
  /usr/bin/pmset -g assertions 2>/dev/null \
    | /usr/bin/awk '/^ *PreventUserIdleDisplaySleep/ {print $2; exit}' \
    | /usr/bin/grep -q '^[1-9]'
}

fire() { # one full round: look away -> wait -> all clear
  local entry title body idle_end rc scored hands_off
  entry="${START_MSGS[$((RANDOM % ${#START_MSGS[@]}))]}"
  title="${entry%%|*}"; body="${entry#*|}"
  notify "$title" "$body" "$START_SOUND"
  log "notify: start  <$title>"

  d_breaks=$((d_breaks + 1))
  scored=0

  # The cover blocks for the whole break, so it replaces the sleep. Its exit
  # code is a far better compliance signal than idle time: 0 means the break
  # ran to the end, 2 means you pressed esc to get your screen back.
  # 遮罩本身会阻塞整段休息，所以它取代了 sleep。它的退出码比空闲时间准得多：
  # 0 = 整段走完，2 = 你按了 esc 把屏幕要回去。
  if [ "$OVERLAY" = "1" ] && [ -x "$OVERLAY_BIN" ] && ! presenting; then
    "$OVERLAY_BIN" "$title" "$body" "$BREAK_SECONDS" "$OVERLAY_OPACITY"
    rc=$?
    case "$rc" in
      0) d_taken=$((d_taken + 1)); scored=1; log "break: overlay ran to the end — taken" ;;
      2) scored=1; log "break: esc — skipped" ;;
      *) log "break: overlay failed (rc=$rc) — falling back to a plain wait"
         sleep "$BREAK_SECONDS" ;;
    esac
  else
    [ "$OVERLAY" = "1" ] && [ -x "$OVERLAY_BIN" ] && \
      log "break: something is holding the display awake — no overlay this round"
    sleep "$BREAK_SECONDS"
  fi

  # No overlay verdict? Fall back to the idle proxy: hands-off for the whole
  # break. It cannot tell where your eyes went, but typing straight through
  # the nudge is unambiguous.
  # 没有遮罩判定时回落到空闲代理指标：整段没碰键鼠。它不知道你眼睛看哪儿，
  # 但「提醒响了还在打字」是确凿的没照做。
  if [ "$scored" = "0" ]; then
    idle_end=${EYE_BREAK_FAKE_IDLE:-$(/usr/sbin/ioreg -c IOHIDSystem 2>/dev/null \
               | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')}
    idle_end=${idle_end:-0}
    # Floor the threshold: BREAK_SECONDS below 5 would make it negative, and
    # every break would score as taken no matter what you did.
    # 阈值要有下限：BREAK_SECONDS 小于 5 时它会变成负数，那样不管你干什么
    # 每次休息都算「照做」。
    hands_off=$((BREAK_SECONDS - 5)); [ "$hands_off" -lt 1 ] && hands_off=1
    if [ "$idle_end" -ge "$hands_off" ]; then
      d_taken=$((d_taken + 1))
      log "break: hands off ${idle_end}s — counted as taken"
    else
      log "break: kept typing (idle ${idle_end}s) — not counted"
    fi
  fi

  entry="${END_MSGS[$((RANDOM % ${#END_MSGS[@]}))]}"
  notify "${entry%%|*}" "${entry#*|}" "$END_SOUND"
  log "notify: end    <${entry%%|*}>"
}

# ═══════════════════════════════════════════════════════════════════════
#  Report · 统计报表
# ═══════════════════════════════════════════════════════════════════════
fmt_dur() { # seconds -> "3h12m" / "47m"
  if [ "$1" -ge 3600 ]; then printf '%dh%02dm' $(($1/3600)) $((($1%3600)/60))
  else printf '%dm' $(($1/60)); fi
}

bar10() { # bar10 <value> <max> -> ten-cell bar
  # Braces are mandatory: bash 3.2 is not multibyte-aware, so it swallows the
  # following UTF-8 byte into the variable name and dies under `set -u`.
  # 花括号不能省：bash 3.2 不认多字节，会把后面的 UTF-8 字节吃进变量名，
  # 配上 set -u 直接报 unbound variable。
  local n=0 i=0 out=""
  [ "$2" -gt 0 ] && n=$(( ($1 * 10 + $2/2) / $2 ))
  [ "$n" -gt 10 ] && n=10
  while [ "$i" -lt "$n" ]; do out="${out}█"; i=$((i+1)); done
  while [ "$i" -lt 10 ]; do out="${out}·"; i=$((i+1)); done
  printf '%s' "$out"
}

stats() {
  local days="${1:-7}" f max=0 t_screen=0 t_break=0 t_taken=0 t_rst=0 t_off=0
  local n_days=0 any_est=0 rate off rst measured=0 t_measured=0
  case "$days" in ''|*[!0-9]*) days=7 ;; esac
  if [ ! -d "$DAILYDIR" ] || [ -z "$(ls "$DAILYDIR" 2>/dev/null)" ]; then
    if [ "$LANG_PREF" = "zh" ]; then echo "还没有任何统计数据。装好之后跑满一天再回来看。"
    else echo "No data yet. Come back after a day of ticks."; fi
    return 0
  fi
  local files
  files=$(ls "$DAILYDIR" 2>/dev/null | sort | tail -n "$days")

  for f in $files; do                      # first pass: scale the bars
    d_screen=0; . "$DAILYDIR/$f" 2>/dev/null
    [ "$d_screen" -gt "$max" ] && max=$d_screen
  done

  # printf pads by BYTES, not display columns, so every data cell below is
  # kept ASCII and these CJK headers are hand-spaced to match.
  # printf 按字节而非显示宽度补空格，所以下面每个数据格都只用 ASCII，
  # 这两行中文表头则是手工对齐的。
  if [ "$LANG_PREF" = "zh" ]; then
    printf '\n  20-20-20 护眼统计 · 最近 %d 天\n' "$days"
    echo   '  ──────────────────────────────────────────────────────────────────'
    echo   '  日期         用眼时间   离屏     提醒  照做  遵守率  中断   用眼强度'
  else
    printf '\n  Eye Break stats · last %d days\n' "$days"
    echo   '  ──────────────────────────────────────────────────────────────────'
    echo   '  Date         Screen     Away     Fired  Took  Rate    Cut    Load'
  fi

  for f in $files; do
    d_screen=0; d_paused=0; d_locked=0; d_breaks=0; d_taken=0
    d_rst_idle=0; d_rst_lock=0; d_rst_sleep=0; d_est=0; d_est_breaks=0
    . "$DAILYDIR/$f" 2>/dev/null
    off=$((d_paused + d_locked))
    rst=$((d_rst_idle + d_rst_lock + d_rst_sleep))
    # Only reminders we actually watched can be scored · 只有实测的提醒能算遵守率
    measured=$((d_breaks - d_est_breaks))
    if [ "$measured" -gt 0 ]; then rate=$(( d_taken * 100 / measured )); else rate=-1; fi
    n_days=$((n_days + 1))
    t_screen=$((t_screen + d_screen)); t_off=$((t_off + off))
    t_break=$((t_break + d_breaks));   t_taken=$((t_taken + d_taken)); t_rst=$((t_rst + rst))
    [ "$d_est" = "1" ] && any_est=1

    printf '  %-11s  %-9s  %-7s  %-5s  %-4s  %-6s  %-5s  %s%s\n' \
      "$f" "$(fmt_dur $d_screen)" "$(fmt_dur $off)" "$d_breaks" \
      "$([ "$measured" -gt 0 ] && echo "$d_taken" || echo "-")" \
      "$([ "$rate" -lt 0 ] && echo "-" || echo "${rate}%")" \
      "$rst" "$(bar10 "$d_screen" "$max")" \
      "$([ "$d_est" = "1" ] && echo " *" || echo "")"
    t_measured=$((t_measured + measured))
  done

  echo '  ──────────────────────────────────────────────────────────────────'
  local t_rate t_took
  if [ "$t_measured" -gt 0 ]; then
    t_rate="$(( t_taken * 100 / t_measured ))%"; t_took="$t_taken"
  else
    t_rate="-"; t_took="-"       # every day was reconstructed · 全是反推数据
  fi
  if [ "$LANG_PREF" = "zh" ]; then
    printf '  合计 %2d 天   %-9s  %-7s  %-5s  %-4s  %s\n' \
      "$n_days" "$(fmt_dur $t_screen)" "$(fmt_dur $t_off)" "$t_break" "$t_took" "$t_rate"
    printf '  日均         %-9s  %-7s  %s 次提醒\n' \
      "$(fmt_dur $((t_screen / (n_days>0?n_days:1))))" \
      "$(fmt_dur $((t_off / (n_days>0?n_days:1))))" \
      "$((t_break / (n_days>0?n_days:1)))"
    echo
    echo '  用眼 = 计入 20 分钟配额的时间；离屏 = 锁屏 + 长时间没碰键鼠'
    echo '  照做 = 全屏遮罩整段走完没按 esc；没开遮罩时回落到「整段没碰键鼠」的代理指标'
    [ "$any_est" = "1" ] && echo '  * 该日部分数据由旧日志反推：用眼时间是下限，反推的提醒不计入遵守率'
  else
    printf '  %2d days      %-9s  %-7s  %-5s  %-4s  %s\n' \
      "$n_days" "$(fmt_dur $t_screen)" "$(fmt_dur $t_off)" "$t_break" "$t_took" "$t_rate"
    printf '  daily avg    %-9s  %-7s  %s reminders\n' \
      "$(fmt_dur $((t_screen / (n_days>0?n_days:1))))" \
      "$(fmt_dur $((t_off / (n_days>0?n_days:1))))" \
      "$((t_break / (n_days>0?n_days:1)))"
    echo
    echo '  Screen = time counted toward the 20-minute quota; Away = locked + long idle'
    echo   '  Took = the cover ran to the end without esc; without it, hands-off for the whole break'
    [ "$any_est" = "1" ] && echo '  * partly reconstructed from the old log: screen time is a lower bound,'
    [ "$any_est" = "1" ] && echo '    and reconstructed reminders are excluded from the rate'
  fi
  echo
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
  eye-break.sh --stats [N]  daily screen time and break compliance, last N days
                          最近 N 天的每日用眼时间与遵守情况（默认 7）
  eye-break.sh --help     this text · 本帮助

Config · 配置:  ~/.eye-break/config     Log · 日志:  ~/.eye-break/eye-break.log
USAGE
}

case "${1:-}" in
  --help|-h)  usage; exit 0 ;;
  --now)      fire;  exit 0 ;;
  --stats)    stats "${2:-7}"; exit 0 ;;
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
  day_load
  if [ "$LANG_PREF" = "zh" ]; then
    printf '已累计用眼 %d 分 %d 秒 / %d 分，还差 %d 分 %d 秒\n' \
      $((accum/60)) $((accum%60)) $((INTERVAL/60)) $((left/60)) $((left%60))
    [ "$away" -gt 0 ] && printf '当前锁屏中，已锁 %d 分 %d 秒\n' $((away/60)) $((away%60))
    if [ "$d_est" = "1" ]; then
      printf '今天累计用眼约 %d 小时 %d 分，收到 %d 次提醒（含旧日志反推的估算）\n' \
        $((d_screen/3600)) $((d_screen%3600/60)) "$d_breaks"
    elif [ "$d_first" -gt 0 ]; then
      printf '今天 %s 起坐到屏幕前，累计用眼 %d 小时 %d 分，收到 %d 次提醒\n' \
        "$(date -r "$d_first" '+%H:%M')" $((d_screen/3600)) $((d_screen%3600/60)) "$d_breaks"
    fi
  else
    printf 'Screen time this round: %dm %ds / %dm  —  %dm %ds to go\n' \
      $((accum/60)) $((accum%60)) $((INTERVAL/60)) $((left/60)) $((left%60))
    [ "$away" -gt 0 ] && printf 'Screen is locked, %dm %ds so far\n' $((away/60)) $((away%60))
    if [ "$d_est" = "1" ]; then
      printf 'Roughly %dh %dm at the screen today, %d reminders (partly reconstructed)\n' \
        $((d_screen/3600)) $((d_screen%3600/60)) "$d_breaks"
    elif [ "$d_first" -gt 0 ]; then
      printf 'At the screen since %s today — %dh %dm total, %d reminders\n' \
        "$(date -r "$d_first" '+%H:%M')" $((d_screen/3600)) $((d_screen%3600/60)) "$d_breaks"
    fi
  fi
  exit 0
fi

# ─── One tick · 每分钟一次 ──────────────────────────────────────────────
# Load today's counters and guarantee they are written back on every exit
# path below. 载入当天计数，并保证下面每条退出路径都会写回。
day_load
trap day_save EXIT
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
  if [ "$accum" -gt 0 ]; then
    log "reset: tick gap ${elapsed}s (machine slept) — timer cleared"
    d_rst_sleep=$((d_rst_sleep + 1))
  fi
  printf '0 %s 0\n' "$now" > "$STATE"
  exit 0
fi

if [ "$locked" = "1" ]; then
  away=$((away + elapsed))
  in_active_hours && d_locked=$((d_locked + elapsed))
  if [ "$away" -ge "$LOCK_RESET" ] && [ "$accum" -gt 0 ]; then
    log "reset: screen locked ${away}s — timer cleared"
    d_rst_lock=$((d_rst_lock + 1))
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
  in_active_hours && d_paused=$((d_paused + elapsed))
  if [ "$accum" -gt 0 ]; then
    log "reset: idle ${idle}s — timer cleared"
    d_rst_idle=$((d_rst_idle + 1))
  fi
  printf '0 %s 0\n' "$now" > "$STATE"
  exit 0
fi

# A short pause still counts as screen time (you are probably reading).
# 短暂发呆仍算在看屏幕；超过 IDLE_PAUSE 就暂停累加，但不清零。
if [ "$idle" -lt "$IDLE_PAUSE" ]; then
  accum=$((accum + elapsed))
  d_screen=$((d_screen + elapsed))
  [ "$d_first" -eq 0 ] && d_first=$now
  d_last=$now
else
  in_active_hours && d_paused=$((d_paused + elapsed))
fi

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
