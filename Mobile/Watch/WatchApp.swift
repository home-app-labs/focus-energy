import SwiftUI
import WatchConnectivity

@main
struct FocusPlusWatchApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: session)
        }
    }
}

/// Receives snapshots from the iPhone and keeps the latest one for the app and its complications.
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()

    @Published private(set) var snapshot: WidgetSnapshot? = SnapshotStore.load()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func accept(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data, let fresh = SnapshotStore.save(data) else { return }
        DispatchQueue.main.async { self.snapshot = fresh }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        accept(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        accept(userInfo)
    }
}

struct WatchContentView: View {
    @ObservedObject var session: WatchSession

    var body: some View {
        if let snapshot = session.snapshot {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let status = CompactStatus(snapshot, at: context.date)
                ScrollView {
                    VStack(spacing: 8) {
                        FocusWidgetView(snapshot: snapshot, date: context.date, layout: .ring(132))
                        Text(status.point.moodTitle).font(.headline)
                        VStack(spacing: 2) {
                            Label(status.focusLine, systemImage: "bolt.fill")
                            Label(status.restLine, systemImage: "cup.and.saucer.fill")
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                        Text(status.point.advice).font(.caption2).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "timer").font(.title)
                Text("Open Focus Energy on your iPhone to connect.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
