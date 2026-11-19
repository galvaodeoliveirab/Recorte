import CoreGraphics
import ImageIO
import Foundation

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let w = 600, pageH = 4000, fh = 500
// Page: real image tiles at varying offsets so it's not perfectly periodic.
let ctx = CGContext(data: nil, width: w, height: pageH, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
var y = 0, i = 0
while y < pageH { let h = 610 + (i % 3) * 57; ctx.draw(img, in: CGRect(x: -(i % 4) * 90, y: y, width: w + 400, height: h)); y += h; i += 1 }
let pagePx = Stitcher.pixels(ctx.makeImage()!, width: w, height: pageH)!
let rb = w * 4

func run(name: String, tops: [Int], header: Int, footer: Int) {
    func frame(_ top: Int) -> [UInt8] {
        var f = Array(pagePx[(top*rb)..<((top+fh)*rb)])
        for r in 0..<header { for x in 0..<w { let o = r*rb + x*4; f[o] = 20; f[o+1] = 60; f[o+2] = UInt8(r % 200); f[o+3] = 255 } }
        for r in (fh-footer)..<fh { for x in 0..<w { let o = r*rb + x*4; f[o] = 240; f[o+1] = UInt8((x/7) % 255); f[o+2] = 30; f[o+3] = 255 } }
        return f
    }
    var st = ScrollStitcher(width: w, frameHeight: fh)
    var log: [String] = []
    var maxTop = 0
    for t in tops { let r = st.add(frame(t)); log.append("\(t):\(r)"); if case .appended = r {}; maxTop = max(maxTop, t) }
    let out = st.output
    // Expected: header once (from first frame), page content, footer once.
    let f0 = frame(0)
    var exp = Array(f0[0..<(header*rb)])
    exp += pagePx[(header*rb)..<((maxTop + fh - footer)*rb)]
    let last = frame(tops.last!)
    exp += last[((fh-footer)*rb)..<(fh*rb)]
    let ok = out.data == exp
    print("\(ok ? "OK  " : "FAIL") \(name): height \(out.height) (expected \(exp.count/rb))")
    if !ok { print("   ", log.joined(separator: " ")) }
}

// Smooth scroll down
run(name: "rolagem normal", tops: Array(stride(from: 0, through: 3400, by: 85)), header: 0, footer: 0)
// Up and down, with still frames
run(name: "sobe e desce", tops: [0,0,120,300,480,300,100,0,200,450,700,900,600,400,800,1100,1400,1400,1700,2000], header: 0, footer: 0)
// Too fast (jumps > one screen), then user goes back a little
run(name: "rápido demais + volta", tops: [0,200,400,1300,1500,900,700,800,1000,1200,1400,1600], header: 0, footer: 0)
// Sticky footer (cookie bar) like globo.com
run(name: "rodapé fixo (cookies)", tops: Array(stride(from: 0, through: 3000, by: 140)), header: 0, footer: 70)
// Sticky header + footer, plus up/down
run(name: "cabeçalho + rodapé + sobe/desce", tops: [0,150,300,450,300,150,300,600,900,750,1050,1350,1650,1950,2250], header: 60, footer: 70)
// Jump too far, then user scrolls back a bit and continues
run(name: "cabeçalho + rodapé + perdido e recupera", tops: [0,200,400,1200,1400,700,600,800,1000,1200,1400], header: 60, footer: 70)
