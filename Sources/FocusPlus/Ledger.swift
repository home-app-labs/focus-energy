import Foundation

/// One finished focus session. `minutes` is what was actually focused, and equals the coins earned.
struct FocusEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var minutes: Int
    var baseMinutes: Int
    var extensions: [Int]

    var coins: Int { minutes }
}

/// A focus session that is still open. Saved to disk so a crash or a forced quit loses nothing.
struct ActiveSession: Codable, Equatable {
    var id = UUID()
    var start: Date
    var baseMinutes: Int
    var extensions: [Int] = []
    var focusedSeconds: Double = 0
    var lastUpdate: Date
    /// Set while the countdown is running, so the session can resume after the app restarts.
    var endsAt: Date?
    var plannedSeconds: Double?

    var plannedMinutes: Int { baseMinutes + extensions.reduce(0, +) }
    var earnedMinutes: Int { Int((focusedSeconds + 0.5) / 60) }
}

/// One break that was actually taken.
struct BreakEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var minutes: Int
    /// What the break was called when it was taken.
    var name: String?
}

/// Everything known about one day, for the weekly view.
struct DaySummary: Identifiable, Equatable {
    var day: Date
    var coins: Int
    var sessions: Int
    var breakMinutes: Int
    /// The person's own 1 to 5 rating of the day, if they gave one.
    var rating: Int?
    var id: Date { day }
}

struct DayTotal: Identifiable, Equatable {
    var day: Date
    var coins: Int
    var sessions: Int
    var id: Date { day }
}

/// The coin ledger: every focused minute is one coin. Stored as JSON in Application Support.
final class Ledger: ObservableObject {
    static let shared = Ledger()

    @Published private(set) var entries: [FocusEntry] = []
    @Published private(set) var breaks: [BreakEntry] = []
    /// Self-ratings keyed by "yyyy-MM-dd". Zero means the rating was cleared.
    @Published private(set) var ratings: [String: Int] = [:]
    /// True when the time log lives in iCloud Drive and so follows the person across their Macs.
    @Published private(set) var usesICloud = false

    /// Stays on this Mac: the open session and the widget snapshot.
    private let localDirectory: URL
    /// Holds the time log: on this Mac, or in iCloud Drive.
    private var dataDirectory: URL
    /// Ids removed here or on another Mac, so a merge never brings a deleted entry back.
    private var deleted: Set<UUID> = []
    private var seenDates: [String: Date] = [:]
    private let allowsICloud: Bool

    /// Folder holding the widget snapshot.
    var directoryURL: URL { localDirectory }
    var dataDirectoryURL: URL { dataDirectory }
    private var entriesURL: URL { dataDirectory.appendingPathComponent("ledger.json") }
    private var breaksURL: URL { dataDirectory.appendingPathComponent("breaks.json") }
    private var ratingsURL: URL { dataDirectory.appendingPathComponent("day-ratings.json") }
    private var deletedURL: URL { dataDirectory.appendingPathComponent("deleted.json") }
    private var activeURL: URL { localDirectory.appendingPathComponent("active-session.json") }
    private let calendar = Calendar.current

    static let iCloudDefaultsKey = "useICloudDrive"

    /// "Focus Energy" inside the person's iCloud Drive, or nil when iCloud Drive is not set up on this Mac.
    static var iCloudFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: drive.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        // The app used to be called Focus Plus: keep using that folder where it already exists.
        let old = drive.appendingPathComponent("Focus Plus", isDirectory: true)
        if FileManager.default.fileExists(atPath: old.path) { return old }
        return drive.appendingPathComponent("Focus Energy", isDirectory: true)
    }

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let override = ProcessInfo.processInfo.environment["FOCUSPLUS_DATA_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        localDirectory = directory ?? override ?? base.appendingPathComponent("FocusPlus", isDirectory: true)
        dataDirectory = localDirectory
        // Tests and development runs with their own folder never touch iCloud.
        allowsICloud = directory == nil && override == nil
        try? FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)

        if allowsICloud, UserDefaults.standard.bool(forKey: Self.iCloudDefaultsKey), let cloud = Self.iCloudFolder,
           (try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)) != nil {
            dataDirectory = cloud
            usesICloud = true
        }
        load()
    }

    // MARK: Persistence

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        if usesICloud { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try Self.encoder.encode(value).write(to: url, options: .atomic)
            seenDates[url.lastPathComponent] = modificationDate(url)
        } catch {
            NSLog("FocusPlus: could not save \(url.lastPathComponent): \(error)")
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func load() {
        if let data = try? Data(contentsOf: entriesURL),
           (try? Self.decoder.decode([FocusEntry].self, from: data)) == nil {
            // Never overwrite a ledger we could not read: keep it aside for manual recovery.
            let backup = dataDirectory.appendingPathComponent("ledger-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: entriesURL, to: backup)
            NSLog("FocusPlus: ledger unreadable, moved to \(backup.path)")
        }
        entries = []
        breaks = []
        ratings = [:]
        deleted = []
        seenDates = [:]
        mergeFromDisk()
    }

    /// Folds what is on disk into memory. Entries are matched by id, and deleted ids stay deleted,
    /// so changes made on another Mac are added without losing anything made here.
    /// Returns true when something changed.
    @discardableResult
    private func mergeFromDisk() -> Bool {
        let before = (entries, breaks, ratings)
        if let ids = read([UUID].self, from: deletedURL) { deleted.formUnion(ids) }
        if let disk = read([FocusEntry].self, from: entriesURL) {
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: disk.filter { !known.contains($0.id) })
        }
        if let disk = read([BreakEntry].self, from: breaksURL) {
            let known = Set(breaks.map(\.id))
            breaks.append(contentsOf: disk.filter { !known.contains($0.id) })
        }
        if let disk = read([String: Int].self, from: ratingsURL) {
            ratings.merge(disk) { _, fromDisk in fromDisk }
        }
        entries = entries.filter { !deleted.contains($0.id) }.sorted { $0.start < $1.start }
        breaks = breaks.filter { !deleted.contains($0.id) }.sorted { $0.start < $1.start }
        for url in [entriesURL, breaksURL, ratingsURL, deletedURL] {
            seenDates[url.lastPathComponent] = modificationDate(url)
        }
        return before.0 != entries || before.1 != breaks || before.2 != ratings
    }

    /// Picks up changes another Mac made to the shared files. Cheap when nothing changed.
    @discardableResult
    func refresh() -> Bool {
        let changed = [entriesURL, breaksURL, ratingsURL, deletedURL].contains {
            modificationDate($0) != seenDates[$0.lastPathComponent]
        }
        return changed ? mergeFromDisk() : false
    }

    private func saveEntries() { write(entries, to: entriesURL) }
    private func saveBreaks() { write(breaks, to: breaksURL) }
    private func saveDeleted() { write(Array(deleted).sorted { $0.uuidString < $1.uuidString }, to: deletedURL) }

    func add(_ entry: FocusEntry) {
        refresh()
        entries.append(entry)
        saveEntries()
    }

    func remove(_ entry: FocusEntry) {
        refresh()
        deleted.insert(entry.id)
        entries.removeAll { $0.id == entry.id }
        saveDeleted()
        saveEntries()
    }

    // MARK: iCloud Drive

    /// Moves the time log into iCloud Drive or back onto this Mac. What is already at the destination is merged in,
    /// and the copy left behind is kept as a backup. Returns an error message on failure.
    @discardableResult
    func setICloud(enabled: Bool) -> String? {
        guard allowsICloud else { return "Not available in this run." }
        guard enabled != usesICloud else { return nil }
        let target: URL
        if enabled {
            guard let cloud = Self.iCloudFolder else { return "iCloud Drive is not turned on for this Mac." }
            target = cloud
        } else {
            target = localDirectory
        }
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let probe = target.appendingPathComponent(".write-test")
            try Data().write(to: probe)
            try? FileManager.default.removeItem(at: probe)
        } catch {
            return "Could not write to \(target.path): \(error.localizedDescription)"
        }
        refresh()
        dataDirectory = target
        usesICloud = enabled
        seenDates = [:]
        mergeFromDisk()
        saveEntries()
        saveBreaks()
        write(ratings, to: ratingsURL)
        saveDeleted()
        UserDefaults.standard.set(enabled, forKey: Self.iCloudDefaultsKey)
        return nil
    }

    // MARK: Breaks and day ratings

    func addBreak(_ entry: BreakEntry) {
        refresh()
        breaks.append(entry)
        saveBreaks()
    }

    func removeBreak(_ entry: BreakEntry) {
        refresh()
        deleted.insert(entry.id)
        breaks.removeAll { $0.id == entry.id }
        saveDeleted()
        saveBreaks()
    }

    func breaks(on day: Date) -> [BreakEntry] {
        breaks.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    func breakMinutes(on day: Date) -> Int {
        breaks.filter { calendar.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    /// Focus minutes logged today after the most recent break started.
    func focusMinutesSinceLastBreak(on day: Date) -> Int {
        let lastBreak = breaks.filter { calendar.isDate($0.start, inSameDayAs: day) }.map(\.start).max()
        return entries(on: day).filter { lastBreak == nil || $0.start >= lastBreak! }.reduce(0) { $0 + $1.coins }
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func rating(on day: Date) -> Int? {
        guard let value = ratings[Self.dayKeyFormatter.string(from: day)], value > 0 else { return nil }
        return value
    }

    /// Stores a 1 to 5 rating for the day; nil clears it.
    func setRating(_ value: Int?, on day: Date) {
        refresh()
        ratings[Self.dayKeyFormatter.string(from: day)] = value.map { min(5, max(1, $0)) } ?? 0
        write(ratings, to: ratingsURL)
    }

    /// The seven days of the week containing `date`, shifted by `offset` weeks.
    func week(offset: Int = 0, containing date: Date = Date()) -> [DaySummary] {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: date),
              let interval = calendar.dateInterval(of: .weekOfYear, for: shifted) else { return [] }
        return (0..<7).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: index, to: interval.start) else { return nil }
            let dayEntries = entries(on: day)
            return DaySummary(day: day, coins: dayEntries.reduce(0) { $0 + $1.coins }, sessions: dayEntries.count,
                              breakMinutes: breakMinutes(on: day), rating: rating(on: day))
        }
    }

    // MARK: Open session (crash safety)

    func saveActive(_ session: ActiveSession) {
        try? Self.encoder.encode(session).write(to: activeURL, options: .atomic)
    }

    func loadActive() -> ActiveSession? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? Self.decoder.decode(ActiveSession.self, from: data)
    }

    func clearActive() {
        try? FileManager.default.removeItem(at: activeURL)
    }

    /// Credits a session left open by a crash or forced quit. Returns the recovered entry, if any.
    @discardableResult
    func recoverActive() -> FocusEntry? {
        guard let data = try? Data(contentsOf: activeURL),
              let session = try? Self.decoder.decode(ActiveSession.self, from: data) else {
            clearActive()
            return nil
        }
        clearActive()
        guard session.earnedMinutes > 0 else { return nil }
        let entry = FocusEntry(id: session.id, start: session.start, end: session.lastUpdate,
                               minutes: session.earnedMinutes, baseMinutes: session.baseMinutes,
                               extensions: session.extensions)
        add(entry)
        return entry
    }

    // MARK: Statistics

    func entries(on day: Date) -> [FocusEntry] {
        entries.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    func coins(on day: Date) -> Int {
        entries(on: day).reduce(0) { $0 + $1.coins }
    }

    var allTimeCoins: Int { entries.reduce(0) { $0 + $1.coins } }

    /// Totals for the last `count` days, oldest first, including empty days.
    func dailyTotals(lastDays count: Int, endingAt now: Date = Date()) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: (coins: Int, sessions: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.start)
            let current = buckets[day] ?? (0, 0)
            buckets[day] = (current.coins + entry.coins, current.sessions + 1)
        }
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let bucket = buckets[day] ?? (0, 0)
            return DayTotal(day: day, coins: bucket.coins, sessions: bucket.sessions)
        }
    }

    /// Coins since the start of the current calendar week.
    func coinsThisWeek(now: Date = Date()) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return entries.filter { week.contains($0.start) }.reduce(0) { $0 + $1.coins }
    }

    func coinsThisMonth(now: Date = Date()) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return entries.filter { month.contains($0.start) }.reduce(0) { $0 + $1.coins }
    }

    /// Consecutive days with at least one coin. Today counts when it has coins,
    /// and an empty today does not break a streak that ran through yesterday.
    func streak(now: Date = Date(), extraToday: Int = 0) -> Int {
        let days = Set(entries.filter { $0.coins > 0 }.map { calendar.startOfDay(for: $0.start) })
        var cursor = calendar.startOfDay(for: now)
        var count = 0
        if days.contains(cursor) || extraToday > 0 {
            count = 1
        }
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(previous) {
            count += 1
            cursor = previous
        }
        return count
    }

    func bestDay() -> DayTotal? {
        var buckets: [Date: (coins: Int, sessions: Int)] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.start)
            let current = buckets[day] ?? (0, 0)
            buckets[day] = (current.coins + entry.coins, current.sessions + 1)
        }
        return buckets.max { $0.value.coins < $1.value.coins }
            .map { DayTotal(day: $0.key, coins: $0.value.coins, sessions: $0.value.sessions) }
    }
}
