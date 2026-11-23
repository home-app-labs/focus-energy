import Foundation
import ServiceManagement

/// One kind of break the person can take: its length, what it is called and how it is drawn.
struct BreakPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var minutes: Int
    var name: String
    /// SF Symbol name.
    var symbol: String
    /// How many times the symbol is drawn, 1 to 3 (two coffees, three coffees).
    var count: Int = 1

    static let defaults: [BreakPreset] = [
        BreakPreset(minutes: 5, name: "Coffee", symbol: "cup.and.saucer.fill", count: 1),
        BreakPreset(minutes: 10, name: "Double coffee", symbol: "cup.and.saucer.fill", count: 2),
        BreakPreset(minutes: 15, name: "Long coffee", symbol: "cup.and.saucer.fill", count: 3),
        BreakPreset(minutes: 30, name: "Walk", symbol: "figure.walk", count: 1),
        BreakPreset(minutes: 60, name: "Lunch", symbol: "fork.knife", count: 1),
    ]

    /// Symbols offered in settings.
    static let symbolChoices: [(symbol: String, label: String)] = [
        ("cup.and.saucer.fill", "Coffee"), ("mug.fill", "Mug"), ("figure.walk", "Walk"), ("fork.knife", "Meal"),
        ("leaf.fill", "Fresh air"), ("figure.mind.and.body", "Stretch"), ("dumbbell.fill", "Workout"),
        ("bicycle", "Ride"), ("bed.double.fill", "Nap"), ("book.fill", "Reading"), ("music.note", "Music"),
        ("gamecontroller.fill", "Game"), ("phone.fill", "Call"), ("sun.max.fill", "Outside"),
        ("shower.fill", "Shower"), ("tv.fill", "Screen"),
    ]
}

/// How long a day the person plans. Each mode keeps its own numbers, which can be edited.
/// The raw values are the names from earlier versions, kept so that saved settings still load.
enum WorkMode: String, CaseIterable, Identifiable, Codable {
    case dayOff, light, moderate, hardcore

    /// The modes that plan a working day and have numbers to edit.
    static let working: [WorkMode] = [.light, .moderate, .hardcore]
    /// A day off plans nothing: no goal to chase, no reminders. It ends by itself at midnight.
    var isDayOff: Bool { self == .dayOff }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Chill"
        case .moderate: return "Moderate"
        case .hardcore: return "Hardcore"
        case .dayOff: return "Day off"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "leaf.fill"
        case .moderate: return "dial.medium.fill"
        case .hardcore: return "flame.fill"
        case .dayOff: return "sun.max.fill"
        }
    }

    /// Factory values: 25 minutes of focus and 5 of rest, the classic Pomodoro round.
    /// Ten rounds fill five hours, fifteen fill a 7.5 hour working day, twenty fill ten hours.
    var defaults: ModeSettings {
        switch self {
        case .light: return ModeSettings(sessions: 10, sessionMinutes: 25, breakMinutes: 5)
        case .moderate, .dayOff: return ModeSettings(sessions: 15, sessionMinutes: 25, breakMinutes: 5)
        case .hardcore: return ModeSettings(sessions: 20, sessionMinutes: 25, breakMinutes: 5)
        }
    }
}

/// The settings that belong to one mode: how many sessions make the day, and the rhythm of focus and rest.
/// There is no separate rest target. The rest that is due follows from the rhythm.
struct ModeSettings: Codable, Equatable {
    /// Sessions planned for the day.
    var sessions: Int
    /// Length of a session started with the main button.
    var sessionMinutes: Int
    /// The break suggested when a session ends.
    var breakMinutes: Int

    init(sessions: Int, sessionMinutes: Int, breakMinutes: Int) {
        self.sessions = sessions
        self.sessionMinutes = sessionMinutes
        self.breakMinutes = breakMinutes
    }

    private enum LegacyKeys: String, CodingKey { case focusGoal }

    /// Settings saved before 1.2 held a focus goal in minutes: it becomes a number of sessions.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionMinutes = max(1, try values.decode(Int.self, forKey: .sessionMinutes))
        breakMinutes = try values.decode(Int.self, forKey: .breakMinutes)
        if let saved = try values.decodeIfPresent(Int.self, forKey: .sessions) {
            sessions = saved
        } else {
            let goal = try decoder.container(keyedBy: LegacyKeys.self).decode(Int.self, forKey: .focusGoal)
            sessions = max(1, Int((Double(goal) / Double(sessionMinutes)).rounded()))
        }
    }

    /// Focus planned for the day, in minutes.
    var focusGoal: Int { sessions * sessionMinutes }
    /// Rest that comes with that focus when every session is followed by its break.
    var restGoal: Int { sessions * breakMinutes }
    /// The length of the day: focus and short breaks together. Lunch comes on top.
    var dayMinutes: Int { focusGoal + restGoal }

    var summary: String {
        "\(sessions) sessions · \(sessionMinutes) / \(breakMinutes) min"
    }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultExtensions = [5, 10, 15, 30, 60]

    private let d = UserDefaults.standard

    @Published var focusMinutes: Int { didSet { d.set(focusMinutes, forKey: "focusMinutes") } }
    @Published var shortBreakMinutes: Int { didSet { d.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    @Published var longBreakMinutes: Int { didSet { d.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    @Published var longBreakEvery: Int { didSet { d.set(longBreakEvery, forKey: "longBreakEvery") } }
    @Published var extensionOptions: [Int] { didSet { d.set(extensionOptions, forKey: "extensionOptions") } }
    /// Rest that goes with a full day in the current mode, in minutes. Follows from the rhythm.
    @Published var dailyRest: Int = 120
    /// The mode in use. Switching it loads that mode's limits and session lengths.
    @Published var currentMode: WorkMode = .moderate {
        didSet {
            d.set(currentMode.rawValue, forKey: "currentMode")
            if currentMode.isDayOff {
                if !oldValue.isDayOff { modeBeforeDayOff = oldValue }
                if dayOffDate == nil { dayOffDate = Date() }
            } else {
                dayOffDate = nil
            }
            applyMode()
        }
    }
    /// The working mode to go back to when the day off is over. Its numbers stay in use meanwhile,
    /// so that a timer started on a day off still has a length and the statistics keep their scale.
    private(set) var modeBeforeDayOff: WorkMode {
        get { d.string(forKey: "modeBeforeDayOff").flatMap(WorkMode.init(rawValue:)).flatMap { $0.isDayOff ? nil : $0 } ?? .moderate }
        set { d.set(newValue.rawValue, forKey: "modeBeforeDayOff") }
    }
    /// The day that was taken off.
    private(set) var dayOffDate: Date? {
        get { d.object(forKey: "dayOffDate") as? Date }
        set { d.set(newValue, forKey: "dayOffDate") }
    }

    /// Returns to the working mode once the day off is in the past.
    func endDayOffIfOver(now: Date = Date()) {
        guard currentMode.isDayOff, let day = dayOffDate, !Calendar.current.isDate(day, inSameDayAs: now) else { return }
        currentMode = modeBeforeDayOff
    }
    /// Every mode's own settings, keyed by the mode's raw value.
    @Published var modes: [String: ModeSettings] = [:] {
        didSet { d.set(try? JSONEncoder().encode(modes), forKey: "modes"); applyMode() }
    }
    @Published var breakPresets: [BreakPreset] {
        didSet { d.set(try? JSONEncoder().encode(breakPresets), forKey: "breakPresets") }
    }
    @Published var dailyGoal: Int { didSet { d.set(dailyGoal, forKey: "dailyGoal") } }
    @Published var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    /// Nudge to start a timer after this many minutes of activity without one.
    @Published var remindToStart: Bool { didSet { d.set(remindToStart, forKey: "remindToStart") } }
    @Published var remindAfterMinutes: Int { didSet { d.set(remindAfterMinutes, forKey: "remindAfterMinutes") } }
    /// Look for a new version once a day.
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    /// Install a new version without asking, at a quiet moment.
    @Published var autoInstallUpdates: Bool { didSet { d.set(autoInstallUpdates, forKey: "autoInstallUpdates") } }
    /// Set just before the app replaces itself, so that the new copy can say what happened.
    var updatedFromVersion: String? {
        get { d.string(forKey: "updatedFromVersion") }
        set { d.set(newValue, forKey: "updatedFromVersion") }
    }
    @Published var showNotifications: Bool { didSet { d.set(showNotifications, forKey: "showNotifications") } }
    @Published var showCoinsInMenuBar: Bool { didSet { d.set(showCoinsInMenuBar, forKey: "showCoinsInMenuBar") } }
    /// Send timer notifications to the phone through ntfy.
    /// Minutes to wait for a reaction on the Mac before the phone is told. 0 sends at once.
    @Published var pushDelayMinutes: Int { didSet { d.set(pushDelayMinutes, forKey: "pushDelayMinutes") } }
    @Published var pushEnabled: Bool { didSet { d.set(pushEnabled, forKey: "pushEnabled") } }
    /// The private ntfy topic. Random, and effectively the password.
    @Published var pushTopic: String { didSet { d.set(pushTopic, forKey: "pushTopic") } }
    @Published var showTimerInDock: Bool { didSet { d.set(showTimerInDock, forKey: "showTimerInDock") } }
    @Published var popUpWhenFinished: Bool { didSet { d.set(popUpWhenFinished, forKey: "popUpWhenFinished") } }

    private init() {
        d.register(defaults: [
            "focusMinutes": 30,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "longBreakEvery": 4,
            "extensionOptions": Self.defaultExtensions,
            "dailyGoal": 360,
            "playSounds": true,
            "showNotifications": true,
            "autoCheckUpdates": true,
            "autoInstallUpdates": false,
            "remindToStart": true,
            "remindAfterMinutes": 10,
            "showCoinsInMenuBar": true,
            "popUpWhenFinished": true,
            "showTimerInDock": true,
        ])
        focusMinutes = max(1, d.integer(forKey: "focusMinutes"))
        shortBreakMinutes = max(1, d.integer(forKey: "shortBreakMinutes"))
        longBreakMinutes = max(1, d.integer(forKey: "longBreakMinutes"))
        longBreakEvery = max(1, d.integer(forKey: "longBreakEvery"))
        let ext = (d.array(forKey: "extensionOptions") as? [Int]) ?? Self.defaultExtensions
        extensionOptions = ext.isEmpty ? Self.defaultExtensions : ext
        dailyGoal = max(1, d.integer(forKey: "dailyGoal"))
        let savedPresets = d.data(forKey: "breakPresets").flatMap { try? JSONDecoder().decode([BreakPreset].self, from: $0) }
        breakPresets = (savedPresets?.isEmpty == false ? savedPresets : nil) ?? BreakPreset.defaults
        playSounds = d.bool(forKey: "playSounds")
        showNotifications = d.bool(forKey: "showNotifications")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        autoInstallUpdates = d.bool(forKey: "autoInstallUpdates")
        remindToStart = d.bool(forKey: "remindToStart")
        remindAfterMinutes = d.integer(forKey: "remindAfterMinutes")
        showCoinsInMenuBar = d.bool(forKey: "showCoinsInMenuBar")
        popUpWhenFinished = d.bool(forKey: "popUpWhenFinished")
        showTimerInDock = d.bool(forKey: "showTimerInDock")
        // Development runs can point at a throwaway topic without touching the saved setting.
        let overrideTopic = ProcessInfo.processInfo.environment["FOCUSPLUS_PUSH_TOPIC"]
        pushTopic = overrideTopic ?? d.string(forKey: "pushTopic") ?? ""
        pushEnabled = overrideTopic != nil || d.bool(forKey: "pushEnabled")
        pushDelayMinutes = overrideTopic != nil ? 0 : (d.object(forKey: "pushDelayMinutes") as? Int ?? 1)
        // Modes come last: applying one fills in the goal, the rest target and the session lengths above.
        modes = d.data(forKey: "modes").flatMap { try? JSONDecoder().decode([String: ModeSettings].self, from: $0) } ?? [:]
        currentMode = d.string(forKey: "currentMode").flatMap(WorkMode.init(rawValue:)) ?? .moderate
        applyMode()
        endDayOffIfOver()
        // Topics from earlier versions mixed letters and digits: replace them with the readable kind.
        if overrideTopic == nil, !pushTopic.isEmpty,
           pushTopic.range(of: "^focus-[a-z]{6}-[a-z]{6}$", options: .regularExpression) == nil {
            regeneratePushTopic()
        }
    }

    /// Lengths offered for starting a session: the same buttons as for extending one.
    /// The mode's default length has its own big Start button, so it is not added here.
    var startOptions: [Int] {
        extensionOptions
    }

    /// Break lengths offered, shortest first, one button per distinct length.
    var breakOptions: [Int] {
        Array(Set(breakPresets.map(\.minutes).filter { $0 > 0 })).sorted()
    }

    /// The preset for a break of this length: an exact match, or else the closest shorter one.
    func breakPreset(minutes: Int) -> BreakPreset? {
        let sorted = breakPresets.sorted { $0.minutes < $1.minutes }
        return sorted.first { $0.minutes == minutes } ?? sorted.last { $0.minutes <= minutes } ?? sorted.first
    }

    /// Makes a new random topic name, long enough that it cannot be guessed.
    /// Letters only, in two pronounceable words such as "focus-tavomi-kerulo": easy to read and type,
    /// and with about a million million combinations still not guessable.
    func regeneratePushTopic() {
        let consonants = Array("bdfgkmnprstvz"), vowels = Array("aeiou")
        let words = (0..<2).map { _ in
            String((0..<3).flatMap { _ in [consonants.randomElement()!, vowels.randomElement()!] })
        }
        pushTopic = "focus-" + words.joined(separator: "-")
    }

    // MARK: Modes

    func settings(for mode: WorkMode) -> ModeSettings {
        let source = mode.isDayOff ? modeBeforeDayOff : mode
        return modes[source.rawValue] ?? source.defaults
    }

    /// One line about a mode for the mode menu.
    func summary(for mode: WorkMode) -> String {
        mode.isDayOff ? "No goal, no reminders, until tomorrow" : settings(for: mode).summary
    }

    func update(_ mode: WorkMode, _ change: (inout ModeSettings) -> Void) {
        guard !mode.isDayOff else { return }
        var value = settings(for: mode)
        change(&value)
        value.sessions = min(40, max(1, value.sessions))
        value.sessionMinutes = min(240, max(5, value.sessionMinutes))
        value.breakMinutes = min(120, max(1, value.breakMinutes))
        modes[mode.rawValue] = value
    }

    func reset(_ mode: WorkMode) { modes[mode.rawValue] = nil }

    /// Copies the current mode's settings into the values the rest of the app reads.
    private func applyMode() {
        let active = settings(for: currentMode)
        if dailyGoal != active.focusGoal { dailyGoal = active.focusGoal }
        if dailyRest != active.restGoal { dailyRest = active.restGoal }
        if focusMinutes != active.sessionMinutes { focusMinutes = active.sessionMinutes }
        if shortBreakMinutes != active.breakMinutes { shortBreakMinutes = active.breakMinutes }
    }

    /// Parses "5, 10, 15" into a sorted, de-duplicated list of minutes.
    static func parseExtensions(_ text: String) -> [Int] {
        let values = text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { $0 > 0 && $0 <= 600 }
        return Array(Set(values)).sorted()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("FocusPlus: launch at login failed: \(error.localizedDescription)")
            }
        }
    }
}
