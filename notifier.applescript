-- Tiny notifier app for eye-break.
-- Compiled by install.sh into EyeBreak.app so notifications get their own
-- bundle identity (and therefore their own entry in System Settings >
-- Notifications) instead of borrowing Script Editor's.
--
-- eye-break 的迷你通知器。install.sh 会把它编成 EyeBreak.app，
-- 让通知拥有自己的 bundle id，从而在「系统设置 > 通知」里独立成一条，
-- 而不是借用 Script Editor 的身份（后者在新版 macOS 上经常被静默丢弃）。

on run
	set msgFile to (POSIX path of (path to home folder)) & ".eye-break/msg.txt"
	try
		set raw to do shell script "/bin/cat " & quoted form of msgFile
	on error
		return
	end try
	set AppleScript's text item delimiters to "|"
	set parts to text items of raw
	set AppleScript's text item delimiters to ""
	if (count of parts) < 3 then return
	display notification (item 2 of parts) with title (item 1 of parts) sound name (item 3 of parts)
	delay 2
end run
