// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
// A coffee cup inside a timer ring: three quarters of focus, one quarter of rest.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.27, green: 0.22, blue: 0.56, alpha: 1),
                    NSColor(red: 0.10, green: 0.08, blue: 0.24, alpha: 1)])!.draw(in: background, angle: -90)

let center = NSPoint(x: 512, y: 512)
let radius = 292.0
let width = 54.0

func arc(from start: Double, to end: Double, color: NSColor) {
    // Angles in degrees clockwise from the top.
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: 90 - start, endAngle: 90 - end, clockwise: true)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
track.lineWidth = width
NSColor(white: 1, alpha: 0.10).setStroke()
track.stroke()

arc(from: 8, to: 256, color: NSColor(red: 0.56, green: 0.50, blue: 1.00, alpha: 1))   // focus
arc(from: 284, to: 344, color: NSColor(red: 0.18, green: 0.83, blue: 0.68, alpha: 1)) // rest

// The cup
let names = ["cup.and.heat.waves.fill", "cup.and.saucer.fill"]
let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
    .applying(.init(paletteColors: [NSColor(red: 1.00, green: 0.80, blue: 0.36, alpha: 1)]))
if let symbol = names.lazy.compactMap({ NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
    .withSymbolConfiguration(config) }).first {
    let target = 390.0
    let scale = target / max(symbol.size.width, symbol.size.height)
    let w = symbol.size.width * scale, h = symbol.size.height * scale
    symbol.draw(in: NSRect(x: center.x - w / 2, y: center.y - h / 2 + 6, width: w, height: h))
}

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
