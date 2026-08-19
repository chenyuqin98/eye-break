#!/bin/bash
#
# backfill — rebuild daily stats from an older eye-break.log
# 从旧日志反推每日统计
#
# Versions before daily accounting only logged events, never durations.
# This recovers what the log can prove and leaves the rest clearly marked
# as an estimate. It never overwrites a day that was actually measured.
# 加日统计之前的版本只记事件不记时长。这里只还原日志能证明的部分，
# 其余明确标成估算；已实测的日子绝不覆盖。

set -uo pipefail

BASE="$HOME/.eye-break"
LOG="${EYE_BREAK_LOG:-$BASE/eye-break.log}"
DAILYDIR="${EYE_BREAK_DAILY:-$BASE/daily}"
INTERVAL=1200
[ -f "$BASE/config" ] && . "$BASE/config"

[ -f "$LOG" ] || { echo "no log at $LOG"; exit 1; }
mkdir -p "$DAILYDIR"

# Exact from the log:  reminder count, locked seconds, reset counts.
# Estimated:           screen time = reminders x INTERVAL, a lower bound,
#                      because every reset threw away an unknown partial block.
# 日志能确证的：提醒次数、锁屏秒数、各类中断次数。
# 只能估算的：用眼时间 = 提醒次数 x INTERVAL，这是下限 ——
#             每次清零都丢掉了一段无从得知的零头。
awk -v dir="$DAILYDIR" -v interval="$INTERVAL" '
  { day = $1 }
  /notify: start/                 { brk[day]++ }
  /reset: idle/                   { ri[day]++ }
  /reset: screen locked/          { rl[day]++ }
  /reset: tick gap/               { rs[day]++ }
  /reset: 离开/                    { rs[day]++ }
  # Gaps of 4h+ span a night or a whole morning away — they cannot be
  # attributed to one day, and counting them reports absurd "away" totals.
  # 4 小时以上的间隔要么跨夜要么整个上午不在，没法归到某一天，
  # 硬算进去会得出荒唐的离屏时长。
  /resume: unlocked after/        {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+s$/) {
        sub(/s$/, "", $i)
        if ($i + 0 < 14400) lk[day] += $i
        break
      }
  }
  { seen[day] = 1 }
  END {
    for (d in seen) {
      printf "%s\t%d\t%d\t%d\t%d\t%d\n", d, brk[d]+0, lk[d]+0, ri[d]+0, rl[d]+0, rs[d]+0
    }
  }
' "$LOG" | sort | while IFS=$'\t' read -r day brk lk ri rl rs; do
  f="$DAILYDIR/$day"
  if [ -f "$f" ]; then
    est=0; . "$f" 2>/dev/null; d_est=${d_est:-0}
    if [ "$d_est" != "1" ]; then
      echo "skip $day — already measured · 已有实测数据，跳过"
      continue
    fi
  fi
  cat > "$f" <<EOF
d_screen=$((brk * INTERVAL))
d_paused=0
d_locked=$lk
d_breaks=$brk
d_taken=0
d_rst_idle=$ri
d_rst_lock=$rl
d_rst_sleep=$rs
d_first=0
d_last=0
d_est=1
d_est_breaks=$brk
EOF
  echo "wrote $day — ${brk} reminders, $((brk * INTERVAL / 60))m screen (lower bound), $((lk / 60))m locked"
done

echo
echo "Done. 看结果:  ~/.eye-break/eye-break.sh --stats"
