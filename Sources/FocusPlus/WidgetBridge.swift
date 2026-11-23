import Foundation
import Combine
import WidgetKit
import WidgetUI

/// Publishes the app's state for the desktop widget: writes `widget-state.json` next to the ledger
/// and asks the system to redraw the widget whenever something meaningful changes.
final class WidgetBridge {
    static let shared = WidgetBridge()

    private var subscriptions = Set<AnyCancellable>()
    private var lastWritten: WidgetSnapshot?

    func start(engine: TimerEngine = .shared, settings: AppSettings = .shared, ledger: Ledger = .shared) {
        let triggers: [AnyPublisher<Void, Never>] = [
            engine.$runState.map { _ in }.eraseToAnyPublisher(),
            engine.$phase.map { _ in }.eraseToAnyPublisher(),
            engine.$plannedSeconds.map { _ in }.eraseToAnyPublisher(),
            engine.$today.map { _ in }.eraseToAnyPublisher(),
            ledger.$entries.map { _ in }.eraseToAnyPublisher(),
            ledger.$breaks.map { _ in }.eraseToAnyPublisher(),
            ledger.$usesICloud.map { _ in }.eraseToAnyPublisher(),
            settings.$dailyGoal.map { _ in }.eraseToAnyPublisher(),
            settings.$dailyRest.map { _ in }.eraseToAnyPublisher(),
            settings.$currentMode.map { _ in }.eraseToAnyPublisher(),
            settings.$focusMinutes.map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.publish(engine: engine, settings: settings, ledger: ledger) }
            .store(in: &subscriptions)
    }

    func publish(engine: TimerEngine, settings: AppSettings, ledger: Ledger) {
        let snapshot = Self.makeSnapshot(engine: engine, settings: settings, ledger: ledger, now: Date())
        var comparable = snapshot
        comparable.points = Array(comparable.points.prefix(1))
        if var previous = lastWritten {
            previous.points = Array(previous.points.prefix(1))
            if previous == comparable, snapshot.runState != .running { return }
        }
        lastWritten = snapshot
        let url = ledger.directoryURL.appendingPathComponent(WidgetSnapshot.fileName)
        try? WidgetSnapshot.encoder.encode(snapshot).write(to: url, options: .atomic)
        if ledger.usesICloud {
            // The iPhone app reads this copy from the shared iCloud Drive folder.
            let shared = ledger.dataDirectoryURL.appendingPathComponent(WidgetSnapshot.fileName)
            try? WidgetSnapshot.encoder.encode(snapshot).write(to: shared, options: .atomic)
        }
        if Bundle.main.bundleIdentifier != nil { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Builds the snapshot, projecting the day's numbers minute by minute until the countdown ends.
    static func makeSnapshot(engine: TimerEngine, settings: AppSettings, ledger: Ledger, now: Date) -> WidgetSnapshot {
        let base = engine.wellbeing
        let running = engine.runState == .running
        let inFocus = engine.phase == .focus
        let inBreak = engine.phase.isBreak

        func point(at date: Date, extra: Int) -> WidgetSnapshot.Point {
            var w = Wellbeing(focusMinutes: base.focusMinutes + (inFocus ? extra : 0),
                              breakMinutes: base.breakMinutes + (inBreak ? extra : 0),
                              goal: base.goal, stretch: base.stretch + (inFocus ? extra : 0),
                              restGoal: base.restGoal, sessionMinutes: base.sessionMinutes,
                              longestBreak: base.longestBreak + (inBreak ? extra : 0))
            w.dayOff = base.dayOff
            return .init(date: date, coins: w.focusMinutes, breakMinutes: w.breakMinutes,
                         recommendedRest: w.recommendedRest, energy: w.energy, moodEmoji: w.mood.emoji,
                         moodTitle: w.mood.title, advice: "\(w.adviceIcon) \(w.advice)")
        }

        var points = [point(at: now, extra: 0)]
        if running, engine.phase != .idle {
            let elapsed = max(0, engine.plannedSeconds - engine.remaining)
            // Seconds until the next whole minute is earned.
            var offset = 60 - elapsed.truncatingRemainder(dividingBy: 60)
            var extra = 1
            while offset <= engine.remaining + 0.5, extra <= 600 {
                points.append(point(at: now.addingTimeInterval(offset), extra: extra))
                offset += 60
                extra += 1
            }
        }

        // FOCUSPLUS_WEEK=-1 shows last week, for screenshots early in a week.
        let weekShift = min(0, Int(ProcessInfo.processInfo.environment["FOCUSPLUS_WEEK"] ?? "") ?? 0)
        let weekDate = Calendar.current.date(byAdding: .day, value: 7 * weekShift, to: now) ?? now
        let week = ledger.week(containing: weekDate).map { day -> WidgetSnapshot.Day in
            let isToday = Calendar.current.isDate(day.day, inSameDayAs: now)
            let coins = isToday ? base.focusMinutes : day.coins
            return .init(day: day.day, label: day.day.formatted(.dateTime.weekday(.abbreviated)), coins: coins,
                         emoji: DayVerdict.of(coins: coins, goal: settings.dailyGoal).emoji,
                         isToday: isToday, isFuture: day.day > now)
        }

        let phase: WidgetSnapshot.Phase = inFocus ? .focus : inBreak ? .rest : .idle
        let state: WidgetSnapshot.RunState
        switch engine.runState {
        case .idle: state = .idle
        case .running: state = .running
        case .paused: state = .paused
        case .finished: state = .finished
        }
        return WidgetSnapshot(phase: phase, runState: state,
                              endsAt: running ? now.addingTimeInterval(engine.remaining) : nil,
                              plannedSeconds: engine.plannedSeconds, remainingSeconds: engine.remaining,
                              goal: settings.dailyGoal, defaultFocusMinutes: settings.focusMinutes,
                              points: points, week: week)
    }
}
