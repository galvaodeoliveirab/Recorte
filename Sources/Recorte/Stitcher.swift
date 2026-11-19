import CoreGraphics
import Foundation

/// Pure image helpers for scrolling capture (kept free of UI so they can be tested).
enum Stitcher {
    /// Luminance samples per row used for matching.
    static let cols = 48

    static func pixels(_ image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? buf : nil
    }

    /// Per row: luminance at `cols` sample columns (ignoring the edges, where scrollbars live).
    static func signature(_ rgba: [UInt8], width w: Int, height h: Int) -> [UInt8] {
        var sig = [UInt8](repeating: 0, count: h * cols)
        let x0 = w / 20, usable = max(w - 2 * x0, 1)
        rgba.withUnsafeBufferPointer { px in
            for y in 0..<h {
                let row = y * w * 4
                for k in 0..<cols {
                    let i = row + (x0 + k * usable / cols) * 4
                    let lum = (Int(px[i]) * 77 + Int(px[i + 1]) * 150 + Int(px[i + 2]) * 29) >> 8
                    sig[y * cols + k] = UInt8(lum)
                }
            }
        }
        return sig
    }

    static func makeImage(_ data: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard h > 0, let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Builds one tall page from frames of a scrolling region.
///
/// Robust to the user scrolling up/down, scrolling too fast, and sticky headers/footers:
/// - Every frame is located *in the page built so far* (not just vs. the previous frame),
///   so scrolling back up never duplicates content, and after a too-fast jump the next
///   overlapping frame continues from the right place.
/// - Rows that stay identical while the content moves are treated as a sticky header
///   (top) or footer (bottom): they are ignored for matching, never appended in the middle,
///   and the footer is added once at the very end.
struct ScrollStitcher {
    enum Result: Equatable { case started, still, appended(Int), inside, lost }

    let width: Int
    let frameHeight: Int

    private(set) var pageHeight = 0
    private var page: [UInt8] = []        // RGBA rows of the page (without the sticky footer)
    private var pageSig: [UInt8] = []
    private var prevSig: [UInt8]?
    private var lastFrame: [UInt8] = []
    private var lastPos = 0
    private var top = 0                   // sticky header rows
    private var bottom = 0                // sticky footer rows

    static let maxPageHeight = 40_000
    private let c = Stitcher.cols

    init(width: Int, frameHeight: Int) {
        self.width = width
        self.frameHeight = frameHeight
    }

    /// Final image bytes and height (page + sticky footer once).
    var output: (data: [UInt8], height: Int) {
        guard bottom > 0, !lastFrame.isEmpty else { return (page, pageHeight) }
        let rb = width * 4
        return (page + lastFrame[((frameHeight - bottom) * rb)..<(frameHeight * rb)], pageHeight + bottom)
    }

    mutating func add(_ rgba: [UInt8]) -> Result {
        let fh = frameHeight
        let sig = Stitcher.signature(rgba, width: width, height: fh)

        guard let prev = prevSig else {
            page = rgba
            pageSig = sig
            pageHeight = fh
            prevSig = sig
            lastFrame = rgba
            return .started
        }

        if rowsDiff(prev, sig, from: 0, to: fh) <= 15 { return .still }

        // Sticky bands: rows identical between two frames whose content moved.
        let (t, b) = staticBands(prev, sig)
        prevSig = sig
        if b > bottom {
            // A footer appeared: drop its copy from the end of the page.
            let cut = min(pageHeight, lastPos + fh - b)
            if cut < pageHeight { truncate(to: max(cut, 0)) }
        }
        top = t
        bottom = b

        guard let pos = locate(sig) else { return .lost }
        lastPos = pos
        lastFrame = rgba

        let bandEnd = fh - bottom
        let from = max(pageHeight - pos, top)
        guard from < bandEnd, pageHeight < Self.maxPageHeight else { return .inside }
        let rb = width * 4
        page.append(contentsOf: rgba[(from * rb)..<(bandEnd * rb)])
        pageSig.append(contentsOf: sig[(from * c)..<(bandEnd * c)])
        let added = pos + bandEnd - pageHeight
        pageHeight = pos + bandEnd
        return .appended(added)
    }

    // MARK: - Internals

    private mutating func truncate(to h: Int) {
        page.removeSubrange((h * width * 4)...)
        pageSig.removeSubrange((h * c)...)
        pageHeight = h
    }

    /// Mean absolute difference ×10 between the same rows of two frame signatures.
    private func rowsDiff(_ a: [UInt8], _ b: [UInt8], from: Int, to: Int) -> Int {
        var sum = 0, n = 0
        var r = from
        while r < to {
            for k in 0..<c { sum += abs(Int(a[r * c + k]) - Int(b[r * c + k])) }
            n += c
            r += 2
        }
        return n == 0 ? 0 : sum * 10 / n
    }

    private func staticBands(_ a: [UInt8], _ b: [UInt8]) -> (Int, Int) {
        let fh = frameHeight
        func same(_ r: Int) -> Bool {
            var s = 0
            for k in 0..<c { s += abs(Int(a[r * c + k]) - Int(b[r * c + k])) }
            return s <= c * 2
        }
        let cap = fh * 3 / 10
        var t = 0
        while t < cap && same(t) { t += 1 }
        var bo = 0
        while bo < cap && same(fh - 1 - bo) { bo += 1 }
        // Ignore tiny bands (noise) — a real sticky bar is at least a few rows tall.
        return (t >= 6 ? t : 0, bo >= 6 ? bo : 0)
    }

    /// Finds where the frame's top sits in page coordinates.
    private func locate(_ sig: [UInt8]) -> Int? {
        let fh = frameHeight
        let bandStart = top, bandEnd = fh - bottom
        let minOverlap = max((bandEnd - bandStart) / 6, 16)
        let maxPos = pageHeight - bandStart - minOverlap
        guard maxPos >= 0 else { return nil }

        func diff(_ pos: Int, cutoff: Int) -> Int {
            let end = min(bandEnd, pageHeight - pos)
            guard end - bandStart >= minOverlap else { return Int.max }
            var sum = 0, n = 0
            var r = bandStart
            while r < end {
                let a = (pos + r) * c, b = r * c
                for k in 0..<c { sum += abs(Int(pageSig[a + k]) - Int(sig[b + k])) }
                n += c
                r += 2
                if n >= 1536 && sum * 10 / n > cutoff { return Int.max }
            }
            return n == 0 ? Int.max : sum * 10 / n
        }

        func search(_ range: ClosedRange<Int>) -> (pos: Int, d: Int) {
            var best = (pos: -1, d: Int.max)
            var scores: [(Int, Int)] = []
            for pos in range {
                let d = diff(pos, cutoff: best.d == Int.max ? Int.max : best.d + 30)
                if d != Int.max { scores.append((pos, d)) }
                if d < best.d { best = (pos, d) }
            }
            // Ties (repetitive/blank content): prefer the candidate closest to the last position.
            if best.d != Int.max {
                let near = scores.filter { $0.1 <= best.d + 2 }.min { abs($0.0 - lastPos) < abs($1.0 - lastPos) }
                if let near { best = (near.0, near.1) }
            }
            return best
        }

        let threshold = 60
        let lo = max(0, lastPos - 2 * fh), hi = min(maxPos, lastPos + fh)
        if lo <= hi {
            let near = search(lo...hi)
            if near.d <= threshold { return near.pos }
        }
        let all = search(0...maxPos)
        return all.d <= threshold ? all.pos : nil
    }
}
