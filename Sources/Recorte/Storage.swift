import AppKit
import ImageIO

enum Store {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Recorte", isDirectory: true)

    static func ensureFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Saves a PNG tagged with the right DPI (so Retina captures paste at their real size).
    static func encode(_ image: CGImage, scale: CGFloat) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    static func save(_ image: CGImage, scale: CGFloat) throws -> (URL, Data) {
        ensureFolder()
        let png = try encode(image, scale: scale)
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "yyyy-MM-dd 'às' HH.mm.ss"
        let base = "Recorte \(f.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        try png.write(to: url)
        return (url, png)
    }

    static func recent(limit: Int = 300) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        }
        return Array(urls
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { date($0) > date($1) }
            .prefix(limit))
    }
}

enum Clipboard {
    /// Puts the image (PNG + TIFF, for older apps) and the file itself on the clipboard.
    static func copy(png: Data, url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        item.setString(url.absoluteString, forType: .fileURL)
        pb.writeObjects([item])
    }

    static func copyFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        copy(png: data, url: url)
    }
}

enum Thumbs {
    static func load(_ url: URL, maxPixel: Int = 480) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }.value
    }
}
