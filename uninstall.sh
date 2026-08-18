#!/bin/bash
# eye-break uninstaller · 卸载脚本
#   ./uninstall.sh          remove agent + app, keep config & log
#                           删掉后台任务和通知器，保留配置与日志
#   ./uninstall.sh --purge  remove everything including ~/.eye-break
#                           连 ~/.eye-break 一起删干净
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
  echo "==> purged $BASE (config, log, state)"
else
  echo "    kept $BASE (config, log, state) — use --purge to remove"
fi
echo "✅ Uninstalled. · 已卸载"
