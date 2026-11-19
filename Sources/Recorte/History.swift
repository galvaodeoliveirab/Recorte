import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Histórico de capturas"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView())
            w.center()
            window = w
        }
        NotificationCenter.default.post(name: .recorteNewCapture, object: nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class HistoryModel: ObservableObject {
    @Published var items: [URL] = []
    func reload() { items = Store.recent() }
}

struct HistoryView: View {
    @StateObject private var model = HistoryModel()
    @State private var copied: URL?

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        Group {
            if model.items.isEmpty {
                ContentUnavailableView("Nenhuma captura ainda", systemImage: "camera.viewfinder",
                                       description: Text("Use ⌘⇧2 para recortar uma área ou janela."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.items, id: \.self) { url in
                            HistoryCell(url: url, copied: copied == url)
                                .onTapGesture(count: 2) { EditorWindowController.open(url: url) }
                                .onTapGesture {
                                    Clipboard.copyFile(url)
                                    copied = url
                                }
                                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                                .contextMenu {
                                    Button("Copiar") { Clipboard.copyFile(url); copied = url }
                                    Button("Editar / anotar") { EditorWindowController.open(url: url) }
                                    Button("Fixar na tela") { PinManager.shared.pin(url: url) }
                                    Button("Abrir no Pré-Visualização") { NSWorkspace.shared.open(url) }
                                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    Divider()
                                    Button("Apagar", role: .destructive) {
                                        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                        model.reload()
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .safeAreaInset(edge: .bottom) {
            Text("Clique para copiar  •  Duplo clique para editar  •  Arraste para outro app  •  Botão direito: mais opções")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .recorteNewCapture)) { _ in model.reload() }
    }
}

struct HistoryCell: View {
    let url: URL
    let copied: Bool
    @State private var thumb: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                if let thumb {
                    Image(decorative: thumb, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
                if copied {
                    Label("Copiado", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .frame(height: 120)
            Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Recorte ", with: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .task(id: url) { thumb = await Thumbs.load(url) }
    }
}
