import Cocoa
import GhosttyKit

/// kghostty: a quick terminal made of regular terminal windows.
///
/// Enabled with `quick-terminal-normal-window`. Instead of the borderless
/// sliding `QuickTerminalController` panel, `toggle_quick_terminal` shows
/// and hides a dedicated `TerminalController` window. Because it is a
/// regular terminal window it has a titlebar, can be moved and resized,
/// and keeps its frame while hidden.
///
/// Quick windows are marked with a dedicated `tabbingIdentifier`, which
/// also keeps AppKit from automatically merging regular windows into them.
/// With `quick-terminal-tabs`, new tabs created from a quick window become
/// quick windows as well and are hidden and shown together.
///
/// AppKit dissolves a tab group when its windows are ordered out, so when
/// hiding we remember the tab order and the selected tab and rebuild the
/// group when showing again.
///
/// AppKit's own window animations are disabled. Instead the window fades
/// in and out over `quick-terminal-animation-duration` seconds, and is
/// shown and hidden instantly when that is 0.
final class QuickWindowManager {
    static let tabbingIdentifier = "com.kawaemon.kghostty.quickWindow"

    private static var instance: QuickWindowManager?

    static func shared(_ ghostty: Ghostty.App) -> QuickWindowManager {
        if let instance { return instance }
        let manager = QuickWindowManager(ghostty)
        instance = manager
        return manager
    }

    /// Returns true if the given window belongs to the quick window.
    static func isQuickWindow(_ window: NSWindow?) -> Bool {
        window?.tabbingIdentifier == tabbingIdentifier
    }

    /// Called before a new tab is created from `parent`. Returns true (after
    /// telling the user why) if the new tab must not be created.
    static func shouldBlockNewTab(from parent: NSWindow?, _ ghostty: Ghostty.App) -> Bool {
        guard let parent, isQuickWindow(parent) else { return false }
        if ghostty.config.quickTerminalTabs { return false }

        let alert = NSAlert()
        alert.messageText = "Cannot Create New Tab"
        alert.informativeText = "Tabs aren't enabled for the Quick Terminal. Set `quick-terminal-tabs = true` to enable them."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: parent)
        return true
    }

    /// Called when a new tab window is created from `parent`. If the parent
    /// is a quick window, the new tab becomes part of the quick window too.
    static func adoptNewTab(_ window: NSWindow, from parent: NSWindow, _ ghostty: Ghostty.App) {
        guard isQuickWindow(parent) else { return }
        shared(ghostty).adopt(window)
    }

    private let ghostty: Ghostty.App

    /// All windows that belong to the quick window, in creation order.
    private var tracked: [Weak<NSWindow>] = []

    /// The tab order and selected tab captured when we last hid.
    private var hiddenOrder: [Weak<NSWindow>] = []
    private weak var hiddenSelected: NSWindow?

    /// The app that was frontmost before we were shown, restored on hide.
    private var previousApp: NSRunningApplication?

    /// The frame of the last quick window, reused when a new one is created
    /// after all of them were closed.
    private var lastFrame: NSRect?

    /// Incremented for every show/hide so a stale fade-out completion does
    /// not order out windows that were shown again in the meantime.
    private var animationGeneration = 0

    private init(_ ghostty: Ghostty.App) {
        self.ghostty = ghostty

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Live quick windows.
    private var windows: [NSWindow] {
        tracked.compactMap(\.value)
    }

    /// True if any quick window is currently on screen.
    private var isShown: Bool {
        !NSApp.isHidden && windows.contains(where: \.isVisible)
    }

    // MARK: Toggle

    func toggle() {
        if isShown && NSApp.isActive && Self.isQuickWindow(NSApp.keyWindow) {
            hide(restorePreviousApp: true)
        } else {
            show()
        }
    }

    private func show() {
        // Remember who was frontmost so we can give focus back on hide.
        if !NSApp.isActive,
           let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        let live = windows
        if live.isEmpty {
            createWindow()
            return
        }

        live.forEach(applyWindowBehavior)

        // Already on screen (e.g. behind another app or fading out): just
        // bring it forward.
        if let visible = live.first(where: \.isVisible) {
            let target = visible.tabGroup?.selectedWindow ?? visible
            animationGeneration += 1
            target.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            fadeIn(target, from: target.alphaValue)
            return
        }

        // Rebuild the tab group in the order it had when we hid it. Windows
        // that are not part of the saved order go at the end.
        let saved = hiddenOrder.compactMap(\.value).filter { live.contains($0) }
        let order = saved + live.filter { !saved.contains($0) }
        guard let first = order.first else { return }
        let selected = hiddenSelected.flatMap { order.contains($0) ? $0 : nil } ?? first

        animationGeneration += 1
        if animationDuration > 0 { selected.alphaValue = 0 }
        first.orderFront(nil)
        var last = first
        for window in order.dropFirst() {
            last.addTabbedWindow(window, ordered: .above)
            last = window
        }

        if order.count > 1 {
            first.tabGroup?.selectedWindow = selected
        }
        selected.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fadeIn(selected, from: 0)

        hiddenOrder = []
        hiddenSelected = nil
    }

    private func hide(restorePreviousApp: Bool) {
        let live = windows
        guard !live.isEmpty else { return }

        // Ordering out a native fullscreen window misbehaves; do nothing,
        // matching upstream's toggle_visibility.
        if live.contains(where: { $0.styleMask.contains(.fullScreen) }) { return }

        let visible = live.first(where: \.isVisible)
        let groupWindows = visible?.tabGroup?.windows.filter { live.contains($0) } ?? []
        let order = groupWindows + live.filter { !groupWindows.contains($0) }
        let selected = visible?.tabGroup?.selectedWindow ?? visible ?? order.first

        hiddenOrder = order.map { Weak($0) }
        hiddenSelected = selected
        if let selected { lastFrame = selected.frame }

        animationGeneration += 1
        let generation = animationGeneration
        let finish = { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            order.forEach {
                $0.orderOut(nil)
                $0.alphaValue = 1
            }
        }

        let duration = animationDuration
        if duration > 0, let selected, selected.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = .init(name: .easeIn)
                selected.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            finish()
        }

        if restorePreviousApp, let previousApp, !previousApp.isTerminated {
            _ = previousApp.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: Windows

    private func createWindow() {
        var config = Ghostty.SurfaceConfiguration()
        config.environmentVariables["GHOSTTY_QUICK_TERMINAL"] = "1"

        let controller = TerminalController(ghostty, withBaseConfig: config)
        guard let window = controller.window else { return }
        adopt(window)

        let frame = restorableLastFrame ?? initialFrame(for: window)
        animationGeneration += 1
        if animationDuration > 0 { window.alphaValue = 0 }
        controller.showWindowSafely(nil)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fadeIn(window, from: 0)
    }

    // MARK: Animation

    private var animationDuration: Double {
        max(0, ghostty.config.quickTerminalAnimationDuration)
    }

    /// Fade a window in from `alpha` to fully opaque.
    private func fadeIn(_ window: NSWindow, from alpha: CGFloat) {
        let duration = animationDuration
        guard duration > 0, alpha < 1 else {
            window.alphaValue = 1
            return
        }

        window.alphaValue = alpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration * Double(1 - alpha)
            context.timingFunction = .init(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Marks a window as part of the quick window.
    func adopt(_ window: NSWindow) {
        window.tabbingIdentifier = Self.tabbingIdentifier
        // Quick windows are recreated on demand, never restored on launch.
        window.isRestorable = false
        // We animate (or not) ourselves; see quick-terminal-animation-duration.
        window.animationBehavior = .none
        applyWindowBehavior(window)
        if !tracked.contains(where: { $0.value === window }) {
            tracked.append(Weak(window))
        }
    }

    private func applyWindowBehavior(_ window: NSWindow) {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        switch ghostty.config.quickTerminalSpaceBehavior {
        case .move: behavior.insert(.canJoinAllSpaces)
        case .remain: behavior.insert(.moveToActiveSpace)
        }
        window.collectionBehavior = behavior
    }

    /// The last frame if it is still on a connected screen.
    private var restorableLastFrame: NSRect? {
        guard let lastFrame else { return nil }
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(lastFrame) }) else { return nil }
        return lastFrame
    }

    /// The first frame of a quick window, derived from `quick-terminal-position`,
    /// `quick-terminal-size` and `quick-terminal-screen`.
    private func initialFrame(for window: NSWindow) -> NSRect {
        let config = ghostty.config
        guard let screen = config.quickTerminalScreen.screen ?? NSScreen.main else { return window.frame }
        let position = config.quickTerminalPosition
        let visible = screen.visibleFrame
        let size = config.quickTerminalSize.calculate(
            position: position,
            screenDimensions: visible.size)
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let centerX = round(visible.minX + (visible.width - width) / 2)
        let centerY = round(visible.minY + (visible.height - height) / 2)

        let origin: NSPoint
        switch position {
        case .top: origin = .init(x: centerX, y: visible.maxY - height)
        case .bottom: origin = .init(x: centerX, y: visible.minY)
        case .left: origin = .init(x: visible.minX, y: centerY)
        case .right: origin = .init(x: visible.maxX - width, y: centerY)
        case .center: origin = .init(x: centerX, y: centerY)
        }
        return .init(origin: origin, size: .init(width: width, height: height))
    }

    // MARK: Notifications

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              tracked.contains(where: { $0.value === window }) else { return }
        if window.frame.width > 0 && window.frame.height > 0 {
            lastFrame = window.frame
        }
        tracked.removeAll { $0.value == nil || $0.value === window }
        hiddenOrder.removeAll { $0.value == nil || $0.value === window }
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        guard ghostty.config.quickTerminalAutoHide, isShown else { return }
        // Another app took focus; don't steal it back.
        previousApp = nil
        hide(restorePreviousApp: false)
    }
}
