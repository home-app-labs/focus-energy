import SwiftUI

/// How the day is going for the person, judged from focus time, breaks and the daily goal.
struct Wellbeing: Equatable {
    enum Mood: Equatable {
        case idle, energised, steady, tired, overworked, dayOff

        var emoji: String {
            switch self {
            case .idle: return "😴"
            case .energised: return "😄"
            case .steady: return "🙂"
            case .tired: return "😮‍💨"
            case .overworked: return "🥵"
            case .dayOff: return "🌴"
            }
        }

        var title: String {
            switch self {
            case .idle: return "Not started yet"
            case .energised: return "Full of energy"
            case .steady: return "Steady pace"
            case .tired: return "Getting tired"
            case .overworked: return "Overworked"
            case .dayOff: return "Day off"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .dayOff: return Palette.rest
            case .energised: return Palette.rest
            case .steady: return Color(red: 0.20, green: 0.60, blue: 0.90)
            case .tired: return Color(red: 0.96, green: 0.58, blue: 0.16)
            case .overworked: return Palette.focus
            }
        }
    }


    var focusMinutes: Int
    var breakMinutes: Int
    var goal: Int
    /// Focus minutes since the last break.
    var stretch: Int
    /// Rest that goes with a full day at the goal: one short break after every session.
    var restGoal: Int
    /// Length of one session in the mode in use: the unit the day is counted in.
    var sessionMinutes: Int
    /// The longest single break taken today, in minutes.
    var longestBreak: Int
    /// A day off: nothing is asked of the person and nothing is suggested.
    var dayOff = false

    /// A break of this length counts as the long one of the day.
    static let longBreakMinutes = 30
    /// Focus without a break that is long enough to suggest one.
    static let stretchLimit = 60

    init(focusMinutes: Int, breakMinutes: Int, goal: Int, stretch: Int, restGoal: Int? = nil, sessionMinutes: Int = 25,
         longestBreak: Int = 0) {
        self.longestBreak = longestBreak
        self.sessionMinutes = max(1, sessionMinutes)
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        self.goal = goal
        self.stretch = stretch
        self.restGoal = restGoal ?? goal / 3
    }

    /// Sessions worth of focus done today. A session extended to twice its length counts as two.
    var sessionsDone: Int { focusMinutes / sessionMinutes }
    var sessionsGoal: Int { max(1, goal / sessionMinutes) }
    /// An hour of focus has passed without a break.
    var breakIsDue: Bool { stretch >= Self.stretchLimit }
    /// Half the day's sessions are done, or four hours of focus, and there has been no long break yet.
    /// How long it should be is left to the person.
    var longBreakIsDue: Bool {
        let threshold = Swift.min(goal / 2, 240)
        return focusMinutes > 0 && focusMinutes >= threshold && longestBreak < Wellbeing.longBreakMinutes
    }
    /// The one-line suggestion to rest, when there is one.
    var breakHint: String? {
        if dayOff { return nil }
        if longBreakIsDue { return "\(Format.duration(minutes: focusMinutes)) of focus today. Take a long break." }
        if breakIsDue { return "\(Format.duration(minutes: stretch)) without a break. Time for a coffee." }
        return nil
    }

    /// Rest that is due so far: one break for every session done.
    /// It moves in whole breaks, so it never asks for rest for a session that is still running.
    var recommendedRest: Int { sessionsDone * restGoal / sessionsGoal }
    var restDeficit: Int { max(0, recommendedRest - breakMinutes) }
    var overtime: Int { max(0, focusMinutes - goal) }

    /// Focus done as a share of the daily goal; above 1 is overtime.
    var focusShare: Double { Double(focusMinutes) / Double(max(goal, 1)) }

    /// Rest taken as a share of the rest that is due for the work done.
    var restShare: Double {
        recommendedRest > 0 ? Double(breakMinutes) / Double(recommendedRest) : (breakMinutes > 0 ? 1 : 0)
    }

    /// Rest taken as a share of the rest planned for the whole day.
    var restShareOfDay: Double { restGoal > 0 ? Double(breakMinutes) / Double(restGoal) : (breakMinutes > 0 ? 1 : 0) }

    /// 1 is fresh, 0 is spent.
    var energy: Double {
        if dayOff { return 1 }
        let safeGoal = Double(max(goal, 1))
        let focus = Double(focusMinutes)
        // Ordinary tiredness from a full day of work.
        var drain = min(focus / safeGoal, 1) * 0.20
        // Working past the goal costs the most: four hours over a six hour goal empties the tank.
        drain += Double(overtime) / (safeGoal * 0.67) * 0.60
        // Skipped breaks.
        if focusMinutes >= 60, recommendedRest > 0 {
            drain += Double(restDeficit) / Double(recommendedRest) * 0.20
        }
        // A long unbroken stretch.
        drain += min(max(Double(stretch) - 60, 0) / 60, 1) * 0.15
        return min(1, max(0, 1 - drain))
    }

    /// The colour of the energy bar: green while the day is in balance, orange once it tips, red when it is critical.
    /// The steps follow the moods: half and up, a quarter and up, below a quarter.
    var energyColor: Color {
        switch energy {
        case 0.50...: return Palette.rest
        case 0.25...: return Color(red: 0.96, green: 0.58, blue: 0.16)
        default: return Palette.focus
        }
    }

    var mood: Mood {
        if dayOff { return .dayOff }
        if focusMinutes == 0 { return .idle }
        switch energy {
        case 0.75...: return .energised
        case 0.50...: return .steady
        case 0.25...: return .tired
        default: return .overworked
        }
    }

    /// "6 : 1" style ratio of focus to rest.
    var ratioText: String {
        guard breakMinutes > 0 else { return focusMinutes > 0 ? "no breaks yet" : "–" }
        let ratio = Double(focusMinutes) / Double(breakMinutes)
        return String(format: ratio >= 10 ? "%.0f : 1" : "%.1f : 1", ratio)
    }

    var advice: String {
        if dayOff { return "Rest today. Back to work tomorrow." }
        if focusMinutes == 0 { return "Pick a length and start." }
        if overtime > 0 && mood == .overworked { return "Well past the goal. Time to stop for today." }
        if let breakHint { return breakHint }
        if restDeficit >= 10 { return "\(restDeficit) min of rest owed. A coffee would help." }
        if overtime > 0 { return "Goal done. Anything more is overtime." }
        return "Good rhythm of focus and rest."
    }

    /// A small picture for the advice line: what to do next, at a glance.
    var adviceIcon: String {
        if dayOff { return "🌴" }
        if focusMinutes == 0 { return "👉" }
        if overtime > 0 && mood == .overworked { return "🛑" }
        if longBreakIsDue { return "🚶" }
        if breakIsDue { return "☕️" }
        if restDeficit >= 10 { return "☕️" }
        if overtime > 0 { return "🏁" }
        return "👍"
    }
}

/// A verdict on one finished day, relative to the daily goal (six hours by default).
enum DayVerdict: Equatable {
    case none, light, onTrack, great, heavy, overwork

    /// With a six hour goal: under 3 h light, up to 6 h on track, 6 to 8 h great, 8 to 10 h heavy, 10 h and more overwork.
    static func of(coins: Int, goal: Int) -> DayVerdict {
        guard coins > 0 else { return .none }
        let share = Double(coins) / Double(max(goal, 1))
        switch share {
        case ..<0.5: return .light
        case ..<1.0: return .onTrack
        case ..<1.34: return .great
        case ..<1.66: return .heavy
        default: return .overwork
        }
    }

    var emoji: String {
        switch self {
        case .none: return "😴"
        case .light: return "🌱"
        case .onTrack: return "🙂"
        case .great: return "😄"
        case .heavy: return "😮‍💨"
        case .overwork: return "🥵"
        }
    }

    var title: String {
        switch self {
        case .none: return "Day off"
        case .light: return "Light"
        case .onTrack: return "On track"
        case .great: return "Well done"
        case .heavy: return "Heavy"
        case .overwork: return "Overwork"
        }
    }

    var color: Color {
        switch self {
        case .none: return .secondary
        case .light: return Color(red: 0.55, green: 0.70, blue: 0.40)
        case .onTrack: return Color(red: 0.20, green: 0.60, blue: 0.90)
        case .great: return Palette.rest
        case .heavy: return Color(red: 0.96, green: 0.58, blue: 0.16)
        case .overwork: return Palette.focus
        }
    }
}
