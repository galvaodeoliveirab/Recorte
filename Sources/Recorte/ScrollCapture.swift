import AppKit
import ScreenCaptureKit
import SwiftUI

/// Scrolling capture: the user scrolls a region while we grab frames; `ScrollStitcher`
/// places each frame in the page built so far.
@MainActor
final class ScrollCapture: ObservableObject {
    static let shared = ScrollCapture()

    @Published var heightPx = 0
    @Published var warning = false
    private(set) var active = false

    private var screen: NSScreen!
    private var scale: CGFloat = 1
    private var filter: SCContentFilter?
    private var config = SCStreamConfiguration()
    private var loop: Task<Void, Never>?
    private var border: NSWindow?
    private var controls: NSPanel?

    private var width = 0
    private var frameHeight = 0
    private var stitcher: ScrollStitcher?
    private var warningTask: Task<Void, Never>?

    
    /// `rect` in Cocoa global coordinates.
    func start(rect: NSRect, screen: NSScreen) {
        guard !active else { return }
        active = true
        self.screen = screen
        scale = screen.backingScaleFactor
        heightPx = 0
        warning = false
        stitcher = nil

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let id = screen.displayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else { stop(); return }
                let mine = content.applications.filter { $0.processID == getpid() }
                filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])

                let r = rect.intersection(screen.frame)
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: r.minX - screen.frame.minX, y: screen.frame.maxY - r.maxY,
                                        width: r.width, height: r.height)
                width = Int((r.width * scale).rounded())
                frameHeight = Int((r.height * scale).rounded())
                cfg.width = width
                cfg.height = frameHeight
                stitcher = ScrollStitcher(width: width, frameHeight: frameHeight)
                cfg.showsCursor = false
                cfg.captureResolution = .best
                config = cfg

                showChrome(around: r)
                loop = Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.tick()
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }
            } catch {
                stop()
                Permissions.report(error)
            }
        }
    }

    func finish() {
        let w = width, out = stitcher?.output
        stop()
        guard let out, let image = Stitcher.makeImage(out.data, width: w, height: out.height) else { return }
        CaptureController.shared.deliver(image, scale: scale, screen: screen)
    }

    func cancel() { stop() }

    private func stop() {
        loop?.cancel()
        loop = nil
        border?.orderOut(nil)
        controls?.orderOut(nil)
        border = nil
        controls = nil
        stitcher = nil
        active = false
    }

    // MARK: - Frames

    private func tick() async {
        guard let filter, active else { return }
        guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              active, let rgba = Stitcher.pixels(img, width: width, height: frameHeight) else { return }
        guard var st = stitcher else { return }
        let result = st.add(rgba)
        stitcher = st
        heightPx = st.output.height
        if result == .lost { flagWarning() }
    }

    private func flagWarning() {
        warning = true
        warningTask?.cancel()
        warningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { self?.warning = false }
        }
    }

    // MARK: - On-screen chrome (click-through border + control bar)

    private func showChrome(around r: NSRect) {
        let b = NSWindow(contentRect: r.insetBy(dx: -3, dy: -3), styleMask: .borderless,
                         backing: .buffered, defer: false)
        b.level = .statusBar
        b.isOpaque = false
        b.backgroundColor = .clear
        b.ignoresMouseEvents = true
        b.hasShadow = false
        b.isReleasedWhenClosed = false
        b.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        b.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        b.orderFrontRegardless()
        border = b

        let host = NSHostingView(rootView: ScrollControls(session: self))
        let size = host.fittingSize
        let vf = screen.visibleFrame
        var y = r.minY - size.height - 12
        if y < vf.minY + 8 { y = min(r.maxY + 12, vf.maxY - size.height - 8) }
        if y + size.height > vf.maxY { y = r.minY + 12 }
        let x = min(max(r.midX - size.width / 2, vf.minX + 8), vf.maxX - size.width - 8)
        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        p.orderFrontRegardless()
        controls = p
    }
}

struct ScrollControls: View {
    @ObservedObject var session: ScrollCapture

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.warning ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                .foregroundStyle(session.warning ? .yellow : .white)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.warning ? "Rápido demais — volte um pouco" : "Role a página para baixo")
                    .font(.system(size: 12, weight: .semibold))
                Text("Altura: \(session.heightPx) px")
                    .font(.system(size: 10).monospacedDigit())
                    .opacity(0.75)
            }
            .frame(width: 200, alignment: .leading)
            Button("Cancelar") { session.cancel() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.15), in: Capsule())
            Button("Concluir") { session.finish() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.white, in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.8), in: Capsule())
        .fixedSize()
    }
}
