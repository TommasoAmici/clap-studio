import AppKit
import ClapCore
import CVST3

/// The manufacturer's view stays in the same isolated process as its controller.
@MainActor final class NativeEditor: NSObject, NSWindowDelegate {
    private let session: VST3EditorSession
    private let request: VST3HostRequest
    private let window: NSWindow
    private let container: EditorContainer
    private var completion: CheckedContinuation<VST3HostReply, any Error>?
    private var heartbeat: Timer?
    private var closing = false

    static func run(_ request: VST3HostRequest) async throws -> VST3HostReply {
        let editor = try NativeEditor(request)
        let reply = try await withCheckedThrowingContinuation { continuation in
            editor.completion = continuation
            do { try editor.show() }
            catch { editor.session.close(); continuation.resume(throwing: error) }
        }
        withExtendedLifetime(editor) {}
        return reply
    }

    private init(_ request: VST3HostRequest) throws {
        guard let slot = request.slot else { throw VST3Error.message("Missing effect settings.") }
        session = try VST3EditorSession(slot: slot); self.request = request
        container = EditorContainer(editor: session.editor)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(slot.plugin.name) — Clap Studio"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = container
        if clap_vst3_editor_can_resize(session.editor) != 0 { window.styleMask.insert(.resizable) }
    }

    private func show() throws {
        var width: Int32 = 600, height: Int32 = 400
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard clap_vst3_editor_attach(session.editor, Unmanaged.passUnretained(container).toOpaque(), { context, width, height in
            guard let context else { return }
            MainActor.assumeIsolated {
                let editor = Unmanaged<NativeEditor>.fromOpaque(context).takeUnretainedValue()
                editor.window.setContentSize(NSSize(width: Int(width), height: Int(height)))
            }
        }, context, &width, &height) != 0 else { throw VST3Error.message("The plug-in could not open its Mac editor.") }
        window.setContentSize(NSSize(width: Int(width), height: Int(height)))
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(container)
        NSApp.activate(ignoringOtherApps: true)
        installMenus()
        if let path = request.heartbeat {
            try Data().write(to: path, options: .atomic)
            // A stuck controller also stops this main-run-loop heartbeat.
            let timer = Timer(timeInterval: 0.5, repeats: true) { _ in try? Data().write(to: path, options: .atomic) }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .modalPanel)
            heartbeat = timer
        }
        #if DEBUG
        if let delay = request.editorCloseAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, delay)) { [weak self] in self?.window.performClose(nil) }
        }
        if let output = request.editorSnapshot ?? ProcessInfo.processInfo.environment["CLAP_VST3_EDITOR_SNAPSHOT"].map({ URL(fileURLWithPath: $0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.capture(to: output) }
        }
        #endif
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
        var width = Int32(min(10000, max(1, content.width))), height = Int32(min(10000, max(1, content.height)))
        guard clap_vst3_editor_resize(session.editor, &width, &height) != 0 else { return sender.frame.size }
        return sender.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Int(width), height: Int(height))).size
    }

    func windowDidBecomeKey(_ notification: Notification) { clap_vst3_editor_focus(session.editor, 1) }
    func windowDidResignKey(_ notification: Notification) { clap_vst3_editor_focus(session.editor, 0) }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        closing = true; heartbeat?.invalidate(); heartbeat = nil
        window.delegate = nil
        do {
            let slot = try session.snapshot()
            session.close()
            completion?.resume(returning: VST3HostReply(slot: slot))
        } catch {
            session.close(); completion?.resume(throwing: error)
        }
        completion = nil
        NSRunningApplication(processIdentifier: getppid())?.activate(options: [])
    }

    private func installMenus() {
        let menu = NSMenu()
        let application = NSMenuItem(title: "Clap Studio", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Clap Studio")
        let finish = NSMenuItem(title: "Close Plug-in Editor", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        finish.target = window; appMenu.addItem(finish)
        application.submenu = appMenu; menu.addItem(application)
        let editing = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editing.submenu = editMenu; menu.addItem(editing)
        let windows = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = window; windowMenu.addItem(close)
        windows.submenu = windowMenu; menu.addItem(windows); NSApp.mainMenu = menu
    }

    #if DEBUG
    private func capture(to output: URL) {
        guard let image = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        container.cacheDisplay(in: container.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: output, options: .atomic)
    }
    #endif
}

@MainActor private final class EditorContainer: NSView {
    let editor: UnsafeMutableRawPointer
    init(editor: UnsafeMutableRawPointer) { self.editor = editor; super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400)) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { if !sendKey(event, down: true) { super.keyDown(with: event) } }
    override func keyUp(with event: NSEvent) { if !sendKey(event, down: false) { super.keyUp(with: event) } }
    private func sendKey(_ event: NSEvent, down: Bool) -> Bool {
        let flags = event.modifierFlags
        var modifiers: Int16 = 0
        if flags.contains(.shift) { modifiers |= 1 }
        if flags.contains(.option) { modifiers |= 2 }
        if flags.contains(.command) { modifiers |= 4 }
        if flags.contains(.control) { modifiers |= 8 }
        return clap_vst3_editor_key(editor, event.charactersIgnoringModifiers?.utf16.first ?? 0, clap_vst3_editor_virtual_key(event.keyCode), modifiers, down ? 1 : 0) != 0
    }
}
