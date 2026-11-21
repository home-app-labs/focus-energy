import AppKit

/// Draws the live timer into the Dock icon: a ring that empties as time runs out,
/// the minutes left in the middle and the full countdown underneath.
final class DockTimerView: NSView {
    private let engine = TimerEngine.shared

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // All coordinates below are for a 128 pt tile.
        let scale = bounds.width / 128
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        defer { context.restoreGState() }

        let finished = engine.runState == .finished
        let paused = engine.runState == .paused
        let tint: NSColor = engine.phase == .focus
            ? NSColor(red: 0.47, green: 0.40, blue: 1.00, alpha: 1)
            : NSColor(red: 0.18, green: 0.83, blue: 0.68, alpha: 1)

        // Tile background, shaped like a standard app icon.
        let tile = NSBezierPath(roundedRect: NSRect(x: 7, y: 7, width: 114, height: 114), xRadius: 26, yRadius: 26)
        NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.10, alpha: 1)])!.draw(in: tile, angle: -90)

        // Ring
        let center = NSPoint(x: 64, y: 73)
        let radius: CGFloat = 35
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 9
        NSColor(white: 1, alpha: 0.14).setStroke()
        track.stroke()

        let left = finished ? 1 : 1 - engine.progress
        if left > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - 360 * left, clockwise: true)
            arc.lineWidth = 9
            arc.lineCapStyle = .round
            (paused ? tint.withAlphaComponent(0.45) : tint).setStroke()
            arc.stroke()
        }

        // Minutes left, inside the ring
        let seconds = Int(ceil(max(0, engine.remaining)))
        let middle = finished ? "✓" : "\(seconds / 60)"
        let middleSize: CGFloat = middle.count >= 3 ? 25 : 34
        draw(middle, size: middleSize, weight: .bold, color: paused ? NSColor(white: 1, alpha: 0.55) : .white,
             centeredAt: NSPoint(x: center.x, y: center.y))

        // Countdown under the ring
        let bottom = finished ? (engine.phase == .focus ? "Done" : "Go") : (paused ? "II " : "") + Format.clock(engine.remaining)
        draw(bottom, size: bottom.count > 6 ? 15 : 19, weight: .semibold,
             color: finished ? tint : NSColor(white: 1, alpha: 0.92), centeredAt: NSPoint(x: 64, y: 21))
    }

    private func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centeredAt point: NSPoint) {
        var font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if let rounded = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: size) {
            font = f
        }
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let bounds = string.size()
        string.draw(at: NSPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
    }
}

enum DockIcon {
    private static let view = DockTimerView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    /// Shows the live timer while something is running, and the normal app icon otherwise.
    static func update() {
        let tile = NSApp.dockTile
        let active = TimerEngine.shared.phase != .idle && AppSettings.shared.showTimerInDock
        if active {
            if tile.contentView !== view { tile.contentView = view }
            tile.display()
        } else if tile.contentView != nil {
            tile.contentView = nil
            tile.display()
        }
    }

    /// Development aid: saves the current Dock tile drawing as a PNG.
    static func writePNG(to url: URL) {
        let big = DockTimerView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        guard let rep = big.bitmapImageRepForCachingDisplay(in: big.bounds) else { return }
        big.cacheDisplay(in: big.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
