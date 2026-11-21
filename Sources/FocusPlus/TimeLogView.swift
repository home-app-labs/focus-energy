import SwiftUI

/// The day's time log: every focus session and break, newest first, with a way to delete
/// what should not be there and to add what was forgotten.
struct TimeLogView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var ledger: Ledger
    @ObservedObject var settings: AppSettings

    @State private var dayOffset = 0

    private enum Item: Identifiable {
        case focus(FocusEntry)
        case rest(BreakEntry)

        var id: UUID {
            switch self {
            case .focus(let entry): return entry.id
            case .rest(let entry): return entry.id
            }
        }

        var start: Date {
            switch self {
            case .focus(let entry): return entry.start
            case .rest(let entry): return entry.start
            }
        }
    }

    private var day: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: engine.today) ?? engine.today
    }

    private var items: [Item] {
        (ledger.entries(on: day).map(Item.focus) + ledger.breaks(on: day).map(Item.rest))
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            totals
            Divider()
            if items.isEmpty && !(dayOffset == 0 && engine.phase != .idle) {
                Spacer()
                Text("Nothing logged on this day.").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        if dayOffset == 0 { runningRow }
                        ForEach(items) { row($0) }
                    }
                }
            }
            Divider()
            addBar
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Button { dayOffset -= 1 } label: { Image(systemName: "chevron.left") }.help("Previous day")
            Spacer()
            VStack(spacing: 1) {
                Text(dayOffset == 0 ? "Today" : dayOffset == -1 ? "Yesterday" : day.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(day.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dayOffset += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(dayOffset >= 0).help("Next day")
        }
    }

    private var totals: some View {
        let focus = ledger.coins(on: day) + (dayOffset == 0 ? engine.liveCoins : 0)
        let rest = ledger.breakMinutes(on: day) + (dayOffset == 0 ? engine.liveBreakMinutes : 0)
        return HStack(spacing: 0) {
            total("Focus", Format.short(minutes: focus), Palette.ringFocus)
            total("Rest", Format.short(minutes: rest), Palette.ringRest)
            total("Entries", "\(items.count)", .secondary)
        }
    }

    private func total(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The timer that is running now; it joins the log when it ends.
    @ViewBuilder private var runningRow: some View {
        if engine.phase == .focus, let session = engine.session {
            rowBody(symbol: "bolt.fill", color: Palette.ringFocus, title: "Focus, in progress",
                    time: "\(Format.time(session.start)) – now", minutes: session.earnedMinutes, onDelete: nil)
        } else if engine.phase.isBreak {
            rowBody(symbol: "cup.and.saucer.fill", color: Palette.ringRest, title: "\(engine.breakName), in progress",
                    time: "now", minutes: engine.liveBreakMinutes, onDelete: nil)
        }
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        switch item {
        case .focus(let entry):
            let plan = entry.extensions.isEmpty ? "Focus"
                : "Focus " + ([String(entry.baseMinutes)] + entry.extensions.map(String.init)).joined(separator: " + ")
            rowBody(symbol: "bolt.fill", color: Palette.ringFocus, title: plan,
                    time: "\(Format.time(entry.start)) – \(Format.time(entry.end))", minutes: entry.minutes) {
                ledger.remove(entry)
            }
        case .rest(let entry):
            let kind = BreakKind(minutes: entry.minutes)
            rowBody(symbol: kind.symbols[0], color: kind.color, title: entry.name ?? kind.name,
                    time: "\(Format.time(entry.start)) – \(Format.time(entry.start.addingTimeInterval(Double(entry.minutes * 60))))",
                    minutes: entry.minutes) {
                ledger.removeBreak(entry)
            }
        }
    }

    private func rowBody(symbol: String, color: Color, title: String, time: String, minutes: Int,
                         onDelete: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.short(minutes: minutes)).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete this entry")
            } else {
                Image(systemName: "trash").opacity(0)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Adds something that already happened. It is logged as ending now.
    private var addBar: some View {
        HStack {
            Text("Forgot to start a timer?").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(settings.startOptions, id: \.self) { minutes in
                    Button("\(minutes) min") { engine.logPastFocus(minutes: minutes) }
                }
            } label: { Label("Log focus", systemImage: "bolt.fill") }
            .fixedSize()
            Menu {
                ForEach(settings.breakOptions, id: \.self) { minutes in
                    Button("\(BreakKind(minutes: minutes).name), \(minutes) min") { engine.logPastBreak(minutes: minutes) }
                }
            } label: { Label("Log break", systemImage: "cup.and.saucer.fill") }
            .fixedSize()
        }
        .disabled(dayOffset != 0)
        .help(dayOffset == 0 ? "Logged as ending now" : "Past entries can be added for today only")
    }
}
