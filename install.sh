#!/bin/bash
# eye-break installer · 安装脚本
#   ./install.sh            install / upgrade  · 安装或升级
#   ./install.sh --lang zh  force Chinese      · 强制中文
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/.eye-break"
APP="$BASE/EyeBreak.app"
LABEL="com.eyebreak.agent"
BUNDLE_ID="com.eyebreak.notifier"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

LANG_ARG=""
[ "${1:-}" = "--lang" ] && LANG_ARG="${2:-}"

echo "==> Installing eye-break into $BASE"
mkdir -p "$BASE" "$HOME/Library/LaunchAgents"
install -m 755 "$SRC/eye-break.sh" "$BASE/eye-break.sh"
install -m 644 "$SRC/notifier.applescript" "$BASE/notifier.applescript"
install -m 755 "$SRC/backfill.sh" "$BASE/backfill.sh"
[ -f "$BASE/config" ] || install -m 644 "$SRC/config.example" "$BASE/config"
[ -n "$LANG_ARG" ] && {
  /usr/bin/sed -i '' "s/^LANG_PREF=.*/LANG_PREF=$LANG_ARG/" "$BASE/config"
  echo "    language pinned to '$LANG_ARG' in $BASE/config"
}

# The full-screen cover is a tiny Swift program. It needs the Command Line
# Tools; without them eye-break still works, just notification-only.
# 全屏遮罩是个很小的 Swift 程序，要 Command Line Tools。没装也不影响使用，
# 只是回落成纯通知。
if command -v swiftc >/dev/null 2>&1; then
  echo "==> Building the full-screen cover · 编译全屏遮罩"
  if swiftc -O -o "$BASE/eye-break-overlay" "$SRC/overlay.swift" 2>"$BASE/overlay-build.log"; then
    chmod 755 "$BASE/eye-break-overlay"
    rm -f "$BASE/overlay-build.log"
  else
    echo "    build failed — see $BASE/overlay-build.log; falling back to notifications only"
    rm -f "$BASE/eye-break-overlay"
  fi
else
  echo "==> No swiftc, skipping the full-screen cover · 没有 swiftc，跳过全屏遮罩"
  echo "    install it with: xcode-select --install"
fi

# Resolve display name for the notifier app · 通知器 App 的显示名
LP="$LANG_ARG"
[ -z "$LP" ] && LP=$(/usr/bin/awk -F= '/^LANG_PREF=/{print $2}' "$BASE/config" 2>/dev/null || echo auto)
[ "$LP" = "auto" ] && { case "$(defaults read -g AppleLocale 2>/dev/null)" in zh*) LP=zh ;; *) LP=en ;; esac; }
[ "$LP" = "zh" ] && APP_NAME="护眼提醒" || APP_NAME="Eye Break"

echo "==> Building notifier app ($BUNDLE_ID, \"$APP_NAME\")"
rm -rf "$APP"
/usr/bin/osacompile -o "$APP" "$SRC/notifier.applescript" 2>/dev/null
PB=/usr/libexec/PlistBuddy
IP="$APP/Contents/Info.plist"
$PB -c "Add :CFBundleIdentifier string $BUNDLE_ID"   "$IP" >/dev/null
$PB -c "Set :CFBundleName $APP_NAME"                 "$IP" >/dev/null 2>&1 || \
$PB -c "Add :CFBundleName string $APP_NAME"          "$IP" >/dev/null
$PB -c "Add :CFBundleDisplayName string $APP_NAME"   "$IP" >/dev/null
$PB -c "Add :LSUIElement bool true"                  "$IP" >/dev/null   # no Dock icon
# Editing Info.plist invalidates the applet's signature — re-sign ad-hoc,
# otherwise the app refuses to launch. 改完 Info.plist 必须重签，否则起不来。
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "==> Installing LaunchAgent ($LABEL, ticks every 60s)"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$BASE/eye-break.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$BASE/launchd.out</string>
    <key>StandardErrorPath</key>
    <string>$BASE/launchd.err</string>
</dict>
</plist>
PLIST_EOF
/usr/bin/plutil -lint "$PLIST" >/dev/null

# Retire the pre-1.0 label if it is still around · 清掉早期版本的 agent
launchctl bootout "gui/$(id -u)/com.claude.eye-break" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.claude.eye-break.plist"

# Upgrading from a version without daily stats? Recover what the old log can
# prove, so --stats is not blank on day one. This MUST happen before the agent
# is bootstrapped: RunAtLoad fires a tick immediately, which would create
# today's file as measured data and make the backfill skip today.
# 从没有日统计的版本升级时，把旧日志能证明的部分捞回来。必须赶在启动 agent
# 之前做：RunAtLoad 会立刻跑一个 tick，把今天的文件建成「已实测」，
# 回填就会跳过今天。
if [ -f "$BASE/eye-break.log" ] && [ -z "$(ls "$BASE/daily" 2>/dev/null)" ]; then
  echo "==> Backfilling daily stats from the existing log · 从旧日志回填统计"
  "$BASE/backfill.sh" | /usr/bin/sed 's/^/    /'
fi

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
rm -f "$BASE/state"

echo
echo "✅ Installed. · 安装完成"
echo "   status  : $BASE/eye-break.sh --status"
echo "   stats   : $BASE/eye-break.sh --stats [days]"
echo "   test    : $BASE/eye-break.sh --now"
[ -x "$BASE/eye-break-overlay" ] && echo "   cover   : on — set OVERLAY=0 in the config to turn it off"
echo "   config  : $BASE/config"
echo "   log     : $BASE/eye-break.log"
echo "   uninstall: $SRC/uninstall.sh"
echo
echo "First reminder lands after 20 minutes of actual screen time."
echo "第一次提醒会在你累计用眼 20 分钟后出现。"
