import AppKit
import SwiftUI
import Vision

enum OCR {
    static func recognize(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}

/// Small HUD message near the bottom-center of the screen.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, icon: String = "checkmark.circle.fill") {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let view = HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 13, weight: .semibold)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.78), in: Capsule())
        .fixedSize()

        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let vf = CaptureController.screenUnderMouse().visibleFrame
        let p = NSPanel(contentRect: NSRect(x: vf.midX - size.width / 2, y: vf.minY + 80,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        p.orderFrontRegardless()
        panel = p

        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                                 completionHandler: { p.orderOut(nil) })
        }
    }
}
