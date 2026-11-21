import SwiftUI
import WidgetKit

/// Small pieces used on the lock screen and on the watch face.
struct CompactStatus {
    let snapshot: WidgetSnapshot
    let date: Date

    init(_ snapshot: WidgetSnapshot, at date: Date) {
        self.snapshot = snapshot.resolved(at: date)
        self.date = date
    }

    var point: WidgetSnapshot.Point { snapshot.point(at: date) ?? WidgetSnapshot.placeholder.points[0] }
    var goalShare: Double { Double(point.coins) / Double(max(snapshot.goal, 1)) }
    var percent: Int { Int((goalShare * 100).rounded()) }

    /// Share of the ring to fill: time left while a timer runs, share of the daily goal otherwise.
    var fraction: Double {
        switch snapshot.runState {
        case .running:
            guard let end = snapshot.endsAt, snapshot.plannedSeconds > 0 else { return 0 }
            return min(1, max(0, end.timeIntervalSince(date) / snapshot.plannedSeconds))
        case .paused:
            return snapshot.plannedSeconds > 0 ? min(1, snapshot.remainingSeconds / snapshot.plannedSeconds) : 0
        case .finished: return 1
        case .idle: return min(1, goalShare)
        }
    }

    var symbol: String {
        switch (snapshot.phase, snapshot.runState) {
        case (_, .finished): return "bell.badge.fill"
        case (_, .paused): return "pause.fill"
        case (.focus, _): return "bolt.fill"
        case (.rest, _): return "cup.and.saucer.fill"
        default: return "play.fill"
        }
    }

    var title: String {
        switch (snapshot.phase, snapshot.runState) {
        case (.focus, .finished): return "Focus done"
        case (_, .finished): return "Break is over"
        case (_, .paused): return "Paused"
        case (.focus, _): return "Focus"
        case (.rest, _): return "Break"
        default: return "Ready"
        }
    }

    var tint: Color {
        switch snapshot.phase {
        case .focus: return Color(red: 0.47, green: 0.40, blue: 1.00)
        case .rest: return Color(red: 0.18, green: 0.83, blue: 0.68)
        case .idle: return Color(red: 1.00, green: 0.72, blue: 0.20)
        }
    }

    /// The countdown while running, otherwise the share of the goal.
    @ViewBuilder var mainText: some View {
        if snapshot.runState == .running, let end = snapshot.endsAt, end > date {
            Text(timerInterval: date...end, countsDown: true)
        } else if snapshot.runState == .finished {
            Text("Done")
        } else {
            Text("\(percent)%")
        }
    }

    static func short(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var focusLine: String { "\(Self.short(point.coins)) of \(Self.short(snapshot.goal))" }
    var restLine: String { "rest \(Self.short(point.breakMinutes)) of \(Self.short(point.recommendedRest))" }
}

/// Round gauge for the lock screen and circular watch complications.
struct CircularStatusView: View {
    let status: CompactStatus

    var body: some View {
        Gauge(value: status.fraction) {
            Image(systemName: status.symbol)
        } currentValueLabel: {
            if let minutes = status.snapshot.minutesLeft(at: status.date) {
                Text("\(minutes)")
            } else {
                Text(status.point.moodEmoji)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(status.tint)
    }
}

/// Three lines for the lock screen and rectangular watch complications.
struct RectangularStatusView: View {
    let status: CompactStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                Text(status.title)
                Spacer(minLength: 2)
                status.mainText.monospacedDigit().multilineTextAlignment(.trailing)
            }
            .font(.headline)
            .widgetAccentable()
            Text("\(status.point.moodEmoji) \(status.focusLine)").font(.caption)
            Text(status.restLine).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
