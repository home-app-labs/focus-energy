import WidgetKit
import SwiftUI

struct MobileWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularStatusView(status: CompactStatus(entry.snapshot, at: entry.date))
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            RectangularStatusView(status: CompactStatus(entry.snapshot, at: entry.date))
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            let status = CompactStatus(entry.snapshot, at: entry.date)
            Label { Text("\(status.title) · \(status.focusLine)") } icon: { Image(systemName: status.symbol) }
                .containerBackground(.clear, for: .widget)
        default:
            FocusWidgetView(snapshot: entry.snapshot, date: entry.date,
                            layout: family == .systemSmall ? .small : family == .systemMedium ? .medium : .large)
                .containerBackground(focusWidgetBackground, for: .widget)
        }
    }
}

@main
struct FocusPlusMobileWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.focusplus.mobile.timer", provider: SnapshotProvider()) { entry in
            MobileWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus Energy")
        .description("The timer on your Mac, your focus for the day and your energy.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
