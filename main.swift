// Appshot — freeze the screen, mark it up with a laser pointer, and hand the
// annotated screenshot + instructions to Claude or Codex.
//
// Hotkey: ⌃⌥L (or the ◎ menu bar item)
//   drag        → laser circle / freehand mark
//   shift-drag  → arrow
//   click       → point marker
//   ⌘Z undo · Esc cancel · Return send

import AppKit
import Carbon
import ApplicationServices

// MARK: - Annotation model

enum MarkKind { case free, arrow, point }

struct Mark {
    var kind: MarkKind
    var points: [CGPoint]          // view coords (points, top-left origin)

    var bounds: CGRect {
        guard let f = points.first else { return .zero }
        var r = CGRect(origin: f, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }
}

let laserRed = NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.18, alpha: 1)
let laserCore = NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.88, alpha: 1)

/// Draws marks into the current NSGraphicsContext (which must be flipped).
/// `glow` scales shadow blur, since shadows ignore the CTM.
func drawMarks(_ marks: [Mark], glow: CGFloat) {
    for (i, m) in marks.enumerated() {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = laserRed.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 10 * glow
        shadow.shadowOffset = .zero
        shadow.set()

        switch m.kind {
        case .free:
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: m.points[0])
            for p in m.points.dropFirst() { path.line(to: p) }
            path.lineWidth = 5
            laserRed.setStroke(); path.stroke()
            NSShadow().set()
            path.lineWidth = 1.5
            laserCore.setStroke(); path.stroke()

        case .arrow:
            let a = m.points.first!, b = m.points.last!
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: a); path.line(to: b)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head: CGFloat = 22, spread: CGFloat = .pi / 7
            path.move(to: b)
            path.line(to: CGPoint(x: b.x - head * cos(angle - spread), y: b.y - head * sin(angle - spread)))
            path.move(to: b)
            path.line(to: CGPoint(x: b.x - head * cos(angle + spread), y: b.y - head * sin(angle + spread)))
            path.lineWidth = 5
            laserRed.setStroke(); path.stroke()
            NSShadow().set()
            path.lineWidth = 1.5
            laserCore.setStroke(); path.stroke()

        case .point:
            let c = m.points[0]
            let ring = NSBezierPath(ovalIn: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36))
            ring.lineWidth = 4
            laserRed.setStroke(); ring.stroke()
            let dot = NSBezierPath(ovalIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            laserRed.setFill(); dot.fill()
            NSShadow().set()
            laserCore.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Number badge so the prompt can say "#2"
        let anchor: CGPoint = m.kind == .point
            ? CGPoint(x: m.points[0].x + 16, y: m.points[0].y - 30)
            : CGPoint(x: m.bounds.minX - 12, y: m.bounds.minY - 12)
        let badge = CGRect(x: max(2, anchor.x), y: max(2, anchor.y), width: 24, height: 24)
        laserRed.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let label = "\(i + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
        ]
        let sz = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: badge.midX - sz.width / 2, y: badge.midY - sz.height / 2), withAttributes: attrs)
    }
}

// MARK: - Drawing view

final class DrawView: NSView {
    let image: NSImage
    var marks: [Mark] = []
    private var current: Mark?
    private var laser: CGPoint?
    var onChange: (() -> Void)?

    init(frame: CGRect, image: NSImage) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        // Subtle dim so the laser pops
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
        drawMarks(marks + (current.map { [$0] } ?? []), glow: 1)

        if let p = laser {
            NSGraphicsContext.saveGraphicsState()
            let s = NSShadow()
            s.shadowColor = laserRed; s.shadowBlurRadius = 14; s.shadowOffset = .zero; s.set()
            laserRed.setFill()
            NSBezierPath(ovalIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).fill()
            NSGraphicsContext.restoreGraphicsState()
            laserCore.setFill()
            NSBezierPath(ovalIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)).fill()
        }
    }

    private func loc(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with e: NSEvent) { laser = loc(e); needsDisplay = true }
    override func mouseExited(with e: NSEvent) { laser = nil; needsDisplay = true }

    override func mouseDown(with e: NSEvent) {
        let p = loc(e)
        current = Mark(kind: e.modifierFlags.contains(.shift) ? .arrow : .free, points: [p])
        laser = p
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let p = loc(e)
        laser = p
        guard var m = current else { return }
        if m.kind == .arrow { m.points = [m.points[0], p] } else { m.points.append(p) }
        current = m
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        guard var m = current else { return }
        current = nil
        let b = m.bounds
        if b.width < 6 && b.height < 6 { m = Mark(kind: .point, points: [m.points[0]]) }
        marks.append(m)
        needsDisplay = true
        onChange?()
    }

    func undo() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        needsDisplay = true
        onChange?()
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum Target: Int { case claude = 0, codex = 1, lastApp = 2 }

final class Overlay: NSObject {
    let window: OverlayWindow
    let drawView: DrawView
    let field = NSTextField()
    let targetControl = NSSegmentedControl(labels: ["Claude", "Codex", "Last app"], trackingMode: .selectOne, target: nil, action: nil)
    let countLabel = NSTextField(labelWithString: "")
    let cgImage: CGImage
    var keyMonitor: Any?
    var onFinish: ((Overlay, Bool) -> Void)?

    init(screen: NSScreen, image: NSImage, cgImage: CGImage, lastAppName: String?) {
        self.cgImage = cgImage
        window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let size = screen.frame.size
        drawView = DrawView(frame: CGRect(origin: .zero, size: size), image: image)
        super.init()

        let root = NSView(frame: CGRect(origin: .zero, size: size))
        root.addSubview(drawView)
        root.addSubview(makeBar(width: size.width, lastAppName: lastAppName))
        window.contentView = root
        drawView.onChange = { [weak self] in self?.updateCount() }
        updateCount()
    }

    private func makeBar(width: CGFloat, lastAppName: String?) -> NSView {
        let w: CGFloat = min(880, width - 40), h: CGFloat = 92
        let bar = NSVisualEffectView(frame: CGRect(x: (width - w) / 2, y: 36, width: w, height: h))
        bar.material = .hudWindow
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 14
        bar.layer?.masksToBounds = true

        targetControl.frame = CGRect(x: 14, y: 48, width: 250, height: 28)
        targetControl.selectedSegment = UserDefaults.standard.object(forKey: "target") as? Int ?? 0
        if let n = lastAppName { targetControl.setLabel(n, forSegment: 2) }
        targetControl.setToolTip("Paste into the app that was in front when you pressed the hotkey (e.g. your terminal running claude / codex)", forSegment: 2)
        bar.addSubview(targetControl)

        field.frame = CGRect(x: 276, y: 47, width: w - 276 - 104, height: 30)
        field.placeholderString = "Tell the agent what to do with the marked spots…"
        field.font = .systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(send)
        bar.addSubview(field)

        let sendBtn = NSButton(title: "Send ↩", target: self, action: #selector(send))
        sendBtn.bezelStyle = .rounded
        sendBtn.keyEquivalent = "\r"
        sendBtn.frame = CGRect(x: w - 96, y: 46, width: 84, height: 32)
        bar.addSubview(sendBtn)

        let hint = NSTextField(labelWithString: "drag = circle   ·   shift-drag = arrow   ·   click = point   ·   ⌘Z undo   ·   esc cancel")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = CGRect(x: 16, y: 14, width: w - 160, height: 18)
        bar.addSubview(hint)

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = laserRed
        countLabel.alignment = .right
        countLabel.frame = CGRect(x: w - 150, y: 14, width: 134, height: 18)
        bar.addSubview(countLabel)
        return bar
    }

    private func updateCount() {
        let n = drawView.marks.count
        countLabel.stringValue = n == 0 ? "no marks yet" : "\(n) mark\(n == 1 ? "" : "s")"
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == UInt16(kVK_Escape) { self.finish(send: false); return nil }
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "z" { self.drawView.undo(); return nil }
            return e
        }
    }

    @objc func send() { finish(send: true) }

    private func finish(send: Bool) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        UserDefaults.standard.set(targetControl.selectedSegment, forKey: "target")
        window.orderOut(nil)
        onFinish?(self, send)
    }

    var target: Target { Target(rawValue: targetControl.selectedSegment) ?? .claude }
    var instruction: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Pixel-per-point scale of the captured image.
    var scale: CGFloat { CGFloat(cgImage.width) / drawView.bounds.width }

    /// Screenshot with marks burned in, at full pixel resolution.
    func renderPNG() -> Data? {
        let pw = cgImage.width, ph = cgImage.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = ctx.cgContext
        cg.draw(cgImage, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        cg.translateBy(x: 0, y: CGFloat(ph))
        cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        drawMarks(drawView.marks, glow: scale)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Human/agent-readable list of marks in image pixel coordinates.
    func markDescriptions() -> [String] {
        let s = scale
        func px(_ v: CGFloat) -> Int { Int((v * s).rounded()) }
        return drawView.marks.enumerated().map { i, m in
            switch m.kind {
            case .point:
                let p = m.points[0]
                return "#\(i + 1) point at (\(px(p.x)), \(px(p.y)))"
            case .arrow:
                let a = m.points.first!, b = m.points.last!
                return "#\(i + 1) arrow from (\(px(a.x)), \(px(a.y))) pointing at (\(px(b.x)), \(px(b.y)))"
            case .free:
                let r = m.bounds
                return "#\(i + 1) circled region x=\(px(r.minX)) y=\(px(r.minY)) w=\(px(r.width)) h=\(px(r.height))"
            }
        }
    }
}

// MARK: - Delivery

let terminalBundleIDs: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
    "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty", "com.microsoft.VSCode",
    "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.exafunction.windsurf",
]

struct AgentApp {
    let name: String
    let bundleIDs: [String]
    let cli: String
}

let claudeApp = AgentApp(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], cli: "claude")
let codexApp = AgentApp(name: "Codex", bundleIDs: ["com.openai.codex", "com.openai.chat.codex"], cli: "codex")

func findCLI(_ name: String) -> String? {
    let home = NSHomeDirectory()
    var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    dirs += ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
             "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
    return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func runInTerminal(_ command: String) {
    let esc = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let script = "tell application \"Terminal\"\nactivate\ndo script \"\(esc)\"\nend tell"
    var err: NSDictionary?
    NSAppleScript(source: script)?.executeAndReturnError(&err)
    if let err { alert("Couldn't open Terminal", "\(err)") }
}

func alert(_ title: String, _ text: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.runModal()
}

func pressCmdV() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func setPasteboard(image: NSImage? = nil, text: String? = nil) {
    let pb = NSPasteboard.general
    pb.clearContents()
    if let image { pb.writeObjects([image]) }
    if let text { pb.setString(text, forType: .string) }
}

func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

// MARK: - App

// MARK: - Permissions

enum Permission {
    case screenRecording, accessibility

    var name: String { self == .screenRecording ? "Screen Recording" : "Accessibility" }
    var granted: Bool { self == .screenRecording ? CGPreflightScreenCaptureAccess() : AXIsProcessTrusted() }

    /// Asks macOS to list Appshot in the pane (and prompt, the first time).
    func request() {
        if self == .screenRecording { CGRequestScreenCaptureAccess() }
        else { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    }

    func openSettings() {
        let pane = self == .screenRecording ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

/// macOS remembers a permission for one exact build of an app. If Appshot was
/// rebuilt or reinstalled, its old switch can look on while this copy is off.
func permissionAlert(_ p: Permission, why: String, fallback: String? = nil) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = "Appshot needs \(p.name) permission"
    a.informativeText = """
        \(why)\(fallback.map { "\n\n" + $0 } ?? "")

        In System Settings, turn on Appshot under \(p.name).

        Already on? It's left over from an older copy of Appshot. Select it, click the − button to remove it, then quit and reopen Appshot and turn it on again.
        """
    a.addButton(withTitle: "Open System Settings")
    a.addButton(withTitle: "Not Now")
    if a.runModal() == .alertFirstButtonReturn {
        p.request()
        p.openSettings()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    var statusItem: NSStatusItem!
    var overlay: Overlay?
    var previousApp: NSRunningApplication?
    var hotKeyRef: EventHotKeyRef?
    let cliItem = NSMenuItem(title: "Start a new CLI session instead of pasting", action: #selector(toggleCLI), keyEquivalent: "")
    let screenItem = NSMenuItem(title: "", action: #selector(fixScreenRecording), keyEquivalent: "")
    let axItem = NSMenuItem(title: "", action: #selector(fixAccessibility), keyEquivalent: "")

    var useCLI: Bool {
        get { UserDefaults.standard.bool(forKey: "useCLI") }
        set { UserDefaults.standard.set(newValue, forKey: "useCLI") }
    }

    let shotsDir: URL = {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Appshot")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "scope", accessibilityDescription: "Appshot") {
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "◎"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture & Annotate  (⌃⌥L)", action: #selector(capture), keyEquivalent: ""))
        menu.addItem(.separator())
        cliItem.state = useCLI ? .on : .off
        menu.addItem(cliItem)
        menu.addItem(NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(screenItem)
        menu.addItem(axItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Appshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        statusItem.menu = menu

        registerHotKey()
        if !Permission.screenRecording.granted { Permission.screenRecording.request() }
        if CommandLine.arguments.contains("--capture") { after(0.3) { self.capture() } }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.capture() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4150_5348), id: 1) // 'APSH'
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc func toggleCLI() { useCLI.toggle(); cliItem.state = useCLI ? .on : .off }
    @objc func openFolder() { NSWorkspace.shared.open(shotsDir) }

    // Live permission status, refreshed every time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        for (item, p) in [(screenItem, Permission.screenRecording), (axItem, Permission.accessibility)] {
            item.title = p.granted ? "\(p.name): on" : "\(p.name): off. Click to fix…"
            item.image = NSImage(systemSymbolName: p.granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                 accessibilityDescription: nil)
        }
    }

    @objc func fixScreenRecording() { fix(.screenRecording) }
    @objc func fixAccessibility() { fix(.accessibility) }
    private func fix(_ p: Permission) {
        if p.granted { p.openSettings() } else { p.request(); p.openSettings() }
    }

    @objc func capture() {
        guard overlay == nil else { return }
        // Without permission, screencapture silently returns just the wallpaper.
        guard Permission.screenRecording.granted else {
            return permissionAlert(.screenRecording, why: "It needs this to take the screenshot you draw on.")
        }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? previousApp : front

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let mainH = NSScreen.screens.first?.frame.height else { return }

        // screencapture -R wants global top-left-origin coordinates.
        let f = screen.frame
        let rect = "\(Int(f.minX)),\(Int(mainH - f.maxY)),\(Int(f.width)),\(Int(f.height))"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("appshot-raw-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R", rect, tmp.path]
        do { try p.run(); p.waitUntilExit() } catch {}
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard let img = NSImage(contentsOf: tmp),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            alert("Screen capture failed",
                  "Give Appshot Screen Recording permission in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it.")
            return
        }

        let o = Overlay(screen: screen, image: img, cgImage: cg, lastAppName: previousApp?.localizedName)
        o.onFinish = { [weak self] o, send in
            self?.overlay = nil
            if send { self?.deliver(o) }
        }
        overlay = o
        o.show()
    }

    // MARK: Delivery

    func deliver(_ o: Overlay) {
        guard let png = o.renderPNG() else { return alert("Couldn't render screenshot", "") }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = shotsDir.appendingPathComponent("appshot-\(stamp).png")
        do { try png.write(to: file) } catch { return alert("Couldn't save screenshot", error.localizedDescription) }

        let marks = o.markDescriptions()
        var prompt = o.instruction.isEmpty ? "Look at the marked spots in this screenshot." : o.instruction
        prompt += "\n\n[Appshot] Annotated screenshot: \(file.path) (\(o.cgImage.width)×\(o.cgImage.height) px)."
        if !marks.isEmpty {
            prompt += " Red laser marks (pixel coords, top-left origin):\n" + marks.map { "  " + $0 }.joined(separator: "\n")
        }

        let image = NSImage(data: png)
        let target = o.target

        if useCLI && target != .lastApp {
            let agent = target == .claude ? claudeApp : codexApp
            guard let bin = findCLI(agent.cli) else {
                setPasteboard(text: prompt)
                return alert("\(agent.cli) CLI not found",
                             "Install it or turn off “Start a new CLI session”. The prompt is on your clipboard.")
            }
            let cmd = target == .codex
                ? "\(shellQuote(bin)) -i \(shellQuote(file.path)) \(shellQuote(prompt))"
                : "\(shellQuote(bin)) \(shellQuote(prompt))"
            return runInTerminal("cd ~ && " + cmd)
        }

        let app: NSRunningApplication?
        switch target {
        case .lastApp: app = previousApp
        case .claude: app = runningApp(claudeApp)
        case .codex: app = runningApp(codexApp)
        }

        if let app {
            paste(into: app, image: image, text: prompt)
        } else if target != .lastApp, let url = appURL(target == .claude ? claudeApp : codexApp) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, _ in
                DispatchQueue.main.async {
                    guard let app else { return }
                    after(2.5) { self.paste(into: app, image: image, text: prompt) }
                }
            }
        } else {
            let agent = target == .claude ? claudeApp : codexApp
            if target != .lastApp, let bin = findCLI(agent.cli) {
                let cmd = target == .codex
                    ? "\(shellQuote(bin)) -i \(shellQuote(file.path)) \(shellQuote(prompt))"
                    : "\(shellQuote(bin)) \(shellQuote(prompt))"
                runInTerminal("cd ~ && " + cmd)
            } else {
                setPasteboard(image: image)
                alert("Couldn't find \(target == .lastApp ? "the previous app" : agent.name)",
                      "The annotated screenshot is on your clipboard and saved to \(file.path).")
            }
        }
    }

    func runningApp(_ a: AgentApp) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first { a.bundleIDs.contains($0.bundleIdentifier ?? "") }
            ?? apps.first { $0.localizedName == a.name && $0.activationPolicy == .regular }
    }

    func appURL(_ a: AgentApp) -> URL? {
        for id in a.bundleIDs { if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u } }
        let u = URL(fileURLWithPath: "/Applications/\(a.name).app")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Activates the app and pastes. Terminals get text only (the prompt carries the
    /// file path, which claude/codex CLIs read); GUI apps get the image, then the text.
    /// Nothing is submitted — you review and hit Return yourself.
    func paste(into app: NSRunningApplication, image: NSImage?, text: String) {
        guard Permission.accessibility.granted else {
            setPasteboard(image: image, text: text)
            permissionAlert(.accessibility, why: "It needs this to paste into \(app.localizedName ?? "the app") for you.",
                            fallback: "For now, your screenshot is on the clipboard. Press ⌘V to paste it.")
            app.activate()
            return
        }
        let isTerminal = terminalBundleIDs.contains(app.bundleIdentifier ?? "")
        app.activate()
        after(0.4) {
            if isTerminal || image == nil {
                setPasteboard(text: text); pressCmdV()
            } else {
                setPasteboard(image: image); pressCmdV()
                after(0.6) { setPasteboard(text: text); pressCmdV() }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
