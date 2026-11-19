import AppKit
import SwiftUI

/// Pinned screenshots: borderless always-on-top windows. Drag to move, scroll to zoom,
/// Esc or double-click to close.
@MainActor
final class PinManager {
    static let shared = PinManager()
    private var windows: [PinWindow] = []

    func pin(url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let screen = CaptureController.screenUnderMouse()
        let window = PinWindow(image: image, screen: screen)
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            window.orderOut(nil)
            self.windows.removeAll { $0 === window }
        }
        window.contentView = NSHostingView(rootView: PinView(image: image,
                                                             onCopy: { Clipboard.copyFile(url) },
                                                             onClose: { window.onClose?() }))
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }
}

final class PinWindow: NSPanel {
    var onClose: (() -> Void)?
    private var lastDrag: NSPoint?
    private let ratio: CGFloat

    init(image: NSImage, screen: NSScreen) {
        let vf = screen.visibleFrame
        var size = image.size
        let maxW = vf.width * 0.6, maxH = vf.height * 0.6
        let k = min(1, maxW / size.width, maxH / size.height)
        size = NSSize(width: size.width * k, height: size.height * k)
        ratio = size.width / max(size.height, 1)
        let rect = NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                          width: size.width, height: size.height)
        super.init(contentRect: rect, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentAspectRatio = size
        minSize = NSSize(width: 60, height: 60 / max(ratio, 0.01))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            lastDrag = NSEvent.mouseLocation
        case .leftMouseDragged:
            if let last = lastDrag {
                let now = NSEvent.mouseLocation
                setFrameOrigin(NSPoint(x: frame.minX + now.x - last.x, y: frame.minY + now.y - last.y))
                lastDrag = now
            }
        case .leftMouseUp:
            lastDrag = nil
        case .scrollWheel:
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.05
            zoom(by: 1 + delta)
            return
        case .magnify:
            zoom(by: 1 + event.magnification)
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    private func zoom(by factor: CGFloat) {
        let w = min(max(frame.width * factor, 60), 4000)
        let h = w / ratio
        let f = NSRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
        setFrame(f, display: true)
    }
}

struct PinView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.92), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Fechar (Esc)")
                }
            }
            .overlay(Rectangle().strokeBorder(Color.white.opacity(hovering ? 0.5 : 0.15)))
            .onHover { hovering = $0 }
            .onTapGesture(count: 2, perform: onClose)
            .contextMenu {
                Button("Copiar", action: onCopy)
                Button("Fechar", action: onClose)
            }
    }
}
