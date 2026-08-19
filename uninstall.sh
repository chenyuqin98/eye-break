#!/bin/bash
# eye-break uninstaller · 卸载脚本
#   ./uninstall.sh          remove agent + app, keep config, log and stats
#                           删掉后台任务和通知器，保留配置、日志和统计
#   ./uninstall.sh --purge  remove everything including ~/.eye-break
#                           连 ~/.eye-break 一起删干净（统计历史也没了）
set -uo pipefail

BASE="$HOME/.eye-break"
LABEL="com.eyebreak.agent"

for L in "$LABEL" com.claude.eye-break; do
  launchctl bootout "gui/$(id -u)/$L" 2>/dev/null && echo "==> unloaded $L"
  rm -f "$HOME/Library/LaunchAgents/$L.plist"
done
rm -rf "$BASE/EyeBreak.app"
echo "==> removed LaunchAgent and notifier app"

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$BASE"
  echo "==> purged $BASE (config, log, state, daily stats)"
else
  echo "    kept $BASE (config, log, state, daily stats) — use --purge to remove"
fi
echo "✅ Uninstalled. · 已卸载"
