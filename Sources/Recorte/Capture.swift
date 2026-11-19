import AppKit
import ScreenCaptureKit

struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
}

struct WindowTarget {
    let id: CGWindowID
    /// Cocoa global coordinates (origin bottom-left of the primary screen).
    let frame: CGRect
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private var overlays: [SelectionWindow] = []
    private var windows: [WindowTarget] = []
    private var content: SCShareableContent?
    private(set) var windowMode = false
    private(set) var purpose: Purpose = .image
    private var busy = false

    enum Purpose { case image, text, scroll }

    // MARK: - Entry points

    func startSelection(purpose: Purpose = .image, windowMode startInWindowMode: Bool = false) {
        guard !busy, !ScrollCapture.shared.active else { return }
        busy = true
        self.purpose = purpose
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                self.content = content
                self.windows = Self.windowsFrontToBack()
                var frozen: [FrozenScreen] = []
                for screen in NSScreen.screens {
                    if let img = try await self.snapshot(screen: screen, content: content) {
                        frozen.append(FrozenScreen(screen: screen, image: img))
                    }
                }
                self.showOverlays(frozen)
                if startInWindowMode { self.toggleWindowMode() }
            } catch {
                self.busy = false
                Permissions.report(error)
            }
        }
    }

    func captureFullScreen() {
        guard !busy else { return }
        busy = true
        Task {
            defer { self.busy = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let screen = Self.screenUnderMouse()
                if let img = try await self.snapshot(screen: screen, content: content) {
                    self.deliver(img, scale: CGFloat(img.width) / screen.frame.width, screen: screen)
                }
            } catch {
                Permissions.report(error)
            }
        }
    }

    // MARK: - Overlay callbacks

    var isWindowMode: Bool { windowMode }

    func toggleWindowMode() {
        windowMode.toggle()
        overlays.forEach { ($0.contentView as? SelectionView)?.refresh() }
    }

    func window(at point: NSPoint) -> WindowTarget? {
        windows.first { $0.frame.contains(point) }
    }

    func cancel() {
        closeOverlays()
        busy = false
    }

    func finishArea(rect: NSRect, in view: NSView, frozen: FrozenScreen) {
        let s = CGFloat(frozen.image.width) / view.bounds.width
        let crop = CGRect(x: rect.minX * s,
                          y: (view.bounds.height - rect.maxY) * s,
                          width: rect.width * s,
                          height: rect.height * s).integral
        closeOverlays()
        busy = false
        if purpose == .scroll {
            let global = rect.offsetBy(dx: frozen.screen.frame.minX, dy: frozen.screen.frame.minY)
            return ScrollCapture.shared.start(rect: global, screen: frozen.screen)
        }
        guard let img = frozen.image.cropping(to: crop) else { return }
        complete(img, scale: s, screen: frozen.screen)
    }

    func finishWindow(_ target: WindowTarget, screen: NSScreen) {
        closeOverlays()
        if purpose == .scroll {
            busy = false
            return ScrollCapture.shared.start(rect: target.frame, screen: screen)
        }
        Task {
            defer { self.busy = false }
            guard let content = self.content,
                  let scWindow = content.windows.first(where: { $0.windowID == target.id }) else { return }
            do {
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let scale = CGFloat(filter.pointPixelScale)
                let cfg = SCStreamConfiguration()
                cfg.width = Int(filter.contentRect.width * scale)
                cfg.height = Int(filter.contentRect.height * scale)
                cfg.showsCursor = false
                cfg.captureResolution = .best
                cfg.ignoreShadowsSingleWindow = true
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                self.complete(img, scale: scale, screen: screen)
            } catch {
                Permissions.report(error)
            }
        }
    }

    // MARK: - Internals

    private func snapshot(screen: NSScreen, content: SCShareableContent) async throws -> CGImage? {
        guard let id = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let mine = content.applications.filter { $0.processID == getpid() }
        // Our own windows are hidden from captures, except the "hide desktop icons" cover.
        let coverIDs = DesktopCover.shared.windowIDs
        let keep = content.windows.filter { coverIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: keep)
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    private func showOverlays(_ frozen: [FrozenScreen]) {
        windowMode = false
        overlays = frozen.map { SelectionWindow(frozen: $0, controller: self) }
        NSApp.activate()
        overlays.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        (overlays.first { $0.frame.contains(mouse) } ?? overlays.first)?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }

    private func closeOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    private func complete(_ image: CGImage, scale: CGFloat, screen: NSScreen) {
        guard purpose == .text else { return deliver(image, scale: scale, screen: screen) }
        Task {
            let text = await OCR.recognize(image)
            if text.isEmpty {
                Toast.show("Nenhum texto encontrado", icon: "text.magnifyingglass")
            } else {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                Sound.play()
                Toast.show("Texto copiado (\(text.count) caracteres)", icon: "text.viewfinder")
            }
        }
    }

    func deliver(_ image: CGImage, scale: CGFloat, screen: NSScreen) {
        do {
            let (url, png) = try Store.save(image, scale: scale)
            Clipboard.copy(png: png, url: url)
            Sound.play()
            let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            ThumbnailManager.shared.show(url: url, image: NSImage(cgImage: image, size: size), on: screen)
            NotificationCenter.default.post(name: .recorteNewCapture, object: url)
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    static func screenUnderMouse() -> NSScreen {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Normal app windows, front-most first.
    static func windowsFrontToBack() -> [WindowTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let me = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  b.width > 40, b.height > 40 else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { return nil }
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
            return WindowTarget(id: CGWindowID(number.uint32Value), frame: frame)
        }
    }
}

enum Permissions {
    @MainActor
    static func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "O Recorte precisa de permissão para gravar a tela"
        alert.informativeText = """
        Ative o Recorte em Ajustes do Sistema → Privacidade e Segurança → \
        Gravação de Tela e Áudio do Sistema. Depois, abra o Recorte de novo.

        Detalhe: \(error.localizedDescription)
        """
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Sound {
    @MainActor private static let shutter = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)

    @MainActor static func play() {
        shutter?.stop()
        shutter?.play()
    }
}
