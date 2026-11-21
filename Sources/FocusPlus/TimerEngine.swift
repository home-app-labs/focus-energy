import Foundation
import Combine

/// The timer state machine.
///
/// A focus session is one continuous piece of work. When its countdown ends the session stays open
/// and waits for a decision: extend it (+5 … +60 minutes), take a break, start a fresh session, or stop.
/// Extending keeps the same session, so 30 + 15 is recorded as a single 45 minute session.
final class TimerEngine: ObservableObject {
    enum Phase: Equatable {
        case idle, focus, shortBreak, longBreak

        var isBreak: Bool { self == .shortBreak || self == .longBreak }

        var title: String {
            switch self {
            case .idle: return "Ready"
            case .focus: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            }
        }
    }

    enum RunState: Equatable {
        case idle, running, paused
        /// Countdown reached zero and the app is waiting for the user's choice.
        case finished
    }

    static let shared = TimerEngine(settings: .shared, ledger: .shared)

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var runState: RunState = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var plannedSeconds: TimeInterval = 0
    @Published private(set) var session: ActiveSession?
    /// What the running break is called, taken from the break presets ("Coffee", "Walk", "Lunch").
    @Published private(set) var breakName = "Break"
    @Published private(set) var sessionsSinceLongBreak = 0
    @Published private(set) var today: Date = Calendar.current.startOfDay(for: Date())

    /// Called once when a countdown reaches zero.
    var onFinish: ((Phase) -> Void)?

    let settings: AppSettings
    let ledger: Ledger

    private var endDate: Date?
    private var breakStart: Date?
    private var ticker: Timer?
    private var lastSavedMinute = -1
    private let now: () -> Date

    init(settings: AppSettings, ledger: Ledger, now: @escaping () -> Date = Date.init, startTicker: Bool = true) {
        self.settings = settings
        self.ledger = ledger
        self.now = now
        if !resumeSavedSession() { ledger.recoverActive() }
        if startTicker {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    /// Picks a running session back up after a restart. Returns false when there is nothing to resume.
    private func resumeSavedSession() -> Bool {
        guard let saved = ledger.loadActive(), let end = saved.endsAt, let planned = saved.plannedSeconds,
              end > now() else { return false }
        phase = .focus
        session = saved
        plannedSeconds = planned
        endDate = end
        remaining = end.timeIntervalSince(now())
        runState = .running
        syncSession()
        return true
    }

    // MARK: Derived values

    /// Title for the current state: the break's own name while resting.
    var phaseTitle: String { phase.isBreak ? breakName : phase.title }

    /// Coins earned so far by the session that is still open.
    var liveCoins: Int { session?.earnedMinutes ?? 0 }

    var todayCoins: Int { ledger.coins(on: now()) + liveCoins }

    var todaySessions: Int { ledger.entries(on: now()).count + (session == nil ? 0 : 1) }

    /// Whole minutes rested so far in the break that is running.
    var liveBreakMinutes: Int {
        phase.isBreak ? Int((max(0, plannedSeconds - remaining) + 0.5) / 60) : 0
    }

    var todayBreakMinutes: Int { ledger.breakMinutes(on: now()) + liveBreakMinutes }

    /// Energy and rest picture for today.
    var wellbeing: Wellbeing {
        let stretch = phase.isBreak ? 0 : ledger.focusMinutesSinceLastBreak(on: now()) + liveCoins
        return Wellbeing(focusMinutes: todayCoins, breakMinutes: todayBreakMinutes,
                         goal: settings.dailyGoal, stretch: stretch, restGoal: settings.dailyRest)
    }

    var progress: Double {
        guard plannedSeconds > 0 else { return 0 }
        return min(1, max(0, (plannedSeconds - remaining) / plannedSeconds))
    }

    /// True when the next break should be the long one.
    var nextBreakIsLong: Bool {
        let completed = sessionsSinceLongBreak + (sessionCountsAsCompleted ? 1 : 0)
        return completed >= settings.longBreakEvery
    }

    var nextBreakMinutes: Int {
        nextBreakIsLong ? settings.longBreakMinutes : settings.shortBreakMinutes
    }

    private var sessionCountsAsCompleted: Bool {
        guard let session else { return false }
        return session.focusedSeconds >= Double(session.baseMinutes * 60) - 1
    }

    // MARK: Commands

    /// Starts a focus session of the chosen length, or the default one.
    /// `demoSeconds` shortens the countdown for development; real sessions leave it nil.
    func startFocus(minutes chosen: Int? = nil, demoSeconds: Double? = nil) {
        finalizeBreak()
        finalizeSession()
        let minutes = max(1, chosen ?? settings.focusMinutes)
        let start = now()
        phase = .focus
        session = ActiveSession(start: start, baseMinutes: minutes, lastUpdate: start)
        begin(seconds: demoSeconds ?? Double(minutes * 60))
        persistActive(force: true)
    }

    /// Adds minutes to whatever is running. During focus this extends the same session.
    func extend(minutes: Int) {
        guard minutes > 0, phase != .idle else { return }
        let extra = Double(minutes * 60)
        plannedSeconds += extra
        if phase == .focus { session?.extensions.append(minutes) }
        switch runState {
        case .running:
            endDate = (endDate ?? now()).addingTimeInterval(extra)
            remaining += extra
        case .paused:
            remaining += extra
        case .finished:
            remaining = extra
            endDate = now().addingTimeInterval(extra)
            runState = .running
        case .idle:
            break
        }
        persistActive(force: true)
    }

    func pause() {
        guard runState == .running else { return }
        refreshRemaining()
        endDate = nil
        runState = .paused
        persistActive(force: true)
    }

    func resume() {
        guard runState == .paused else { return }
        endDate = now().addingTimeInterval(remaining)
        runState = .running
    }

    /// Closes the focus session (crediting its coins) and starts a break.
    /// Without `minutes` the configured short or long break is used.
    func startBreak(minutes: Int? = nil) {
        let long = nextBreakIsLong
        finalizeBreak()
        finalizeSession()
        if long { sessionsSinceLongBreak = 0 }
        phase = long ? .longBreak : .shortBreak
        breakStart = now()
        let length = minutes ?? (long ? settings.longBreakMinutes : settings.shortBreakMinutes)
        breakName = settings.breakPreset(minutes: length)?.name ?? "Break"
        begin(seconds: Double(max(1, length) * 60))
    }

    /// Counts the running timer as done in full and ends it. For when the time was really spent
    /// but the timer was started late, for example a lunch that was never switched on.
    func completeNow() {
        guard phase != .idle else { return }
        let planned = plannedSeconds
        let end = now()
        if phase == .focus {
            session?.focusedSeconds = planned
            session?.start = end.addingTimeInterval(-planned)
            session?.lastUpdate = end
            remaining = 0
        } else {
            remaining = 0
            breakStart = end.addingTimeInterval(-planned)
        }
        runState = .finished
        endDate = nil
        stop()
    }

    /// Records focus that already happened, ending now, without running a timer.
    func logPastFocus(minutes: Int) {
        guard minutes > 0 else { return }
        let end = now()
        ledger.add(FocusEntry(start: end.addingTimeInterval(Double(-minutes * 60)), end: end,
                              minutes: minutes, baseMinutes: minutes, extensions: []))
    }

    /// Records a break that already happened, ending now, without running a timer.
    func logPastBreak(minutes: Int) {
        guard minutes > 0 else { return }
        ledger.addBreak(BreakEntry(start: now().addingTimeInterval(Double(-minutes * 60)), minutes: minutes,
                                   name: settings.breakPreset(minutes: minutes)?.name))
    }

    /// Ends whatever is running. Focused minutes so far are still credited.
    func stop() {
        finalizeBreak()
        finalizeSession()
        phase = .idle
        runState = .idle
        remaining = 0
        plannedSeconds = 0
        endDate = nil
    }

    /// Call before the app quits so an open session is written to the ledger.
    func prepareForQuit() {
        if runState == .running { refreshRemaining() }
        finalizeBreak()
        finalizeSession()
    }

    // MARK: Internals

    private func begin(seconds: Double) {
        plannedSeconds = seconds
        remaining = seconds
        endDate = now().addingTimeInterval(seconds)
        runState = .running
    }

    private func refreshRemaining() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSince(now()))
        syncSession()
    }

    private func syncSession() {
        guard phase == .focus, session != nil else { return }
        session?.focusedSeconds = max(0, plannedSeconds - remaining)
        session?.lastUpdate = now()
    }

    func tick() {
        let day = Calendar.current.startOfDay(for: now())
        if day != today { today = day }

        guard runState == .running, let endDate else { return }
        let left = max(0, endDate.timeIntervalSince(now()))
        // Publish only when the visible second changes, to keep redraws cheap.
        if left <= 0 || ceil(left) != ceil(remaining) {
            remaining = left
            syncSession()
            persistActive(force: false)
        }
        if left <= 0 {
            self.endDate = nil
            runState = .finished
            persistActive(force: true)
            onFinish?(phase)
        }
    }

    private func persistActive(force: Bool) {
        session?.endsAt = runState == .running ? endDate : nil
        session?.plannedSeconds = plannedSeconds
        guard let session else { return }
        if force || session.earnedMinutes != lastSavedMinute {
            lastSavedMinute = session.earnedMinutes
            ledger.saveActive(session)
        }
    }

    /// Writes the break that is ending to the ledger. Time spent ignoring the "break is over" prompt is not counted.
    private func finalizeBreak() {
        guard phase.isBreak else { return }
        if runState == .running { refreshRemaining() }
        let rested = liveBreakMinutes
        if rested > 0 { ledger.addBreak(BreakEntry(start: breakStart ?? now(), minutes: rested, name: breakName)) }
        breakStart = nil
        phase = .idle
    }

    private func finalizeSession() {
        guard let finished = session else { return }
        if sessionCountsAsCompleted { sessionsSinceLongBreak += 1 }
        if finished.earnedMinutes > 0 {
            ledger.add(FocusEntry(id: finished.id, start: finished.start, end: finished.lastUpdate,
                                  minutes: finished.earnedMinutes, baseMinutes: finished.baseMinutes,
                                  extensions: finished.extensions))
        }
        ledger.clearActive()
        session = nil
        lastSavedMinute = -1
    }
}
