import Foundation

/// Everything the desktop widget shows. The app writes it to `widget-state.json`; the widget only reads it.
public struct WidgetSnapshot: Codable, Equatable {
    public enum Phase: String, Codable { case idle, focus, rest }
    public enum RunState: String, Codable { case idle, running, paused, finished }

    /// The day's numbers at one moment. The app projects one point per minute until the countdown ends,
    /// so the widget stays current without asking the app again.
    public struct Point: Codable, Equatable {
        public var date: Date
        public var coins: Int
        public var breakMinutes: Int
        public var recommendedRest: Int
        public var energy: Double
        public var moodEmoji: String
        public var moodTitle: String
        public var advice: String

        public init(date: Date, coins: Int, breakMinutes: Int, recommendedRest: Int, energy: Double,
                    moodEmoji: String, moodTitle: String, advice: String) {
            self.date = date; self.coins = coins; self.breakMinutes = breakMinutes
            self.recommendedRest = recommendedRest; self.energy = energy
            self.moodEmoji = moodEmoji; self.moodTitle = moodTitle; self.advice = advice
        }
    }

    public struct Day: Codable, Equatable, Identifiable {
        public var day: Date
        public var label: String
        public var coins: Int
        public var emoji: String
        public var isToday: Bool
        public var isFuture: Bool
        public var id: Date { day }

        public init(day: Date, label: String, coins: Int, emoji: String, isToday: Bool, isFuture: Bool) {
            self.day = day; self.label = label; self.coins = coins; self.emoji = emoji
            self.isToday = isToday; self.isFuture = isFuture
        }
    }

    public var phase: Phase
    public var runState: RunState
    /// When the running countdown ends.
    public var endsAt: Date?
    public var plannedSeconds: Double
    /// Seconds left, for a paused timer.
    public var remainingSeconds: Double
    public var goal: Int
    public var defaultFocusMinutes: Int
    public var points: [Point]
    public var week: [Day]

    public init(phase: Phase, runState: RunState, endsAt: Date?, plannedSeconds: Double, remainingSeconds: Double,
                goal: Int, defaultFocusMinutes: Int, points: [Point], week: [Day]) {
        self.phase = phase; self.runState = runState; self.endsAt = endsAt
        self.plannedSeconds = plannedSeconds; self.remainingSeconds = remainingSeconds
        self.goal = goal; self.defaultFocusMinutes = defaultFocusMinutes
        self.points = points; self.week = week
    }

    public static let fileName = "widget-state.json"

    public static var placeholder: WidgetSnapshot {
        let now = Date()
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let coins = [360, 410, 300, 250, 0, 0, 0]
        let faces = ["😄", "😄", "🙂", "🙂", "😴", "😴", "😴"]
        let point = Point(date: now, coins: 250, breakMinutes: 30, recommendedRest: 41, energy: 0.78,
                          moodEmoji: "😄", moodTitle: "Full of energy", advice: "Good rhythm of focus and rest.")
        var week: [Day] = []
        for index in 0..<7 {
            let day: Date = now.addingTimeInterval(Double(index - 3) * 86400)
            week.append(Day(day: day, label: labels[index], coins: coins[index], emoji: faces[index],
                            isToday: index == 3, isFuture: index > 3))
        }
        return WidgetSnapshot(phase: .focus, runState: .running, endsAt: now.addingTimeInterval(1080),
                              plannedSeconds: 1800, remainingSeconds: 1080, goal: 360, defaultFocusMinutes: 30,
                              points: [point], week: week)
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// When the Mac wrote this snapshot.
    public var updatedAt: Date? { points.first?.date }

    /// Whole minutes left on the running countdown at `date`, or nil when nothing is running.
    public func minutesLeft(at date: Date) -> Int? {
        guard runState == .running, let endsAt, endsAt > date else { return nil }
        return Int((endsAt.timeIntervalSince(date) / 60).rounded(.up))
    }

    /// The latest projected point at or before `date`.
    public func point(at date: Date) -> Point? {
        points.last { $0.date <= date } ?? points.first
    }

    /// The snapshot as it should look at `date`, for the moments when the app has not written a newer one:
    /// a countdown that has run out shows as finished, and after midnight the day starts from zero.
    public func resolved(at date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = self
        if runState == .running, let endsAt, date >= endsAt {
            copy.runState = .finished
            copy.endsAt = nil
            copy.remainingSeconds = 0
        }
        guard let written = updatedAt, !calendar.isDate(written, inSameDayAs: date), date > written else { return copy }
        // A timer still counting down across midnight keeps its numbers until it ends.
        if copy.runState == .running { return copy }

        let today = calendar.startOfDay(for: date)
        copy.phase = .idle
        copy.runState = .idle
        copy.endsAt = nil
        copy.remainingSeconds = 0
        copy.points = [Point(date: today, coins: 0, breakMinutes: 0, recommendedRest: 0, energy: 1,
                             moodEmoji: "😴", moodTitle: "Not started yet", advice: "Pick a length and start.")]
        if week.contains(where: { calendar.isDate($0.day, inSameDayAs: date) }) {
            copy.week = week.map { day in
                var day = day
                day.isToday = calendar.isDate(day.day, inSameDayAs: date)
                day.isFuture = calendar.startOfDay(for: day.day) > today
                return day
            }
        } else {
            // A new week has begun: the same seven labels, moved on by whole weeks, all still empty.
            let first = calendar.startOfDay(for: week.first?.day ?? today)
            let weeks = (calendar.dateComponents([.day], from: first, to: today).day ?? 0) / 7
            copy.week = week.map { old in
                let moved = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: old.day)) ?? old.day
                return Day(day: moved, label: old.label, coins: 0, emoji: "😴",
                           isToday: calendar.isDate(moved, inSameDayAs: date), isFuture: moved > today)
            }
        }
        return copy
    }
}
