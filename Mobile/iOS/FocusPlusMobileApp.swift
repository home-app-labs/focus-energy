import SwiftUI
import BackgroundTasks

@main
struct FocusPlusMobileApp: App {
    @StateObject private var source = FolderSource.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneSession.shared.start()
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(source: source)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { source.refresh() }
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

/// Asks iOS for occasional background time to re-read the snapshot. iOS decides when, so this is best effort.
enum BackgroundRefresh {
    static let identifier = "dev.focusplus.mobile.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            DispatchQueue.main.async {
                FolderSource.shared.refresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
