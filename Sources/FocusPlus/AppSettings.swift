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

/// How hard the person wants to work. Each mode keeps its own limits, which can be edited.
enum WorkMode: String, CaseIterable, Identifiable, Codable {
    case light, moderate, hardcore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .hardcore: return "Hardcore"
        }
    }

    var symbol: String {
        switch self {
        case .light: return "leaf.fill"
        case .moderate: return "dial.medium.fill"
        case .hardcore: return "flame.fill"
        }
    }

    /// Factory values. Moderate follows the classic Pomodoro day: six hours of focus and two of rest.
    var defaults: ModeSettings {
        switch self {
        case .light: return ModeSettings(focusGoal: 240, restGoal: 90, sessionMinutes: 25, breakMinutes: 5)
        case .moderate: return ModeSettings(focusGoal: 360, restGoal: 120, sessionMinutes: 30, breakMinutes: 5)
        case .hardcore: return ModeSettings(focusGoal: 480, restGoal: 120, sessionMinutes: 45, breakMinutes: 5)
        }
    }
}

/// The settings that belong to one mode.
struct ModeSettings: Codable, Equatable {
    /// Focus limit for the day, in minutes.
    var focusGoal: Int
    /// Rest planned for the day, in minutes.
    var restGoal: Int
    /// Length of a session started with the main button.
    var sessionMinutes: Int
    /// The break suggested when a session ends.
    var breakMinutes: Int

    var summary: String {
        "\(Format.short(minutes: focusGoal)) focus · \(Format.short(minutes: restGoal)) rest"
    }

    /// Rest the classic Pomodoro technique would give for this much focus:
    /// 25 minutes on, 5 off, and a 15 to 30 minute break after every four rounds.
    var pomodoroRest: ClosedRange<Int> {
        let cycles = Double(focusGoal) / 100
        return Int((cycles * 30).rounded())...Int((cycles * 45).rounded())
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
    /// Rest planned for the day in the current mode, in minutes.
    @Published var dailyRest: Int = 120
    /// The mode in use. Switching it loads that mode's limits and session lengths.
    @Published var currentMode: WorkMode = .moderate {
        didSet { d.set(currentMode.rawValue, forKey: "currentMode"); applyMode() }
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

    func settings(for mode: WorkMode) -> ModeSettings { modes[mode.rawValue] ?? mode.defaults }

    func update(_ mode: WorkMode, _ change: (inout ModeSettings) -> Void) {
        var value = settings(for: mode)
        change(&value)
        value.focusGoal = min(960, max(30, value.focusGoal))
        value.restGoal = min(480, max(0, value.restGoal))
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
