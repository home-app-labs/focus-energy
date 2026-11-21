import AppKit
import UserNotifications

/// Sounds and system notifications. Notification buttons act on the timer directly.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let focusCategory = "FOCUS_DONE"
    private let breakCategory = "BREAK_DONE"
    private let extendPrefix = "EXTEND_"

    /// Notifications need a real app bundle; the bare binary from `swift run` has none.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }
    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        guard available else { return }
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("FocusPlus: notification permission: \(error.localizedDescription)") }
        }
    }

    func registerCategories() {
        guard available else { return }
        let settings = AppSettings.shared
        // The system shows only a few buttons, so offer the first three extensions plus the break.
        var actions = settings.extensionOptions.prefix(3).map {
            UNNotificationAction(identifier: "\(extendPrefix)\($0)", title: "+\($0) min", options: [])
        }
        actions.append(UNNotificationAction(identifier: "BREAK", title: "Take a break", options: []))
        let focus = UNNotificationCategory(identifier: focusCategory, actions: actions, intentIdentifiers: [])
        let breakDone = UNNotificationCategory(identifier: breakCategory, actions: [
            UNNotificationAction(identifier: "FOCUS", title: "Start focus", options: []),
        ], intentIdentifiers: [])
        center.setNotificationCategories([focus, breakDone])
    }

    func announce(finished phase: TimerEngine.Phase, engine: TimerEngine) {
        let settings = AppSettings.shared
        if settings.playSounds {
            NSSound(named: phase == .focus ? "Glass" : "Hero")?.play()
        }
        guard available, settings.showNotifications else { return }

        let content = UNMutableNotificationContent()
        if phase == .focus {
            let minutes = engine.session?.plannedMinutes ?? settings.focusMinutes
            content.title = "Focus session complete"
            content.body = "\(Format.duration(minutes: minutes)) done. Today: \(Format.duration(minutes: engine.todayCoins)) of focus. Extend, or take a break?"
            content.categoryIdentifier = focusCategory
        } else {
            content.title = "Break is over"
            content.body = "Ready for the next \(Format.duration(minutes: settings.focusMinutes)) of focus?"
            content.categoryIdentifier = breakCategory
        }
        center.removeAllDeliveredNotifications()
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func clear() {
        guard available else { return }
        center.removeAllDeliveredNotifications()
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            let engine = TimerEngine.shared
            if action.hasPrefix(self.extendPrefix), let minutes = Int(action.dropFirst(self.extendPrefix.count)) {
                if engine.phase == .focus { engine.extend(minutes: minutes) }
            } else if action == "BREAK" {
                if engine.phase == .focus { engine.startBreak() }
            } else if action == "FOCUS" {
                if engine.phase != .focus { engine.startFocus() }
            } else if action == UNNotificationDefaultActionIdentifier, engine.runState == .finished {
                AppWindows.showChoice()
            }
            completionHandler()
        }
    }
}
