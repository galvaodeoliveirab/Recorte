import AppKit

/// "Hide desktop icons": covers the icons with the wallpaper (non-destructive, Finder untouched).
@MainActor
final class DesktopCover {
    static let shared = DesktopCover()
    private var windows: [NSWindow] = []

    var isActive: Bool { !windows.isEmpty }
    var windowIDs: Set<CGWindowID> { Set(windows.map { CGWindowID($0.windowNumber) }) }

    func toggle() { isActive ? hide() : show() }

    func show() {
        hide()
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let img = NSImage(contentsOf: url) {
                view.layer?.contents = img
                view.layer?.contentsGravity = .resizeAspectFill
            }
            if let fill = NSWorkspace.shared.desktopImageOptions(for: screen)?[.fillColor] as? NSColor {
                view.layer?.backgroundColor = fill.cgColor
            }
            w.contentView = view
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
