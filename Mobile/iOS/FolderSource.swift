import Foundation
import SwiftUI
import UserNotifications

/// Reads the Mac's snapshot from the "Focus Energy" folder in iCloud Drive.
/// The person picks that folder once; the app keeps a bookmark to it and re-reads the file while it is open.
final class FolderSource: ObservableObject {
    static let shared = FolderSource()

    @Published private(set) var snapshot: WidgetSnapshot? = SnapshotStore.load()
    @Published private(set) var folderName: String?
    @Published private(set) var problem: String?
    @Published private(set) var lastRead: Date?

    private let bookmarkKey = "folderBookmark"
    private var timer: Timer?
    private var lastData: Data?

    private init() {
        folderName = resolveFolder()?.lastPathComponent
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
        requestNotifications()
    }

    var isConnected: Bool { folderName != nil }

    /// Remembers the folder the person picked.
    func connect(to url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            folderName = url.lastPathComponent
            problem = nil
            refresh()
        } catch {
            problem = "Could not remember that folder: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
    }

    private func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
    }

    func refresh() {
        guard let folder = resolveFolder() else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let file = folder.appendingPathComponent(WidgetSnapshot.fileName)
        // Ask iCloud for the newest copy; the read below uses whatever has arrived.
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)

        var coordinationError: NSError?
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            data = try? Data(contentsOf: url)
        }
        guard let data else {
            problem = "No \(WidgetSnapshot.fileName) in \"\(folder.lastPathComponent)\" yet. On the Mac, turn on iCloud Drive storage in Focus Energy settings."
            return
        }
        lastRead = Date()
        problem = nil
        guard data != lastData else { return }
        lastData = data
        guard let fresh = SnapshotStore.save(data) else {
            problem = "The file in that folder could not be read."
            return
        }
        snapshot = fresh
        PhoneSession.shared.send(data)
        scheduleEndNotification(for: fresh)
    }

    // MARK: End-of-timer notification

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Plans a local notification for the moment the Mac's countdown ends.
    private func scheduleEndNotification(for snapshot: WidgetSnapshot) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["timer-end"])
        guard snapshot.runState == .running, let end = snapshot.endsAt, end > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = snapshot.phase == .focus ? "Focus session complete" : "Break is over"
        content.body = snapshot.phase == .focus ? "Extend it or take a break." : "Time to get back to focus."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "timer-end", content: content, trigger: trigger))
    }
}
