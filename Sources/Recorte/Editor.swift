import AppKit
import CoreImage
import SwiftUI

// MARK: - Model

enum Tool: String, CaseIterable, Identifiable {
    case arrow, rect, ellipse, line, pen, highlighter, text, pixelate, counter
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pen: "scribble"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .counter: "1.circle"
        }
    }

    var name: String {
        switch self {
        case .arrow: "Seta (A)"
        case .rect: "Retângulo (R)"
        case .ellipse: "Elipse (O)"
        case .line: "Linha (L)"
        case .pen: "Caneta (P)"
        case .highlighter: "Marca-texto (H)"
        case .text: "Texto (T)"
        case .pixelate: "Borrar / ocultar (B)"
        case .counter: "Contador (N)"
        }
    }

    var key: Character {
        switch self {
        case .arrow: "a"
        case .rect: "r"
        case .ellipse: "o"
        case .line: "l"
        case .pen: "p"
        case .highlighter: "h"
        case .text: "t"
        case .pixelate: "b"
        case .counter: "n"
        }
    }
}

struct Mark: Identifiable {
    let id = UUID()
    var tool: Tool
    var color: Color
    var width: CGFloat
    var points: [CGPoint]
    var text = ""
    var number = 0
}

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    let base: CGImage
    let scale: CGFloat
    let pointSize: CGSize
    let pixelated: CGImage?

    @Published var marks: [Mark] = []
    @Published var draft: Mark?
    @Published var tool: Tool = .arrow
    @Published var color: Color = .red
    @Published var width: CGFloat = 4
    @Published var textPoint: CGPoint?
    @Published var textValue = ""

    static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    static let widths: [CGFloat] = [2, 4, 8]

    init?(url: URL) {
        guard let ns = NSImage(contentsOf: url),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.url = url
        base = cg
        scale = max(CGFloat(cg.width) / max(ns.size.width, 1), 1)
        pointSize = CGSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale)

        let ci = CIImage(cgImage: cg)
        let px = ci.clampedToExtent()
            .applyingFilter("CIPixellate", parameters: ["inputScale": max(10, 9 * scale),
                                                         kCIInputCenterKey: CIVector(x: 0, y: 0)])
            .cropped(to: ci.extent)
        pixelated = CIContext().createCGImage(px, from: ci.extent)
    }

    var nextNumber: Int { marks.filter { $0.tool == .counter }.count + 1 }

    func commitText() {
        if let p = textPoint, !textValue.trimmingCharacters(in: .whitespaces).isEmpty {
            marks.append(Mark(tool: .text, color: color, width: width, points: [p], text: textValue))
        }
        textPoint = nil
        textValue = ""
    }

    func undo() {
        if textPoint != nil { textPoint = nil; textValue = ""; return }
        _ = marks.popLast()
    }

    func render() -> CGImage? {
        commitText()
        let layer = AnnotationLayer(base: base, scale: scale, pointSize: pointSize, pixelated: pixelated,
                                    marks: marks, fit: 1)
            .frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: layer)
        renderer.scale = scale
        return renderer.cgImage
    }
}

// MARK: - Drawing

enum MarkRenderer {
    static func fontSize(_ width: CGFloat) -> CGFloat { 12 + width * 3 }

    static func draw(_ m: Mark, in ctx: inout GraphicsContext, pixelated: Image?, size: CGSize) {
        guard let a = m.points.first else { return }
        let b = m.points.last ?? a
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        let style = StrokeStyle(lineWidth: m.width, lineCap: .round, lineJoin: .round)

        switch m.tool {
        case .rect:
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(m.color), style: style)
        case .ellipse:
            ctx.stroke(Path(ellipseIn: rect), with: .color(m.color), style: style)
        case .line:
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(m.color), style: style)
        case .arrow:
            drawArrow(from: a, to: b, color: m.color, width: m.width, in: &ctx)
        case .pen:
            ctx.stroke(freehand(m.points), with: .color(m.color), style: style)
        case .highlighter:
            ctx.drawLayer { layer in
                layer.blendMode = .multiply
                layer.stroke(freehand(m.points), with: .color(m.color.opacity(0.45)),
                             style: StrokeStyle(lineWidth: m.width * 4 + 6, lineCap: .round, lineJoin: .round))
            }
        case .pixelate:
            if let pixelated {
                ctx.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    layer.draw(pixelated, in: CGRect(origin: .zero, size: size))
                }
            }
        case .text:
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 1))
            shadowed.draw(Text(m.text)
                            .font(.system(size: fontSize(m.width), weight: .bold))
                            .foregroundColor(m.color),
                          at: a, anchor: .topLeading)
        case .counter:
            let r = 11 + m.width
            let circle = CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1))
            shadowed.fill(Path(ellipseIn: circle), with: .color(m.color))
            ctx.stroke(Path(ellipseIn: circle), with: .color(.white), lineWidth: 2)
            ctx.draw(Text("\(m.number)").font(.system(size: r * 1.1, weight: .bold)).foregroundColor(.white),
                     at: a, anchor: .center)
        }
    }

    private static func freehand(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count < 3 {
            pts.dropFirst().forEach { p.addLine(to: $0) }
            return p
        }
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    private static func drawArrow(from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat,
                                  in ctx: inout GraphicsContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 2 else { return }
        let angle = atan2(dy, dx)
        let head = max(14, width * 4)
        let shaftEnd = CGPoint(x: b.x - cos(angle) * head * 0.7, y: b.y - sin(angle) * head * 0.7)

        var shaft = Path(); shaft.move(to: a); shaft.addLine(to: shaftEnd)
        var tip = Path()
        tip.move(to: b)
        tip.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
        tip.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
        tip.closeSubpath()

        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1))
        shadowed.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        shadowed.fill(tip, with: .color(color))
        shadowed.stroke(tip, with: .color(color), style: StrokeStyle(lineWidth: max(1, width / 2), lineJoin: .round))
    }
}

/// Base image + marks. Used both on screen (fit < 1) and for export (fit = 1).
struct AnnotationLayer: View {
    let base: CGImage
    let scale: CGFloat
    let pointSize: CGSize
    let pixelated: CGImage?
    let marks: [Mark]
    let fit: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: fit, y: fit)
            let rect = CGRect(origin: .zero, size: pointSize)
            ctx.draw(Image(decorative: base, scale: scale), in: rect)
            let pix = pixelated.map { Image(decorative: $0, scale: scale) }
            for m in marks {
                MarkRenderer.draw(m, in: &ctx, pixelated: pix, size: pointSize)
            }
        }
    }
}

// MARK: - Window

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private static var open: [EditorWindowController] = []

    private let window: NSWindow
    private let model: EditorModel

    static func open(url: URL) {
        guard let model = EditorModel(url: url) else { return }
        let c = EditorWindowController(model: model)
        open.append(c)
        NSApp.activate()
        c.window.makeKeyAndOrderFront(nil)
    }

    private init(model: EditorModel) {
        self.model = model
        let vf = CaptureController.screenUnderMouse().visibleFrame
        let w = min(max(model.pointSize.width + 60, 760), vf.width * 0.85)
        let h = min(max(model.pointSize.height + 120, 480), vf.height * 0.85)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Editar captura"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 720, height: 420)
        window.contentView = NSHostingView(rootView: EditorView(model: model, onDone: { [weak self] in self?.done() }))
        window.center()
    }

    private func done() {
        guard let img = model.render() else { return }
        do {
            let png = try Store.encode(img, scale: model.scale)
            try png.write(to: model.url)
            Clipboard.copy(png: png, url: model.url)
            NotificationCenter.default.post(name: .recorteNewCapture, object: model.url)
            let size = NSSize(width: model.pointSize.width, height: model.pointSize.height)
            ThumbnailManager.shared.show(url: model.url, image: NSImage(cgImage: img, size: size),
                                         on: CaptureController.screenUnderMouse())
            window.close()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    let onDone: () -> Void
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let fit = min((geo.size.width - 40) / model.pointSize.width,
                              (geo.size.height - 40) / model.pointSize.height, 1)
                let display = CGSize(width: model.pointSize.width * fit, height: model.pointSize.height * fit)
                ZStack(alignment: .topLeading) {
                    AnnotationLayer(base: model.base, scale: model.scale, pointSize: model.pointSize,
                                    pixelated: model.pixelated,
                                    marks: model.marks + (model.draft.map { [$0] } ?? []), fit: fit)
                        .frame(width: display.width, height: display.height)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(fit: fit))

                    if let p = model.textPoint {
                        TextField("Digite…", text: $model.textValue)
                            .textFieldStyle(.plain)
                            .font(.system(size: MarkRenderer.fontSize(model.width) * fit, weight: .bold))
                            .foregroundColor(model.color)
                            .frame(minWidth: 160)
                            .fixedSize()
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor.opacity(0.7), lineWidth: 1))
                            .offset(x: p.x * fit - 2, y: p.y * fit - 2)
                            .focused($textFocused)
                            .onSubmit { model.commitText() }
                            .onAppear { textFocused = true }
                    }
                }
                .frame(width: display.width, height: display.height)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .background(shortcuts)
    }

    private func drawGesture(fit: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / fit, y: v.location.y / fit)
                switch model.tool {
                case .text, .counter:
                    return
                case .pen, .highlighter:
                    if model.draft == nil {
                        model.commitText()
                        model.draft = Mark(tool: model.tool, color: model.color, width: model.width, points: [p])
                    } else {
                        model.draft?.points.append(p)
                    }
                default:
                    if model.draft == nil {
                        model.commitText()
                        model.draft = Mark(tool: model.tool, color: model.color, width: model.width, points: [p, p])
                    } else {
                        model.draft?.points[1] = p
                    }
                }
            }
            .onEnded { v in
                let p = CGPoint(x: v.location.x / fit, y: v.location.y / fit)
                switch model.tool {
                case .text:
                    model.commitText()
                    model.textPoint = p
                case .counter:
                    model.commitText()
                    model.marks.append(Mark(tool: .counter, color: model.color, width: model.width,
                                            points: [p], number: model.nextNumber))
                default:
                    if var d = model.draft {
                        if d.points.count >= 2 {
                            let a = d.points[0], b = d.points[d.points.count - 1]
                            if d.tool == .pen || d.tool == .highlighter || hypot(a.x - b.x, a.y - b.y) > 3 {
                                if d.tool != .pen && d.tool != .highlighter { d.points = [a, p] }
                                model.marks.append(d)
                            }
                        }
                    }
                    model.draft = nil
                }
            }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Tool.allCases) { t in
                    Button {
                        model.commitText()
                        model.tool = t
                    } label: {
                        Image(systemName: t.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 26)
                            .background(model.tool == t ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.name)
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 5) {
                ForEach(Array(EditorModel.palette.enumerated()), id: \.offset) { _, c in
                    Circle()
                        .fill(c)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                        .padding(2)
                        .overlay(Circle().stroke(model.color == c ? Color.accentColor : .clear, lineWidth: 2))
                        .onTapGesture { model.color = c }
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 2) {
                ForEach(EditorModel.widths, id: \.self) { w in
                    Button { model.width = w } label: {
                        Circle().frame(width: w + 3, height: w + 3)
                            .frame(width: 24, height: 24)
                            .background(model.width == w ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Espessura")
                }
            }

            Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                .help("Desfazer (⌘Z)")
                .disabled(model.marks.isEmpty && model.textPoint == nil)

            Spacer()

            Button("Copiar") {
                if let img = model.render(), let png = try? Store.encode(img, scale: model.scale) {
                    Clipboard.copy(png: png, url: model.url)
                }
            }
            Button("Salvar como…") {
                if let img = model.render(), let png = try? Store.encode(img, scale: model.scale) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(model.url.lastPathComponent)
                    try? png.write(to: tmp)
                    Exporter.saveAs(url: tmp)
                }
            }
            Button("Concluir", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Hidden buttons for keyboard shortcuts (undo + single-letter tool keys).
    private var shortcuts: some View {
        ZStack {
            Button("", action: model.undo).keyboardShortcut("z", modifiers: .command)
            ForEach(Tool.allCases) { t in
                Button("") { if model.textPoint == nil { model.tool = t } }
                    .keyboardShortcut(KeyEquivalent(t.key), modifiers: [])
                    .disabled(model.textPoint != nil)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
