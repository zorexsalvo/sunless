import AppKit
import SwiftUI
import Carbon

final class FloatingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class AssistantController: NSObject, NSWindowDelegate {
    static let shared = AssistantController()

    var window: NSWindow!
    var state = AssistantState()
    private var dragStartOrigin: NSPoint?
    private var hotkey = GlobalHotkey()

    private let windowSize = NSSize(width: 260, height: 400)

    func start() {
        buildWindow()
        setupMenu()
        setupEscapeMonitor()
        setupMouseMonitor()
        registerHotkey()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.environment["PET_MOCK"] != nil {
            state.startMock()
            state.showComposer = true
            state.focusComposer = true
        }
    }

    private func buildWindow() {
        let rootView = AssistantRoot(
            onMove: { [weak self] delta in self?.moveWindow(by: delta) },
            onMoveEnd: { [weak self] in self?.snapToEdges() }
        )
        .environmentObject(state)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        let rect = NSRect(origin: .zero, size: windowSize)
        window = FloatingWindow(
            contentRect: rect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 20
        window.contentView?.layer?.masksToBounds = true
        window.delegate = self

        if let screen = window.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(
                x: frame.maxX - windowSize.width - 16,
                y: frame.minY + 16
            )
            window.setFrameOrigin(origin)
        }
    }

    private func setupMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: ""
        )
        alwaysOnTopItem.state = state.isAlwaysOnTop ? .on : .off
        appMenu.addItem(alwaysOnTopItem)

        appMenu.addItem(
            withTitle: "Toggle Composer",
            action: #selector(toggleComposerMenu),
            keyEquivalent: "0"
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = menu
    }

    private func setupEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.state.showComposer == true {
                self?.state.showComposer = false
                return nil
            }
            return event
        }
    }

    private func setupMouseMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, event.window == self.window else { return event }
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
            return event
        }
    }

    private func registerHotkey() {
        let ok = hotkey.register(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleComposer()
            }
        }
        if !ok {
            print("Warning: could not register global Option+Space hotkey")
        }
    }

    func moveWindow(by delta: CGSize) {
        guard let window = window else { return }
        if dragStartOrigin == nil { dragStartOrigin = window.frame.origin }
        let newOrigin = NSPoint(
            x: dragStartOrigin!.x + delta.width,
            y: dragStartOrigin!.y - delta.height
        )
        window.setFrameOrigin(newOrigin)
    }

    func snapToEdges() {
        dragStartOrigin = nil
        guard let window = window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let margin: CGFloat = 12
        let threshold: CGFloat = 40
        let frame = window.frame
        let screenFrame = screen.visibleFrame
        var origin = frame.origin

        if frame.minX - screenFrame.minX < threshold {
            origin.x = screenFrame.minX + margin
        } else if screenFrame.maxX - frame.maxX < threshold {
            origin.x = screenFrame.maxX - frame.width - margin
        }
        if frame.minY - screenFrame.minY < threshold {
            origin.y = screenFrame.minY + margin
        } else if screenFrame.maxY - frame.maxY < threshold {
            origin.y = screenFrame.maxY - frame.height - margin
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = .init(name: .easeInEaseOut)
            window.animator().setFrameOrigin(origin)
        }
    }

    @objc private func toggleAlwaysOnTop() {
        state.isAlwaysOnTop.toggle()
        window?.level = state.isAlwaysOnTop ? .floating : .normal
        setupMenu()
    }

    @objc private func toggleComposerMenu() {
        toggleComposer()
    }

    func toggleComposer() {
        state.showComposer.toggle()
        if state.showComposer {
            state.focusComposer = true
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AssistantController.shared.start()
    }
}

func loadSunlessRC() {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".sunlessrc")
        .path
    guard FileManager.default.fileExists(atPath: path),
          let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        return
    }
    for line in contents.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        var value = parts[1].trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        setenv(key, value, 1)
    }
}

@main
struct PetApp {
    static func main() {
        loadSunlessRC()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
