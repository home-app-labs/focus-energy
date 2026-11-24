import SwiftUI

/// The three widget layouts.
public enum WidgetLayout {
    case small, medium, large
    /// Just the round status, at the given diameter. Used by the phone and watch apps.
    case ring(CGFloat)
    /// The two detail blocks on their own: focus time, then energy and rest.
    case details
}

enum WidgetPalette {
    static let coin = Color(red: 1.00, green: 0.72, blue: 0.20)
    static let focus = Color(red: 0.47, green: 0.40, blue: 1.00)
    static let rest = Color(red: 0.18, green: 0.83, blue: 0.68)
    /// Energy by level, as in the app: green from half up, orange from a quarter, red below.
    static func energy(_ level: Double) -> Color {
        switch level {
        case 0.50...: return rest
        case 0.25...: return Color(red: 0.96, green: 0.58, blue: 0.16)
        default: return Color(red: 1.00, green: 0.36, blue: 0.40)
        }
    }
    /// The idle ring and its play mark, as on the Start button in the app.
    static let start = Color(red: 0.25, green: 0.48, blue: 1.00)
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
}

/// The widget's content for one moment in time.
public struct FocusWidgetView: View {
    var snapshot: WidgetSnapshot
    var date: Date
    var layout: WidgetLayout

    public init(snapshot: WidgetSnapshot, date: Date, layout: WidgetLayout) {
        self.snapshot = snapshot.resolved(at: date)
        self.date = date
        self.layout = layout
    }

    private var point: WidgetSnapshot.Point {
        snapshot.point(at: date) ?? WidgetSnapshot.placeholder.points[0]
    }

    private var tint: Color {
        switch snapshot.phase {
        case .focus: return WidgetPalette.focus
        case .rest: return WidgetPalette.rest
        case .idle: return WidgetPalette.start
        }
    }

    private var goalShare: Double { Double(point.coins) / Double(max(snapshot.goal, 1)) }
    private var percentText: String { "\(Int((goalShare * 100).rounded()))%" }

    public var body: some View {
        Group {
            switch layout {
            case .small: small
            case .medium: medium
            case .large: large
            case .ring(let size): ring(size: size)
            case .details:
                VStack(alignment: .leading, spacing: 12) {
                    goalBlock
                    moodBlock
                }
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Layouts

    private var small: some View {
        VStack(spacing: 6) {
            ring(size: 96)
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(WidgetPalette.focus).font(.system(size: 12))
                Text("\(hours(point.coins)) · \(percentText)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// The big round status on the left (percentage or countdown under the phase mark), details on the right.
    private var medium: some View {
        HStack(spacing: 16) {
            ring(size: 118)
            VStack(alignment: .leading, spacing: 10) {
                goalBlock
                moodBlock
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var large: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                ring(size: 126)
                VStack(alignment: .leading, spacing: 12) {
                    goalBlock
                    moodBlock
                }
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 10)
            Text(point.advice).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Spacer(minLength: 10)
            Divider().overlay(.white.opacity(0.15))
            Spacer(minLength: 10)
            Text("This week").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                ForEach(snapshot.week) { day in
                    VStack(spacing: 4) {
                        Text(day.label).font(.system(size: 10, weight: .semibold))
                        Text(day.isFuture ? "·" : day.emoji).font(.system(size: 21)).frame(height: 26)
                        Text(day.coins > 0 ? hours(day.coins) : "–")
                            .font(.system(size: 10, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(day.isToday ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                    .opacity(day.isFuture ? 0.45 : 1)
                }
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pieces

    /// The ring: time left while a timer runs, share of the daily goal when idle.
    private func ring(size: CGFloat) -> some View {
        let line = size * 0.09
        return ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: ringFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                // Same mark as in the app's ring: bolt in focus, cup on a break, play when nothing runs.
                Image(systemName: symbol).font(.system(size: size * 0.12, weight: .semibold)).foregroundStyle(tint)
                centerText
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                Text(caption).font(.system(size: size * 0.10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1).minimumScaleFactor(0.6)
                // This line sits low in the circle, where there is less width than across the middle.
                .frame(maxWidth: size * 0.60)
            }
            .padding(.horizontal, line + 4)
        }
        .frame(width: size, height: size)
    }

    private var ringFraction: Double {
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

    private var symbol: String {
        switch (snapshot.phase, snapshot.runState) {
        case (_, .finished): return "bell.badge.fill"
        case (_, .paused): return "pause.fill"
        case (.focus, _): return "bolt.fill"
        case (.rest, _): return "cup.and.saucer.fill"
        default: return "play.fill"
        }
    }

    @ViewBuilder private var centerText: some View {
        switch snapshot.runState {
        case .running:
            if let end = snapshot.endsAt, end > date {
                Text(timerInterval: date...end, countsDown: true)
            } else {
                Text("00:00")
            }
        case .paused: Text(clock(snapshot.remainingSeconds))
        case .finished: Text(snapshot.phase == .focus ? "Done" : "Go")
        case .idle: Text(percentText)
        }
    }

    private var caption: String {
        switch (snapshot.phase, snapshot.runState) {
        case (.focus, .finished): return "extend or rest"
        case (_, .finished): return "break over"
        case (_, .paused): return "paused"
        case (.focus, _): return "focus"
        case (.rest, _): return "break"
        default: return "of goal"
        }
    }

    /// Focus time spent today against the limit.
    private var goalBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "bolt.fill").foregroundStyle(WidgetPalette.focus).font(.system(size: 13))
                Text(duration(point.coins)).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            bar(value: min(1, goalShare), color: WidgetPalette.focus)
            Text(point.coins > snapshot.goal
                    ? "+\(duration(point.coins - snapshot.goal)) over the \(duration(snapshot.goal)) limit"
                    : "\(point.coins / max(snapshot.defaultFocusMinutes, 1)) of \(max(1, snapshot.goal / max(snapshot.defaultFocusMinutes, 1))) sessions today · \(percentText) goal")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    /// Energy and rest.
    private var moodBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(point.moodEmoji).font(.system(size: 12))
                Text(point.moodTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text("\(Int((point.energy * 100).rounded()))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(WidgetPalette.energy(point.energy))
            }
            bar(value: point.energy, color: WidgetPalette.energy(point.energy))
            HStack(spacing: 3) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(WidgetPalette.rest)
                Text("rest \(short(point.breakMinutes)) of \(short(point.recommendedRest))")
            }
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    private func bar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(color).frame(width: max(geo.size.height, geo.size.width * value))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: 6)
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.up))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
                             : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    private func short(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func hours(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : String(format: "%.1fh", Double(minutes) / 60)
    }
}

public extension View {
    /// The dark card the widget content sits on. Used for in-app previews; the widget itself uses containerBackground.
    func focusWidgetCard(width: CGFloat, height: CGFloat) -> some View {
        self.padding(16)
            .frame(width: width, height: height)
            .background(focusWidgetBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

public var focusWidgetBackground: Color { WidgetPalette.background }
