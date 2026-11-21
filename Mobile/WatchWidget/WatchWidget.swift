import WidgetKit
import SwiftUI

struct WatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let status = CompactStatus(entry.snapshot, at: entry.date)
        switch family {
        case .accessoryRectangular:
            RectangularStatusView(status: status).containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Label { Text("\(status.title) · \(status.focusLine)") } icon: { Image(systemName: status.symbol) }
                .containerBackground(.clear, for: .widget)
        case .accessoryCorner:
            Image(systemName: status.symbol)
                .font(.title3)
                .widgetLabel {
                    Gauge(value: status.fraction) { Text(status.title) }.tint(status.tint)
                }
                .containerBackground(.clear, for: .widget)
        default:
            CircularStatusView(status: status).containerBackground(.clear, for: .widget)
        }
    }
}

@main
struct FocusPlusWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.focusplus.watch.timer", provider: SnapshotProvider()) { entry in
            WatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus Energy")
        .description("Timer and daily focus progress.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
