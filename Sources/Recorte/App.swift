import AppKit
import Carbon.HIToolbox
import ServiceManagement

@main
@MainActor
enum RecorteApp {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

extension Notification.Name {
    static let recorteNewCapture = Notification.Name("recorteNewCapture")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyCenter()
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.ensureFolder()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Recorte")

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        buildMenu(menu)

        let mods = cmdKey | shiftKey
        hotKeys.register(id: 1, keyCode: kVK_ANSI_2, modifiers: mods) { CaptureController.shared.startSelection() }
        hotKeys.register(id: 2, keyCode: kVK_ANSI_1, modifiers: mods) { CaptureController.shared.captureFullScreen() }
        hotKeys.register(id: 4, keyCode: kVK_ANSI_7, modifiers: mods) { CaptureController.shared.startSelection(purpose: .text) }
        hotKeys.register(id: 5, keyCode: kVK_ANSI_8, modifiers: mods) { CaptureController.shared.startSelection(windowMode: true) }
        hotKeys.register(id: 6, keyCode: kVK_ANSI_0, modifiers: mods) { CaptureController.shared.startSelection(purpose: .scroll) }
        hotKeys.register(id: 3, keyCode: kVK_ANSI_9, modifiers: mods) { HistoryWindowController.shared.show() }

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    /// `open -a Recorte imagem.png` (or "Abrir com → Recorte") opens the image in the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { EditorWindowController.open(url: $0) }
    }

    private func item(_ title: String, _ action: Selector, key: String = "", shift: Bool = true,
                      icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
        i.target = self
        if let icon { i.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    /// Rebuilt every time the menu opens, so "recent captures" is always fresh.
    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Capturar área", #selector(captureArea), key: "2", icon: "viewfinder"))
        menu.addItem(item("Capturar tela inteira", #selector(captureFull), key: "1", icon: "camera"))
        menu.addItem(item("Capturar janela", #selector(captureWindow), key: "8", icon: "macwindow"))
        menu.addItem(item("Captura com rolagem", #selector(captureScroll), key: "0", icon: "arrow.down.to.line"))
        menu.addItem(item("Copiar texto da tela (OCR)", #selector(captureText), key: "7", icon: "text.viewfinder"))

        let timer = NSMenuItem(title: "Temporizador", action: nil, keyEquivalent: "")
        timer.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let sub = NSMenu()
        for s in [3, 5, 10] {
            let t = item("\(s) segundos", #selector(selfTimer(_:)))
            t.tag = s
            sub.addItem(t)
        }
        timer.submenu = sub
        menu.addItem(timer)

        menu.addItem(.separator())
        let hide = item("Esconder ícones da mesa", #selector(toggleDesktopIcons), icon: "eye.slash")
        hide.state = DesktopCover.shared.isActive ? .on : .off
        menu.addItem(hide)

        menu.addItem(.separator())
        menu.addItem(item("Abrir no editor…", #selector(openInEditor), icon: "pencil"))
        menu.addItem(item("Fixar na tela…", #selector(pinFromFile), icon: "pin"))

        let recent = Store.recent(limit: 5)
        if !recent.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Capturas recentes", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for url in recent {
                let r = NSMenuItem(title: url.deletingPathExtension().lastPathComponent
                                    .replacingOccurrences(of: "Recorte ", with: ""),
                                   action: #selector(openRecent(_:)), keyEquivalent: "")
                r.target = self
                r.representedObject = url
                r.image = Self.menuThumb(url)
                r.toolTip = "Clique para mostrar as opções (copiar, editar, fixar…)"
                menu.addItem(r)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Histórico de capturas…", #selector(openHistory), key: "9", icon: "clock.arrow.circlepath"))
        menu.addItem(item("Abrir pasta de capturas", #selector(openFolder), icon: "folder"))
        menu.addItem(.separator())
        loginItem = item("Iniciar com o Mac", #selector(toggleLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(item("Sair do Recorte", #selector(quit), key: "q", shift: false))
    }

    private static func menuThumb(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary) else { return nil }
        let box = NSSize(width: 36, height: 24)
        let img = NSImage(size: box, flipped: false) { rect in
            let k = min(rect.width / CGFloat(cg.width), rect.height / CGFloat(cg.height))
            let w = CGFloat(cg.width) * k, h = CGFloat(cg.height) * k
            let r = NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h)
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
            NSImage(cgImage: cg, size: r.size).draw(in: r)
            return true
        }
        return img
    }

    @objc private func captureScroll() { CaptureController.shared.startSelection(purpose: .scroll) }
    @objc private func captureWindow() { CaptureController.shared.startSelection(windowMode: true) }

    @objc private func selfTimer(_ sender: NSMenuItem) {
        let seconds = sender.tag
        Task { @MainActor in
            for left in stride(from: seconds, to: 0, by: -1) {
                Toast.show("Capturando em \(left)…", icon: "timer")
                try? await Task.sleep(for: .seconds(1))
            }
            CaptureController.shared.startSelection()
        }
    }

    @objc private func toggleDesktopIcons() { DesktopCover.shared.toggle() }

    private func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = Store.folder
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc private func openInEditor() { if let u = pickImage() { EditorWindowController.open(url: u) } }
    @objc private func pinFromFile() { if let u = pickImage() { PinManager.shared.pin(url: u) } }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, let image = NSImage(contentsOf: url) else { return }
        ThumbnailManager.shared.show(url: url, image: image, on: CaptureController.screenUnderMouse())
    }

    @objc private func captureArea() { CaptureController.shared.startSelection() }
    @objc private func captureText() { CaptureController.shared.startSelection(purpose: .text) }
    @objc private func captureFull() { CaptureController.shared.captureFullScreen() }
    @objc private func openHistory() { HistoryWindowController.shared.show() }
    @objc private func openFolder() { NSWorkspace.shared.open(Store.folder) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }
}

/// Global hotkeys via Carbon (no Accessibility permission required).
final class HotKeyCenter {
    nonisolated(unsafe) static var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let id = hk.id
                DispatchQueue.main.async { HotKeyCenter.handlers[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        HotKeyCenter.handlers[id] = action
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         EventHotKeyID(signature: OSType(0x5243_5254), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Recorte: atalho \(id) já está em uso (\(status))") }
        refs.append(ref)
    }
}
