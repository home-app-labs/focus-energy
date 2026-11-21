import Foundation

enum Format {
    /// "24:13", or "1:04:13" from one hour up.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "45 min", "1 h", "1 h 15 min".
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    /// Compact form for tight spots: "45m", "6h", "4h 10m".
    static func short(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
