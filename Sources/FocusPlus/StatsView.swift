import SwiftUI
import Charts

struct StatsView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ledger: Ledger
    @ObservedObject var activity = ActivityLog.shared

    @State private var range = 14
    /// FOCUSPLUS_WEEK=-1 opens on last week, for screenshots early in a week.
    @State private var weekOffset = min(0, Int(ProcessInfo.processInfo.environment["FOCUSPLUS_WEEK"] ?? "") ?? 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnergyCard(wellbeing: engine.wellbeing, large: true)
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                DayRatingRow(ledger: ledger, day: engine.today, prompt: "How does today feel for productivity?", large: true)
                weekSection
                activitySection
                tiles
                chart
                todayList
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 760)
    }

    // MARK: Week by day

    /// The selected week, with the open session and running break added to today.
    private var weekDays: [DaySummary] {
        var days = ledger.week(offset: weekOffset)
        if weekOffset == 0, let index = days.firstIndex(where: { Calendar.current.isDateInToday($0.day) }) {
            days[index].coins += engine.liveCoins
            days[index].breakMinutes += engine.liveBreakMinutes
        }
        return days
    }

    private var weekSection: some View {
        let days = weekDays
        let goal = settings.dailyGoal
        let total = days.reduce(0) { $0 + $1.coins }
        let overtime = days.reduce(0) { $0 + max(0, $1.coins - goal) }
        let verdicts = days.map { DayVerdict.of(coins: $0.coins, goal: goal) }
        let overworkDays = verdicts.filter { $0 == .overwork }.count
        let heavyDays = verdicts.filter { $0 == .heavy }.count
        let rated = days.compactMap(\.rating)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Week by day").font(.headline)
                if let first = days.first?.day, let last = days.last?.day {
                    Text("\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .help("Previous week")
                Button { weekOffset = 0 } label: { Text("This week") }.disabled(weekOffset == 0)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset >= 0).help("Next week")
            }
            HStack(spacing: 8) {
                ForEach(Array(zip(days, verdicts)), id: \.0.id) { day, verdict in
                    dayCard(day, verdict: verdict)
                }
            }
            HStack(spacing: 10) {
                Text(weekEmoji(total: total, overworkDays: overworkDays, heavyDays: heavyDays)).font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekTitle(total: total, overworkDays: overworkDays, heavyDays: heavyDays)).font(.headline)
                    Text(weekDetail(total: total, overtime: overtime, rated: rated))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background((overworkDays > 0 ? Palette.focus : Color.gray).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func dayCard(_ day: DaySummary, verdict: DayVerdict) -> some View {
        let isToday = Calendar.current.isDateInToday(day.day)
        let isFuture = day.day > Date()
        return VStack(spacing: 3) {
            Text(day.day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold))
            Text(isFuture ? "·" : verdict.emoji).font(.system(size: 26)).frame(height: 32)
            Text(isFuture ? " " : verdict.title).font(.caption2.weight(.semibold))
                .foregroundStyle(verdict.color).lineLimit(1).minimumScaleFactor(0.8)
            Text(day.coins > 0 ? Format.duration(minutes: day.coins) : "–")
                .font(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if day.coins > settings.dailyGoal {
                Text("+\(Format.duration(minutes: day.coins - settings.dailyGoal))")
                    .font(.caption2).foregroundStyle(verdict.color).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(" ").font(.caption2)
            }
            HStack(spacing: 2) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(Palette.rest)
                Text(day.breakMinutes > 0 ? "\(day.breakMinutes)" : "–").monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Image(systemName: "laptopcomputer")
                Text(activity.minutes(on: day.day) > 0 ? Format.short(minutes: activity.minutes(on: day.day)) : "–").monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            .help("Time at the Mac that day")
            Text(DayFeeling.emoji(day.rating) ?? "–")
                .font(.system(size: 14)).foregroundStyle(.secondary).frame(height: 18)
                .help(day.rating.map { "You rated this day: \(DayFeeling.names[$0 - 1])" } ?? "Not rated")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(verdict.color.opacity(day.coins > 0 ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isToday ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5))
        .opacity(isFuture ? 0.45 : 1)
        .help("\(verdict.title): \(Format.duration(minutes: day.coins)) of focus, \(day.breakMinutes) min of breaks")
    }

    private func weekEmoji(total: Int, overworkDays: Int, heavyDays: Int) -> String {
        if total == 0 { return "😴" }
        if overworkDays > 0 { return "🥵" }
        if heavyDays >= 2 { return "😮‍💨" }
        return "😄"
    }

    private func weekTitle(total: Int, overworkDays: Int, heavyDays: Int) -> String {
        if total == 0 { return "No focus time this week" }
        if overworkDays > 0 {
            return "Overworked: \(overworkDays) day\(overworkDays == 1 ? "" : "s") past \(Format.duration(minutes: settings.dailyGoal * 10 / 6))"
        }
        if heavyDays >= 2 { return "Heavy week: \(heavyDays) long days" }
        return "Healthy week"
    }

    private func weekDetail(total: Int, overtime: Int, rated: [Int]) -> String {
        var parts = ["Focus \(Format.duration(minutes: total))"]
        parts.append(overtime > 0 ? "overtime \(Format.duration(minutes: overtime))" : "no overtime")
        if !rated.isEmpty {
            parts.append(String(format: "your rating %.1f of 5", Double(rated.reduce(0, +)) / Double(rated.count)))
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: At the Mac

    /// Today's time at the computer next to the focus that was logged.
    private var activitySection: some View {
        let picture = ActivityPicture(atMac: activity.minutes(on: engine.today), focus: engine.todayCoins)
        return VStack(alignment: .leading, spacing: 10) {
            Text("At the Mac today").font(.headline)
            HStack(spacing: 12) {
                tile("At the Mac", Format.short(minutes: picture.atMac), "keyboard or mouse")
                tile("In focus", Format.short(minutes: picture.focus),
                     picture.atMac > 0 ? "\(Int((picture.share * 100).rounded()))% of Mac time" : "logged with the timer")
                tile("Without a timer", Format.short(minutes: picture.untimed), "nothing logged")
                tile("Breaks", Format.short(minutes: engine.todayBreakMinutes), "logged today")
            }
            Text("Counted from keyboard and mouse input only, on this Mac, while the app is open. "
                 + "A pause in input of up to five minutes still counts; a call or a video without touching the Mac does not. "
                 + "The laptop row under each day of the week shows the same number for that day.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Summary tiles

    private var tiles: some View {
        let live = engine.liveCoins
        let best = ledger.bestDay()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("Today", "\(engine.todayCoins)", Format.duration(minutes: engine.todayCoins))
            tile("This week", "\(ledger.coinsThisWeek() + live)", Format.duration(minutes: ledger.coinsThisWeek() + live))
            tile("This month", "\(ledger.coinsThisMonth() + live)", Format.duration(minutes: ledger.coinsThisMonth() + live))
            tile("All time", "\(ledger.allTimeCoins + live)", Format.duration(minutes: ledger.allTimeCoins + live))
            tile("Streak", "\(ledger.streak(extraToday: live))", "days in a row")
            tile("Sessions today", "\(engine.todaySessions)", "focus sessions")
            tile("Daily average", "\(average)", "last \(range) days")
            tile("Best day", best.map { "\($0.coins)" } ?? "–",
                 best.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "no data yet")
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Chart

    /// Daily totals for the selected range, with the open session added to today.
    private var totals: [DayTotal] {
        var days = ledger.dailyTotals(lastDays: range)
        if let last = days.indices.last { days[last].coins += engine.liveCoins }
        return days
    }

    private var average: Int {
        let days = totals
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.coins } / days.count
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Focus minutes per day").font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            }
            Chart {
                ForEach(totals) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.coins))
                        .foregroundStyle(day.coins >= settings.dailyGoal ? Palette.rest : Palette.coin)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", settings.dailyGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("goal \(settings.dailyGoal)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 220)
            Text("Green days reached the daily focus goal.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Today's sessions

    private var todayList: some View {
        let entries = ledger.entries(on: engine.today).sorted { $0.start > $1.start }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today's sessions").font(.headline)
            if let session = engine.session {
                row(time: "\(Format.time(session.start)) – now", base: session.baseMinutes,
                    extensions: session.extensions, coins: session.earnedMinutes, open: true)
            }
            if entries.isEmpty && engine.session == nil {
                Text("Nothing yet. Start a focus session from the menu bar.")
                    .foregroundStyle(.secondary).font(.callout)
            }
            ForEach(entries) { entry in
                row(time: "\(Format.time(entry.start)) – \(Format.time(entry.end))", base: entry.baseMinutes,
                    extensions: entry.extensions, coins: entry.coins, open: false)
                    .contextMenu {
                        Button("Delete session", role: .destructive) { ledger.remove(entry) }
                    }
            }
        }
    }

    private func row(time: String, base: Int, extensions: [Int], coins: Int, open: Bool) -> some View {
        HStack {
            Text(time).monospacedDigit().frame(width: 150, alignment: .leading)
            Text(plan(base: base, extensions: extensions)).foregroundStyle(.secondary)
            if open {
                Text("in progress").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.focus.opacity(0.2), in: Capsule())
            }
            Spacer()
            Text("\(coins) min").monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func plan(base: Int, extensions: [Int]) -> String {
        guard !extensions.isEmpty else { return "\(base) min" }
        return ([String(base)] + extensions.map(String.init)).joined(separator: " + ") + " min"
    }
}
