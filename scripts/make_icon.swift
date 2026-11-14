import AppKit
import CoreGraphics

// Draws the Subah icon: a soft dawn sky with a low sun over a quiet horizon.
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let s = CGFloat(size)
// macOS icon squircle with standard margin
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: c(0x000000, 0.28))
ctx.addPath(path); ctx.setFillColor(c(0xF3C9C9)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
let sky = CGGradient(colorsSpace: cs, colors: [c(0x9C93CF), c(0xE9B5C4), c(0xFBD9B8), c(0xFFEBCF)] as CFArray, locations: [0, 0.45, 0.75, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s - inset), end: CGPoint(x: 0, y: inset), options: [])
// sun glow
let horizon = inset + (s - inset * 2) * 0.34
let glow = CGGradient(colorsSpace: cs, colors: [c(0xFFF3D6, 0.95), c(0xFFE0A8, 0.35), c(0xFFE0A8, 0)] as CFArray, locations: [0, 0.35, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: horizon), startRadius: 0, endCenter: CGPoint(x: s / 2, y: horizon), endRadius: 400, options: [])
// sun disc
ctx.setFillColor(c(0xFFF6E2))
ctx.fillEllipse(in: CGRect(x: s / 2 - 150, y: horizon - 150, width: 300, height: 300))
// far hills
func hills(_ base: CGFloat, _ amp: CGFloat, _ color: CGColor, _ phase: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addLine(to: CGPoint(x: 0, y: base))
    var x: CGFloat = 0
    while x <= s {
        p.addLine(to: CGPoint(x: x, y: base + sin((x / s) * .pi * 2 + phase) * amp + sin((x / s) * .pi * 5 + phase) * amp * 0.25))
        x += 8
    }
    p.addLine(to: CGPoint(x: s, y: 0)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}
hills(horizon - 10, 26, c(0xB79BC4, 0.85), 0.6)
hills(horizon - 62, 30, c(0x8F79B0, 0.95), 2.4)
hills(horizon - 120, 22, c(0x6B5B95), 4.0)
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
