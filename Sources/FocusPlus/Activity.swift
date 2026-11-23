import AppKit
import Combine
import SwiftUI

/// Turns "seconds since the last input", asked every few seconds, into time spent at the computer.
/// Kept free of system calls so it can be tested.
struct ActivityCounter {
    /// Gaps in input shorter than this are reading or thinking and still count.
    var awayAfter: TimeInterval = 5 * 60
    /// A poll that comes later than this means the Mac slept in between: that stretch is not counted.
    var longestStep: TimeInterval = 90

    private var lastPoll: Date?
    /// Seconds counted since the person last came back.
    private var run: TimeInterval = 0
    private var away = true

    /// Call every few seconds. Returns the seconds to add to the day's total.
    /// The value is negative once, when a gap turns out to be an absence and its start is given back.
    mutating func step(now: Date, secondsSinceInput: TimeInterval) -> TimeInterval {
        var elapsed = lastPoll.map { now.timeIntervalSince($0) } ?? 0
        if elapsed < 0 || elapsed > longestStep { elapsed = 0 }
        lastPoll = now
        if secondsSinceInput < awayAfter {
            if away { away = false; run = 0 }
            run += elapsed
            return elapsed
        }
        guard !away else { return 0 }
        away = true
        // The quiet minutes before this poll were counted as thinking time. They were the walk away.
        let giveBack = min(run, max(0, secondsSinceInput - elapsed))
        run = 0
        return -giveBack
    }
}

/// How long the person was at this Mac each day, judged only by whether there was any input.
/// It knows nothing about what was typed or in which app, and needs no permission.
/// The numbers stay on this Mac: two computers would otherwise overwrite each other.
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    /// Seconds at the Mac, by day ("2026-11-23").
    @Published private(set) var seconds: [String: Double] = [:]

    private var counter = ActivityCounter()
    private var subscription: AnyCancellable?
    private var unsaved = 0
    private let url: URL

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Seconds since the last key press, click or pointer move anywhere on this Mac.
    static var secondsSinceInput: TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    init(directory: URL = Ledger.shared.directoryURL) {
        url = directory.appendingPathComponent("activity.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            seconds = saved
        }
    }

    func start() {
        subscription = Timer.publish(every: 20, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.poll(now: Date(), secondsSinceInput: Self.secondsSinceInput)
        }
    }

    func poll(now: Date, secondsSinceInput: TimeInterval) {
        let change = counter.step(now: now, secondsSinceInput: secondsSinceInput)
        guard change != 0 else { return }
        let key = Self.dayKey.string(from: now)
        seconds[key] = max(0, (seconds[key] ?? 0) + change)
        unsaved += 1
        if unsaved >= 3 { save() }
    }

    func save() {
        unsaved = 0
        guard let data = try? JSONEncoder().encode(seconds) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Whole minutes at the Mac on that day.
    func minutes(on day: Date) -> Int { Int((seconds[Self.dayKey.string(from: day)] ?? 0) / 60) }
}

/// Time at the Mac set against the focus that was logged.
struct ActivityPicture: Equatable {
    var atMac: Int
    var focus: Int

    /// Time at the Mac with no timer running. Focus away from the keyboard, a meeting say, never makes it negative.
    var untimed: Int { max(0, atMac - focus) }
    /// Share of the time at the Mac that was logged as focus.
    var share: Double { atMac > 0 ? min(1, Double(focus) / Double(atMac)) : 0 }

    /// "At the Mac 6h 10m · in focus 4h 30m · 1h 40m without a timer"
    var line: String {
        guard atMac > 0 else { return "Time at the Mac is counted from now on" }
        var parts = ["At the Mac \(Format.short(minutes: atMac))", "in focus \(Format.short(minutes: focus))"]
        if untimed >= 10 { parts.append("\(Format.short(minutes: untimed)) without a timer") }
        return parts.joined(separator: " · ")
    }
}

/// One quiet line for the bottom of the timer window.
struct ActivityLine: View {
    @ObservedObject var activity: ActivityLog
    @ObservedObject var engine: TimerEngine

    var body: some View {
        let picture = ActivityPicture(atMac: activity.minutes(on: engine.today), focus: engine.todayCoins)
        Button { AppWindows.showStats() } label: {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                Text(picture.line).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Time with any keyboard or mouse input on this Mac today, next to the focus you logged. Details are in Statistics.")
    }
}
