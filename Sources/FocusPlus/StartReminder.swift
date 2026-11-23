import AppKit
import Combine

/// Decides when to say "you are working without a timer". Kept free of system calls so it can be tested.
struct StartReminderLogic {
    /// How long someone has to be active without a timer before the first reminder.
    var threshold: TimeInterval
    /// How long to wait before reminding again.
    var repeatEvery: TimeInterval = 15 * 60
    /// Input within this many seconds counts as "at the computer right now".
    var activeWithin: TimeInterval = 60
    /// No input for this long means the person walked away, and the count starts over.
    var awayAfter: TimeInterval = 5 * 60

    private(set) var activeSince: Date?
    private(set) var lastReminder: Date?

    init(threshold: TimeInterval) { self.threshold = threshold }

    /// Call every few seconds. Returns the minutes worked without a timer when a reminder is due, otherwise nil.
    mutating func step(now: Date, secondsSinceInput: TimeInterval, timerIdle: Bool, allowed: Bool) -> Int? {
        guard timerIdle, allowed else {
            activeSince = nil
            lastReminder = nil
            return nil
        }
        if secondsSinceInput >= awayAfter {
            activeSince = nil
            return nil
        }
        if activeSince == nil {
            guard secondsSinceInput < activeWithin else { return nil }
            activeSince = now.addingTimeInterval(-secondsSinceInput)
        }
        guard let activeSince else { return nil }
        let worked = now.timeIntervalSince(activeSince)
        guard worked >= threshold else { return nil }
        if let lastReminder, now.timeIntervalSince(lastReminder) < repeatEvery { return nil }
        lastReminder = now
        return Int(worked / 60)
    }
}

/// Watches for activity at the computer while no timer is running and nudges to start one.
final class StartReminder {
    static let shared = StartReminder()

    private var logic = StartReminderLogic(threshold: 600)
    private var subscription: AnyCancellable?

    func start(engine: TimerEngine = .shared, settings: AppSettings = .shared) {
        subscription = Timer.publish(every: 20, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.check(engine: engine, settings: settings)
        }
    }

    private func check(engine: TimerEngine, settings: AppSettings) {
        logic.threshold = TimeInterval(max(1, settings.remindAfterMinutes) * 60)
        // Past the daily goal the evening is yours: no reminders.
        let allowed = settings.remindToStart && !settings.currentMode.isDayOff && engine.todayCoins < settings.dailyGoal
        guard let minutes = logic.step(now: Date(), secondsSinceInput: ActivityLog.secondsSinceInput,
                                       timerIdle: engine.phase == .idle, allowed: allowed) else { return }
        Notifier.shared.remindToStart(activeMinutes: minutes, focusMinutes: settings.focusMinutes)
    }
}
