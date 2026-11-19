import AppKit

/// Full-screen overlay showing a frozen snapshot of one display, where the user drags a region
/// or (after pressing Space) clicks a window.
final class SelectionWindow: NSWindow {
    init(frozen: FrozenScreen, controller: CaptureController) {
        super.init(contentRect: frozen.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(frozen.screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        contentView = SelectionView(frozen: frozen, controller: controller)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    let frozen: FrozenScreen
    unowned let controller: CaptureController

    private var start: NSPoint?
    private var current: NSPoint?
    private var mouse: NSPoint?
    private var hover: WindowTarget?

    private var pixelScale: CGFloat { CGFloat(frozen.image.width) / max(bounds.width, 1) }

    init(frozen: FrozenScreen, controller: CaptureController) {
        self.frozen = frozen
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: frozen.screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        super.updateTrackingAreas()
    }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        hover = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        updateHover()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if controller.isWindowMode {
            if let h = hover { controller.finishWindow(h, screen: frozen.screen) }
            return
        }
        start = p
        current = p
    }

    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { return }
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(p.x, 0), bounds.width)
        p.y = min(max(p.y, 0), bounds.height)
        current = p
        mouse = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let r = selection else { return }
        start = nil
        current = nil
        if r.width >= 4 && r.height >= 4 {
            controller.finishArea(rect: r, in: self, frozen: frozen)
        } else {
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) { controller.cancel() }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Esc
            controller.cancel()
        case 49: // Space
            start = nil
            current = nil
            controller.toggleWindowMode()
        default:
            break
        }
    }

    func refresh() {
        updateHover()
        needsDisplay = true
    }

    private func updateHover() {
        guard controller.isWindowMode, let m = mouse, let w = window else { hover = nil; return }
        hover = controller.window(at: NSPoint(x: m.x + w.frame.minX, y: m.y + w.frame.minY))
    }

    private var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(frozen.image, in: bounds)

        var hole = selection
        if controller.isWindowMode, let h = hover, let w = window {
            hole = NSRect(x: h.frame.minX - w.frame.minX, y: h.frame.minY - w.frame.minY,
                          width: h.frame.width, height: h.frame.height)
        }

        let dim = NSBezierPath(rect: bounds)
        if let hole {
            dim.appendRect(hole)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.38).setFill()
        dim.fill()

        if let hole {
            if controller.isWindowMode {
                NSColor.systemBlue.withAlphaComponent(0.18).setFill()
                hole.fill()
                NSColor.systemBlue.setStroke()
            } else {
                NSColor.white.setStroke()
            }
            let border = NSBezierPath(rect: hole.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            drawLabel("\(Int((hole.width * pixelScale).rounded())) × \(Int((hole.height * pixelScale).rounded()))", near: hole)
        } else if let m = mouse, !controller.isWindowMode {
            let guides = NSBezierPath()
            guides.move(to: NSPoint(x: m.x, y: 0)); guides.line(to: NSPoint(x: m.x, y: bounds.height))
            guides.move(to: NSPoint(x: 0, y: m.y)); guides.line(to: NSPoint(x: bounds.width, y: m.y))
            guides.lineWidth = 0.5
            guides.setLineDash([4, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.55).setStroke()
            guides.stroke()
        }

        if let m = mouse, selection == nil, !controller.isWindowMode {
            drawLoupe(at: m, in: ctx)
        }
        if mouse != nil || selection != nil {
            drawHint()
        }
    }

    private func pill(_ text: String, font: NSFont) -> (NSAttributedString, NSSize) {
        let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = s.size()
        return (s, NSSize(width: size.width + 14, height: size.height + 6))
    }

    private func drawPill(_ s: NSAttributedString, size: NSSize, at origin: NSPoint) {
        let r = NSRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: r, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        s.draw(at: NSPoint(x: r.minX + 7, y: r.minY + 3))
    }

    private func drawLabel(_ text: String, near rect: NSRect) {
        let (s, size) = pill(text, font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        var origin = NSPoint(x: rect.minX, y: rect.minY - size.height - 6)
        if origin.y < 4 { origin.y = rect.minY + 6 }
        origin.x = min(max(origin.x, 4), bounds.width - size.width - 4)
        drawPill(s, size: size, at: origin)
    }

    /// Pixel magnifier next to the cursor, like CleanShot's crosshair loupe.
    private func drawLoupe(at m: NSPoint, in ctx: CGContext) {
        let ps = pixelScale
        let n: CGFloat = 15
        let px = (m.x * ps).rounded(.down), py = ((bounds.height - m.y) * ps).rounded(.down)
        let src = CGRect(x: px - (n - 1) / 2, y: py - (n - 1) / 2, width: n, height: n)
        guard src.minX >= 0, src.minY >= 0,
              src.maxX <= CGFloat(frozen.image.width), src.maxY <= CGFloat(frozen.image.height),
              let crop = frozen.image.cropping(to: src) else { return }

        let size: CGFloat = 112
        var origin = NSPoint(x: m.x + 22, y: m.y - size - 22)
        if origin.x + size > bounds.width - 4 { origin.x = m.x - size - 22 }
        if origin.y < 4 { origin.y = m.y + 22 }
        let rect = NSRect(origin: origin, size: NSSize(width: size, height: size))
        let clip = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: rect)
        let cell = size / n
        let center = NSRect(x: rect.minX + cell * (n - 1) / 2, y: rect.minY + cell * (n - 1) / 2,
                            width: cell, height: cell)
        NSColor.white.setStroke()
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()
        ctx.interpolationQuality = .high

        NSColor.white.withAlphaComponent(0.9).setStroke()
        clip.lineWidth = 2
        clip.stroke()

        let (s, lsize) = pill("\(Int(px)), \(Int(py))", font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium))
        drawPill(s, size: lsize, at: NSPoint(x: rect.midX - lsize.width / 2, y: rect.minY - lsize.height - 4))
    }

    private func drawHint() {
        let prefix = controller.purpose == .text ? "Copiar texto  •  "
            : controller.purpose == .scroll ? "Captura com rolagem: selecione a área que rola  •  " : ""
        let text = prefix + (controller.isWindowMode
            ? "Clique numa janela  •  Espaço: voltar para área  •  Esc: cancelar"
            : "Arraste para recortar  •  Espaço: capturar janela  •  Esc: cancelar")
        let (s, size) = pill(text, font: .systemFont(ofSize: 12, weight: .medium))
        drawPill(s, size: size, at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 48))
    }
}
