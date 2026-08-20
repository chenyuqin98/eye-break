//
//  overlay — the full-screen "look away" cover for eye-break
//  eye-break 的全屏远眺遮罩
//
//  overlay <title> <body> <seconds> <opacity>
//  exit 0 = the break ran to the end   · 整段走完
//  exit 2 = dismissed early with esc   · 中途按 esc 跳过
//
//  Built at install time by swiftc. If the Command Line Tools are missing,
//  install.sh skips it and eye-break falls back to notifications only.
//  安装时用 swiftc 编译。没装 Command Line Tools 就跳过，回落到纯通知。
//

import Cocoa

private func arg(_ i: Int, _ fallback: String) -> String {
    CommandLine.arguments.count > i ? CommandLine.arguments[i] : fallback
}

private let titleText = arg(1, "看向 6 米外")
private let bodyText  = arg(2, "")
private let total     = max(1.0, Double(arg(3, "20")) ?? 20)
private let opacity   = min(1.0, max(0.3, Double(arg(4, "0.94")) ?? 0.94))

private let DOTS = 20

/// A borderless window still has to be allowed to take key focus, otherwise
/// esc never reaches us. 无边框窗口必须显式允许成为 key，否则收不到 esc。
final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class Overlay: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var counters: [NSTextField] = []
    private var dotRows: [NSTextField] = []
    private var remaining = total
    private var monitor: Any?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        for screen in NSScreen.screens { windows.append(makeWindow(on: screen)) }
        NSApp.activate(ignoringOtherApps: true)

        // Swallow every keystroke while the cover is up: you should not be able
        // to keep typing into whatever is underneath it.
        // 遮罩期间吞掉所有按键 —— 不该还能对着底下的窗口继续打字。
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(2) }   // esc
            return nil
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 0.2
            self.render()
            if self.remaining <= 0 { self.finish(0) }
        }
        render()
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = ShieldWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false,
                                  screen: screen)
        // Above the menu bar and above full-screen apps.
        // 盖在菜单栏和全屏应用之上。
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root = NSView(frame: screen.frame)
        root.wantsLayer = true

        let blur = NSVisualEffectView(frame: root.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        root.addSubview(blur)

        let tint = NSView(frame: root.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(opacity).cgColor
        root.addSubview(tint)

        let title = label(titleText, size: 46, weight: .medium, alpha: 1.0)
        let counter = label("", size: 104, weight: .ultraLight, alpha: 0.95)
        counter.font = NSFont.monospacedDigitSystemFont(ofSize: 104, weight: .ultraLight)
        let dots = label("", size: 20, weight: .regular, alpha: 0.55)
        dots.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        let body = label(bodyText, size: 21, weight: .regular, alpha: 0.72)
        let hint = label("按 esc 跳过这次 · esc to skip", size: 13, weight: .regular, alpha: 0.38)

        counters.append(counter)
        dotRows.append(dots)

        let stack = NSStackView(views: [title, counter, dots, body, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.setCustomSpacing(4, after: counter)
        stack.setCustomSpacing(34, after: dots)
        stack.setCustomSpacing(46, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = NSColor.white.withAlphaComponent(alpha)
        f.alignment = .center
        f.isBezeled = false
        f.drawsBackground = false
        f.isEditable = false
        return f
    }

    private func render() {
        let left = max(0, Int(remaining.rounded(.up)))
        let filled = Int((Double(DOTS) * remaining / total).rounded(.up))
        let row = String(repeating: "●", count: max(0, min(DOTS, filled)))
                + String(repeating: "○", count: DOTS - max(0, min(DOTS, filled)))
        for c in counters { c.stringValue = "\(left)" }
        for d in dotRows { d.stringValue = row }
    }

    private func finish(_ code: Int32) {
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        for w in windows { w.orderOut(nil) }
        exit(code)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // no Dock icon · 不占 Dock
let delegate = Overlay()
app.delegate = delegate
app.run()
