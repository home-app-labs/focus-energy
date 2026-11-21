import Foundation
import WidgetKit

/// The latest snapshot from the Mac, kept in the app group so the app and its widgets read the same file.
enum SnapshotStore {
    /// Must match the App Group in the entitlements of the app and of its widget.
    static let group = "group.dev.focusplus.shared"

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Stores new snapshot data and redraws the widgets. Returns the decoded snapshot, or nil if the data is not one.
    @discardableResult
    static func save(_ data: Data) -> WidgetSnapshot? {
        guard let snapshot = try? WidgetSnapshot.decoder.decode(WidgetSnapshot.self, from: data) else { return nil }
        if let url { try? data.write(to: url, options: .atomic) }
        WidgetCenter.shared.reloadAllTimelines()
        return snapshot
    }
}

/// Timeline shared by the phone and watch widgets: one entry per minute the Mac projected,
/// plus one at the moment the countdown ends.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// False when no snapshot has arrived yet and sample data is shown.
    var isLive = true
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder, isLive: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = SnapshotStore.load()
        completion(SnapshotEntry(date: Date(), snapshot: stored ?? .placeholder, isLive: stored != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        guard let snapshot = SnapshotStore.load() else {
            completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: .placeholder, isLive: false)],
                                policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        var dates = [now] + snapshot.points.map(\.date).filter { $0 > now }
        if snapshot.runState == .running, let end = snapshot.endsAt, end > now { dates.append(end) }
        let entries = Array(Set(dates)).sorted().prefix(120).map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: Array(entries), policy: .after(now.addingTimeInterval(30 * 60))))
    }
}
