import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    // macOS icon grid: 824pt body centered in 1024 canvas
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient (indigo -> violet -> pink)
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 0.16, green: 0.20, blue: 0.62, alpha: 1).cgColor,
        NSColor(srgbRed: 0.42, green: 0.27, blue: 0.86, alpha: 1).cgColor,
        NSColor(srgbRed: 0.93, green: 0.39, blue: 0.62, alpha: 1).cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 150, y: 120), end: CGPoint(x: 880, y: 920), options: [])
    // Soft top glow
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 380, y: 860), startRadius: 0, endCenter: CGPoint(x: 380, y: 860), endRadius: 560, options: [])
    ctx.restoreGState()

    // Inner edge highlight
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: radius - 2, cornerHeight: radius - 2, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor); ctx.setLineWidth(4); ctx.strokePath()
    ctx.restoreGState()

    // "Photo" card being captured
    let card = CGRect(x: 330, y: 330, width: 364, height: 364)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(cardPath); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(cardPath); ctx.clip()
    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        NSColor(srgbRed: 0.55, green: 0.83, blue: 1.0, alpha: 1).cgColor,
        NSColor(srgbRed: 1.0, green: 0.86, blue: 0.70, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: card.maxY), end: CGPoint(x: 0, y: card.minY), options: [])
    // sun
    ctx.setFillColor(NSColor(srgbRed: 1.0, green: 0.78, blue: 0.25, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: 548, y: 560, width: 84, height: 84))
    // mountains
    func mountain(_ pts: [CGPoint], _ c: NSColor) {
        ctx.beginPath(); ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.closePath()
        ctx.setFillColor(c.cgColor); ctx.fillPath()
    }
    mountain([CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 430), CGPoint(x: 450, y: 560), CGPoint(x: 600, y: 410), CGPoint(x: 720, y: 300)],
             NSColor(srgbRed: 0.33, green: 0.38, blue: 0.80, alpha: 1))
    mountain([CGPoint(x: 420, y: 300), CGPoint(x: 590, y: 480), CGPoint(x: 720, y: 380), CGPoint(x: 720, y: 300)],
             NSColor(srgbRed: 0.20, green: 0.24, blue: 0.62, alpha: 1))
    ctx.restoreGState()

    // Viewfinder corner brackets
    let r = CGRect(x: 230, y: 230, width: 564, height: 564)
    let L: CGFloat = 150, cr: CGFloat = 70
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(46); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    for (cx, cy, sx, sy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: cy + sy * L))
        p.addArc(tangent1End: CGPoint(x: cx, y: cy), tangent2End: CGPoint(x: cx + sx * L, y: cy), radius: cr)
        p.addLine(to: CGPoint(x: cx + sx * L, y: cy))
        ctx.addPath(p)
    }
    ctx.strokePath()
    ctx.restoreGState()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
