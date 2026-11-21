import WidgetKit
import SwiftUI
import WidgetUI

struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct FocusProvider: TimelineProvider {
    /// The app keeps its data in the real home folder; the sandboxed widget is allowed to read just that folder.
    static func loadSnapshot() -> WidgetSnapshot? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir.map({ String(cString: $0) }) else { return nil }
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/FocusPlus/\(WidgetSnapshot.fileName)")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: Date(), snapshot: Self.loadSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date()
        guard let snapshot = Self.loadSnapshot() else {
            completion(Timeline(entries: [FocusEntry(date: now, snapshot: .placeholder)],
                                policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        // One entry per projected minute, plus one at the moment the countdown ends.
        var dates = [now] + snapshot.points.map(\.date).filter { $0 > now }
        if snapshot.runState == .running, let end = snapshot.endsAt, end > now { dates.append(end) }
        // An entry just after midnight, so the day starts from zero even if the app writes nothing new.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
        dates.append(midnight.addingTimeInterval(1))
        let entries = Array(Set(dates)).sorted().map { FocusEntry(date: $0, snapshot: snapshot) }
        // The app asks for a reload whenever something changes, but the system may ignore that when the
        // widget has used up its daily reload allowance. Reading the file again on a schedule heals that.
        let waiting = snapshot.runState == .finished || snapshot.runState == .paused
        let next = now.addingTimeInterval(waiting ? 10 * 60 : 30 * 60)
        completion(Timeline(entries: entries, policy: .after(min(midnight.addingTimeInterval(5), next))))
    }
}

struct FocusWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    var body: some View {
        FocusWidgetView(snapshot: entry.snapshot, date: entry.date,
                        layout: family == .systemSmall ? .small : family == .systemMedium ? .medium : .large)
            .containerBackground(focusWidgetBackground, for: .widget)
    }
}

@main
struct FocusPlusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "local.focusplus.timer", provider: FocusProvider()) { entry in
            FocusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Focus Energy")
        .description("Timer, daily goal, energy and the week.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
