import AppKit
import SwiftUI

/// Quick Access overlay: floating previews stacked at the bottom-left after each capture.
@MainActor
final class ThumbnailManager {
    static let shared = ThumbnailManager()

    private var panels: [ThumbnailPanel] = []   // oldest first (bottom of the stack)
    private let maxVisible = 6

    func show(url: URL, image: NSImage, on screen: NSScreen) {
        let width: CGFloat = 220
        let ratio = image.size.width / max(image.size.height, 1)
        let height = min(max(width / ratio, 124), 190)
        let size = CGSize(width: width, height: height)

        let panel = ThumbnailPanel(url: url, image: image, size: size, screen: screen)
        panel.onDropped = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.dismiss(panel)
        }

        let actions = ThumbnailActions(
            copy: { [weak self, weak panel] in
                Clipboard.copyFile(url)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    if let self, let panel { self.dismiss(panel) }
                }
            },
            save: { [weak self, weak panel] in
                if Exporter.saveAs(url: url), let self, let panel { self.dismiss(panel) }
            },
            edit: { [weak self, weak panel] in
                EditorWindowController.open(url: url)
                if let self, let panel { self.dismiss(panel) }
            },
            pin: { [weak self, weak panel] in
                PinManager.shared.pin(url: url)
                if let self, let panel { self.dismiss(panel) }
            },
            trash: { [weak self, weak panel] in
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                NotificationCenter.default.post(name: .recorteNewCapture, object: nil)
                if let self, let panel { self.dismiss(panel) }
            },
            close: { [weak self, weak panel] in
                if let self, let panel { self.dismiss(panel) }
            },
            hover: { [weak self, weak panel] inside in
                guard let self, let panel else { return }
                inside ? panel.cancelTimer() : self.schedule(panel, after: 4)
            })

        panel.contentView = NSHostingView(rootView: ThumbnailView(image: image, size: size, actions: actions))

        panels.append(panel)
        while panels.count > maxVisible { dismiss(panels[0]) }

        layout(animated: true, skip: panel)
        let final = frameFor(panel)
        panel.setFrame(final.offsetBy(dx: -(final.width + 30), dy: 0), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
        }
        schedule(panel, after: 10)
    }

    private func schedule(_ panel: ThumbnailPanel, after seconds: Double) {
        panel.cancelTimer()
        panel.timer = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, let panel else { return }
            self.dismiss(panel)
        }
    }

    func dismiss(_ panel: ThumbnailPanel) {
        guard let i = panels.firstIndex(where: { $0 === panel }) else { return }
        panels.remove(at: i)
        panel.cancelTimer()
        let off = panel.frame.offsetBy(dx: -(panel.frame.width + 30), dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(off, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
        layout(animated: true)
    }

    private func frameFor(_ panel: ThumbnailPanel) -> NSRect {
        let vf = panel.targetScreen.visibleFrame
        var y = vf.minY + 20
        for p in panels {
            if p === panel { break }
            if p.targetScreen == panel.targetScreen { y += p.frame.height + 12 }
        }
        return NSRect(x: vf.minX + 20, y: y, width: panel.frame.width, height: panel.frame.height)
    }

    private func layout(animated: Bool, skip: ThumbnailPanel? = nil) {
        for p in panels where p !== skip {
            let f = frameFor(p)
            if animated { p.animator().setFrame(f, display: true) } else { p.setFrame(f, display: true) }
        }
    }
}

struct ThumbnailActions {
    let copy: () -> Void
    let save: () -> Void
    let edit: () -> Void
    let pin: () -> Void
    let trash: () -> Void
    let close: () -> Void
    let hover: (Bool) -> Void
}

/// Non-activating panel that turns a mouse drag into a file drag (drop into any app).
final class ThumbnailPanel: NSPanel, NSDraggingSource {
    let url: URL
    let image: NSImage
    let targetScreen: NSScreen
    var timer: Task<Void, Never>?
    var onDropped: (() -> Void)?

    private var downPoint: NSPoint?
    private var dragging = false

    init(url: URL, image: NSImage, size: CGSize, screen: NSScreen) {
        self.url = url
        self.image = image
        self.targetScreen = screen
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            downPoint = event.locationInWindow
            dragging = false
        case .leftMouseDragged:
            if dragging { return }
            if let d = downPoint, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) > 5,
               let view = contentView {
                dragging = true
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(view.bounds, contents: image)
                view.beginDraggingSession(with: [item], event: event, source: self)
                return
            }
        case .leftMouseUp:
            downPoint = nil
            if dragging { dragging = false; return }
        default:
            break
        }
        super.sendEvent(event)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        downPoint = nil
        if operation != [] { onDropped?() }
    }
}

struct ThumbnailView: View {
    let image: NSImage
    let size: CGSize
    let actions: ThumbnailActions

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()

            if hovering {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.18)

                VStack(spacing: 8) {
                    pill(copied ? "Copiado ✓" : "Copiar") {
                        copied = true
                        actions.copy()
                    }
                    pill("Salvar", action: actions.save)
                }

                VStack {
                    HStack {
                        corner("xmark", help: "Fechar", action: actions.close)
                        Spacer()
                        corner("pencil", help: "Editar / anotar", action: actions.edit)
                    }
                    Spacer()
                    HStack {
                        corner("pin.fill", help: "Fixar na tela", action: actions.pin)
                        Spacer()
                        corner("trash", help: "Apagar", action: actions.trash)
                    }
                }
                .padding(7)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.22)))
        .onHover { inside in
            hovering = inside
            actions.hover(inside)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .frame(minWidth: 84)
                .background(Color.white.opacity(0.92), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func corner(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.92), in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

enum Exporter {
    /// Shows a save panel (Desktop by default). Returns true if saved.
    @MainActor
    @discardableResult
    static func saveAs(url: URL) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate()
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
