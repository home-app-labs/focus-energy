import AppKit
import UserNotifications

/// Sounds and system notifications. Notification buttons act on the timer directly.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let focusCategory = "FOCUS_DONE"
    private let breakCategory = "BREAK_DONE"
    private let nudgeCategory = "START_NUDGE"
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
        let nudge = UNNotificationCategory(identifier: nudgeCategory, actions: [
            UNNotificationAction(identifier: "FOCUS", title: "Start \(settings.focusMinutes) min focus", options: []),
            UNNotificationAction(identifier: "LOG_PAST", title: "Start, and count the time so far", options: []),
            UNNotificationAction(identifier: "NOT_NOW", title: "Not now", options: []),
        ], intentIdentifiers: [])
        center.setNotificationCategories([focus, breakDone, nudge])
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

    /// "You are working without a timer."
    func remindToStart(activeMinutes: Int, focusMinutes: Int) {
        guard available else { return }
        if AppSettings.shared.playSounds { NSSound(named: "Tink")?.play() }
        registerCategories()
        let content = UNMutableNotificationContent()
        content.title = "Working without a timer?"
        content.body = "You have been at it for \(Format.duration(minutes: activeMinutes)). Start a focus session so that it counts."
        content.categoryIdentifier = nudgeCategory
        content.userInfo = ["activeMinutes": activeMinutes]
        center.add(UNNotificationRequest(identifier: "start-nudge", content: content, trigger: nil))
    }

    /// A plain notice without buttons.
    func note(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
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
            } else if action == "LOG_PAST" {
                // Count the untimed minutes as a session of their own, then carry on with a timer.
                let minutes = response.notification.request.content.userInfo["activeMinutes"] as? Int ?? 0
                if engine.phase == .idle {
                    if minutes > 0 { engine.logPastFocus(minutes: minutes) }
                    engine.startFocus()
                }
            } else if action == UNNotificationDefaultActionIdentifier,
                      response.notification.request.content.categoryIdentifier == self.nudgeCategory {
                AppWindows.showMain()
            } else if action == UNNotificationDefaultActionIdentifier, engine.runState == .finished {
                AppWindows.showChoice()
            }
            completionHandler()
        }
    }
}
