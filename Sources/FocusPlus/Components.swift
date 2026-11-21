import SwiftUI
import AppKit
import WidgetUI

/// The app's own palette: cool tones for focus, fresh greens for rest, warm amber for energy.
enum Palette {
    static let coin = Color(red: 1.00, green: 0.72, blue: 0.20)
    /// Pause, stop-like and "over the limit" accents.
    static let focus = Color(red: 1.00, green: 0.36, blue: 0.40)
    static let rest = Color(red: 0.18, green: 0.83, blue: 0.68)
    /// Start and resume buttons.
    static let start = Color(red: 0.25, green: 0.48, blue: 1.00)
    // The three gauges.
    static let ringFocus = Color(red: 0.47, green: 0.40, blue: 1.00)
    static let ringRest = Color(red: 0.18, green: 0.83, blue: 0.68)
    static let ringEnergy = Color(red: 1.00, green: 0.72, blue: 0.20)

    static func tint(for phase: TimerEngine.Phase) -> Color {
        switch phase {
        case .focus: return ringFocus
        case .shortBreak, .longBreak: return rest
        case .idle: return .secondary
        }
    }
}

/// Coin icon with an amount, e.g. "● 87".
struct CoinLabel: View {
    var amount: Int
    var font: Font = .body

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "centsign.circle.fill").foregroundStyle(Palette.coin)
            Text("\(amount)").monospacedDigit()
        }
        .font(font)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) coins")
    }
}

/// The mode switcher: a pill showing the current mode and its limits. Clicking it opens the list of modes.
struct ModePicker: View {
    @ObservedObject var settings: AppSettings
    @State private var open = false

    static func tint(_ mode: WorkMode) -> Color {
        switch mode {
        case .light: return Palette.ringRest
        case .moderate: return Palette.ringFocus
        case .hardcore: return Palette.focus
        }
    }

    var body: some View {
        let mode = settings.currentMode
        let tint = Self.tint(mode)
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.symbol).foregroundStyle(tint)
                Text(mode.title).fontWeight(.semibold)
                Text(settings.settings(for: mode).summary).foregroundStyle(.secondary)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Switch between Light, Moderate and Hardcore")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(WorkMode.allCases) { option in
                    Button {
                        settings.currentMode = option
                        open = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol).foregroundStyle(Self.tint(option)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title).fontWeight(.semibold)
                                Text(settings.settings(for: option).summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 16)
                            Image(systemName: "checkmark").opacity(option == mode ? 1 : 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Self.tint(option).opacity(option == mode ? 0.16 : 0)))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.vertical, 2)
                Button {
                    open = false
                    AppWindows.showSettings()
                } label: {
                    Label("Edit modes…", systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .frame(width: 250)
        }
    }
}

/// Tall rectangular button used for the main actions.
struct TallButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var height: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color.primary.opacity(0.14)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .modifier(TallHover(pressed: configuration.isPressed))
    }
}

private struct TallHover: ViewModifier {
    var pressed: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(pressed ? -0.08 : (hovering ? 0.06 : 0))
            .scaleEffect(pressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .handCursor(hovering: $hovering)
    }
}

/// A wedge of a clock face, starting at 12 o'clock and running clockwise.
struct ClockWedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction < 0.999 else {
            path.addEllipse(in: rect)
            return path
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * max(0, fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Press feedback shared by the round buttons.
struct RoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLift(pressed: configuration.isPressed, shape: Circle(), lift: 1.07) { configuration.label }
    }
}

/// Grows and brightens a button a little under the pointer, and dips it when pressed.
struct HoverLift<Content: View, Hit: Shape>: View {
    var pressed: Bool
    var shape: Hit
    var lift: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        content()
            .brightness(pressed ? -0.1 : (hovering ? 0.07 : 0))
            .scaleEffect(pressed ? 0.94 : (hovering ? lift : 1))
            .shadow(color: .black.opacity(hovering && !pressed ? 0.35 : 0), radius: 6, y: 3)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .contentShape(shape)
            .handCursor(hovering: $hovering, enabled: enabled)
    }
}

extension View {
    /// Tracks the pointer and shows the pointing hand over the view, like a link.
    func handCursor(hovering: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(HandCursor(hovering: hovering, enabled: enabled))
    }
}

private struct HandCursor: ViewModifier {
    @Binding var hovering: Bool
    var enabled: Bool

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                let now = inside && enabled
                guard now != hovering else { return }
                hovering = now
                if now { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            // A button can vanish under the pointer, for example when the timer starts. Give the arrow back.
            .onDisappear {
                if hovering { NSCursor.pop(); hovering = false }
            }
    }
}

extension Palette {
    /// Focus lengths run along a cool spectrum, cyan to pink, so each button is easy to tell apart.
    static func extensionColor(minutes: Int) -> Color {
        switch minutes {
        case ..<8: return Color(red: 0.13, green: 0.80, blue: 0.93)    // cyan
        case ..<13: return Color(red: 0.23, green: 0.60, blue: 1.00)   // blue
        case ..<23: return Color(red: 0.44, green: 0.44, blue: 1.00)   // indigo
        case ..<38: return Color(red: 0.66, green: 0.36, blue: 0.98)   // violet
        case ..<53: return Color(red: 0.85, green: 0.30, blue: 0.92)   // magenta
        default: return Color(red: 0.97, green: 0.28, blue: 0.60)      // pink
        }
    }
}

/// Round clock-face buttons for focus time: they start a session of that length,
/// or with `adds` extend the one that is running. Each is filled for its share of an hour.
struct ExtendButtons: View {
    var options: [Int]
    var adds = true
    var highlighted: Int? = nil
    var prominent = false
    /// When set, a right click offers to log that much focus as already done.
    var onLog: ((Int) -> Void)? = nil
    var action: (Int) -> Void

    var body: some View {
        let size = RoundButtonRow<EmptyView>.fittingSize(count: options.count, prominent: prominent)
        RoundButtonRow(items: options, size: size) { minutes in
            let color = Palette.extensionColor(minutes: minutes)
            Button { action(minutes) } label: {
                ZStack {
                    Circle().fill(color.opacity(0.16))
                    ClockWedge(fraction: Double(minutes) / 60)
                        .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.70)],
                                             startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(minutes == highlighted ? Color.white : color,
                                          lineWidth: size * (minutes == highlighted ? 0.08 : 0.06))
                    Text(adds ? "+\(minutes)" : "\(minutes)")
                        .font(.system(size: size * (adds ? 0.31 : 0.36), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1.2, y: 0.5)
                }
                .frame(width: size, height: size)
            }
            .buttonStyle(RoundPressStyle())
            .help(adds ? "Add \(minutes) minutes to this session" : "Start \(minutes) minutes of focus")
            .accessibilityLabel(adds ? "Add \(minutes) minutes" : "Start \(minutes) minutes of focus")
            .contextMenu {
                if let onLog {
                    Button("Log \(minutes) min of focus as already done") { onLog(minutes) }
                }
            }
        }
    }
}

/// How a break of a given length is drawn and named, taken from the person's break presets.
struct BreakKind: Equatable {
    var name: String
    var symbols: [String]
    var color: Color

    /// Rest colours run mint to orange with the length of the break, clearly apart from the cool focus colours.
    private static let ramp: [Color] = [
        Color(red: 0.18, green: 0.83, blue: 0.75), Color(red: 0.20, green: 0.83, blue: 0.55),
        Color(red: 0.55, green: 0.86, blue: 0.25), Color(red: 0.98, green: 0.75, blue: 0.16),
        Color(red: 0.98, green: 0.55, blue: 0.24),
    ]

    init(minutes: Int, settings: AppSettings = .shared) {
        let lengths = settings.breakOptions
        let preset = settings.breakPreset(minutes: minutes)
        name = preset?.name.isEmpty == false ? preset!.name : "Break"
        symbols = Array(repeating: preset?.symbol ?? "cup.and.saucer.fill", count: min(3, max(1, preset?.count ?? 1)))
        // Position among the configured lengths picks the colour, so five presets use the whole ramp.
        let index = lengths.lastIndex { $0 <= minutes } ?? 0
        let position = lengths.count > 1 ? Double(index) / Double(lengths.count - 1) : 0
        color = Self.ramp[min(Self.ramp.count - 1, Int((position * Double(Self.ramp.count - 1)).rounded()))]
    }
}

/// Break buttons: start a break of that many minutes, or with `adds` lengthen the one that is running.
/// 5 minutes is one coffee, 10 is two, 15 is three, 30 is a walk and 60 is a meal.
struct BreakButtons: View {
    var options: [Int]
    var highlighted: Int? = nil
    /// True when the buttons lengthen a running break instead of starting one.
    var adds = false
    var prominent = false
    /// When set, a right click offers to log a break of that length as already taken.
    var onLog: ((Int) -> Void)? = nil
    var action: (Int) -> Void

    var body: some View {
        let size = RoundButtonRow<EmptyView>.fittingSize(count: options.count, prominent: prominent)
        RoundButtonRow(items: options, size: size) { minutes in
            let kind = BreakKind(minutes: minutes)
            let strong = minutes == highlighted
            Button { action(minutes) } label: {
                ZStack {
                    Circle().fill(kind.color.opacity(strong ? 0.55 : 0.18))
                    Circle().strokeBorder(kind.color, lineWidth: size * 0.055)
                    contourIcons(kind, size: size)
                    Text(adds ? "+\(minutes)" : "\(minutes)")
                        .font(.system(size: size * (adds ? 0.27 : 0.31), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .offset(y: size * 0.15)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                .frame(width: size, height: size)
            }
            .buttonStyle(RoundPressStyle())
            .help(adds ? "Add \(minutes) minutes to the break" : "\(kind.name), \(minutes) min")
            .accessibilityLabel(adds ? "Add \(minutes) minutes to the break" : "\(minutes) minute break, \(kind.name)")
            .contextMenu {
                if let onLog {
                    Button("Log a \(minutes) min break as already taken") { onLog(minutes) }
                }
            }
        }
    }

    /// Places the symbols upright on a shallow arc in the upper half, symmetric about the vertical axis.
    /// The cup symbol has its handle on the right, so each one is nudged left to sit optically centred.
    private func contourIcons(_ kind: BreakKind, size: CGFloat) -> some View {
        let symbols = kind.symbols
        let single = symbols.count == 1
        let radius = size * 0.25
        let step = 50.0
        let isCup = symbols.first == "cup.and.saucer.fill" || symbols.first == "mug.fill"
        let fontSize = size * (single ? 0.23 : 0.15)
        return ZStack {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                let tilt = (Double(index) - Double(symbols.count - 1) / 2) * step
                let angle = (tilt - 90) * .pi / 180
                Image(systemName: symbol)
                    .font(.system(size: fontSize, weight: .semibold))
                    .frame(width: fontSize * 1.4, height: fontSize * 1.2)
                    .offset(x: radius * cos(angle) - (isCup ? fontSize * 0.04 : 0),
                            y: radius * sin(angle) + (single ? size * 0.02 : 0))
            }
        }
    }
}

/// Lays round buttons out in rows of at most six, in equal cells across the full width,
/// so every row is centred and the columns of different rows line up.
struct RoundButtonRow<Content: View>: View {
    var items: [Int]
    var size: CGFloat
    @ViewBuilder var content: (Int) -> Content

    /// Button diameter that leaves a comfortable gap however many buttons share the row.
    /// Five fit at full size; six shrink a little instead of crowding.
    static func fittingSize(count: Int, prominent: Bool) -> CGFloat {
        let full: CGFloat = prominent ? 76 : 64
        let rowWidth: CGFloat = prominent ? 464 : 368
        let perRow = CGFloat(min(max(count, 1), 6))
        let gap: CGFloat = prominent ? 14 : 10
        return min(full, (rowWidth / perRow - gap).rounded(.down))
    }

    var body: some View {
        let perRow = 6
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { content($0).frame(maxWidth: .infinity) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One round gauge: a dim track with a bright rounded arc. Past 100% the arc laps itself in a lighter shade.
private struct Gauge<Center: View>: View {
    var share: Double
    var color: Color
    var size: CGFloat
    @ViewBuilder var center: () -> Center

    var body: some View {
        let width = size * 0.105
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: width)
            Circle().trim(from: 0, to: max(0.002, min(share, 1)))
                .stroke(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if share > 1 {
                Circle().trim(from: 0, to: min(share - 1, 1))
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: width * 0.35, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center().padding(width + 4)
        }
        .padding(width / 2)
        .frame(width: size, height: size)
    }
}

/// "Focus energy": the balance of the day as three gauges.
/// Focus done against the daily goal, rest taken against the rest that is due,
/// and the energy left (work drains it, breaks give it back) with the mood face in its centre.
struct EnergyCard: View {
    var wellbeing: Wellbeing
    var large = false

    var body: some View {
        let mood = wellbeing.mood
        let size: CGFloat = large ? 112 : 92
        VStack(spacing: large ? 12 : 9) {
            HStack(alignment: .top, spacing: 0) {
                column("Focus", detail: "of \(Format.short(minutes: max(wellbeing.goal, 1)))", color: Palette.ringFocus) {
                    Gauge(share: wellbeing.focusShare, color: Palette.ringFocus, size: size) {
                        value(Format.short(minutes: wellbeing.focusMinutes), size: size)
                    }
                }
                column("Rest", detail: "of \(Format.short(minutes: wellbeing.restGoal))", color: Palette.ringRest) {
                    Gauge(share: wellbeing.restShareOfDay, color: Palette.ringRest, size: size) {
                        value(Format.short(minutes: wellbeing.breakMinutes), size: size)
                    }
                }
                column("Energy", detail: "\(Int((wellbeing.energy * 100).rounded()))%", color: Palette.ringEnergy) {
                    Gauge(share: wellbeing.energy, color: Palette.ringEnergy, size: size) {
                        Text(mood.emoji).font(.system(size: size * 0.36))
                    }
                }
            }
            Text(mood == .idle ? wellbeing.advice : "\(mood.title). \(wellbeing.advice)")
                .font(large ? .callout : .caption)
                .foregroundStyle(mood == .overworked ? Palette.focus : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size * 0.21, weight: .bold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
    }

    private func column<Content: View>(_ title: String, detail: String, color: Color,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            content()
            HStack(spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundStyle(color)
                Text(detail).foregroundStyle(.secondary)
            }
            .font(large ? .callout : .caption).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The person's own verdict on the day: five faces, changeable at any time.
enum DayFeeling {
    static let emojis = ["😫", "😕", "😐", "🙂", "🤩"]
    static let names = ["Rough", "Below par", "Okay", "Good", "Great"]

    static func emoji(_ rating: Int?) -> String? {
        guard let rating, (1...5).contains(rating) else { return nil }
        return emojis[rating - 1]
    }
}

struct DayRatingRow: View {
    @ObservedObject var ledger: Ledger
    var day: Date
    var prompt = "How does today feel?"
    var large = false

    var body: some View {
        let current = ledger.rating(on: day)
        let size: CGFloat = large ? 54 : 46
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(prompt).font(.callout.weight(.medium))
                if let current {
                    Text("· \(DayFeeling.names[current - 1])").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    let selected = value == current
                    Button {
                        ledger.setRating(selected ? nil : value, on: day)
                    } label: {
                        Text(DayFeeling.emojis[value - 1])
                            .font(.system(size: size * 0.56))
                            .frame(width: size, height: size)
                            .background(Circle().fill(Color.primary.opacity(selected ? 0.20 : 0.07)))
                            .overlay(Circle().strokeBorder(selected ? Palette.ringEnergy : .clear, lineWidth: 2.5))
                            .saturation(current == nil || selected ? 1 : 0.25)
                            .opacity(current == nil || selected ? 1 : 0.6)
                            .scaleEffect(selected ? 1.08 : 1)
                    }
                    .buttonStyle(RoundPressStyle())
                    .help(DayFeeling.names[value - 1])
                    .accessibilityLabel("\(DayFeeling.names[value - 1]) day")
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: current)
    }
}

/// Today's coins on a scale against the daily goal.
/// Past the goal the scale stretches: the goal becomes a marker and the surplus is drawn in green.
struct GoalBar: View {
    var coins: Int
    var goal: Int
    var large = false

    private var safeGoal: Int { max(goal, 1) }
    private var percent: Int { Int((Double(coins) / Double(safeGoal) * 100).rounded()) }
    private var surplus: Int { max(0, coins - safeGoal) }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 8 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                CoinLabel(amount: coins, font: large ? .title2.weight(.semibold) : .headline)
                Text("of \(safeGoal)").foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(large ? .title2.weight(.semibold) : .headline).monospacedDigit()
                    .foregroundStyle(surplus > 0 ? Palette.rest : .primary)
            }
            scale.frame(height: large ? 14 : 10)
            HStack {
                Text("\(Format.duration(minutes: coins)) of \(Format.duration(minutes: safeGoal))")
                Spacer()
                if surplus > 0 {
                    Label("+\(surplus) over goal (\(Format.duration(minutes: surplus)))",
                          systemImage: "arrow.up.right.circle.fill")
                        .foregroundStyle(Palette.rest)
                } else if coins == safeGoal {
                    Label("Goal reached", systemImage: "checkmark.seal.fill").foregroundStyle(Palette.rest)
                } else {
                    Text("\(Format.duration(minutes: safeGoal - coins)) to go")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var scale: some View {
        GeometryReader { geo in
            let total = Double(max(coins, safeGoal))
            let width = geo.size.width
            let goalX = width * Double(safeGoal) / total
            let doneX = width * Double(min(coins, safeGoal)) / total
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if surplus > 0 {
                    Capsule().fill(Palette.rest).frame(width: width)
                }
                if coins > 0 {
                    Capsule().fill(Palette.coin).frame(width: max(doneX, geo.size.height))
                }
                if surplus > 0 {
                    // Goal marker: everything to its right is surplus.
                    Rectangle().fill(.background).frame(width: 2).offset(x: goalX - 1)
                }
            }
        }
    }
}

/// Today at a glance, drawn the same way as the desktop widget: one big ring on the left, two bars on the right.
/// Sits in its own card so it does not blend with the round timer buttons above it.
struct TodayCard: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ledger: Ledger

    var body: some View {
        let wellbeing = engine.wellbeing
        var snapshot = WidgetBridge.makeSnapshot(engine: engine, settings: settings, ledger: ledger, now: Date())
        // The countdown is already on screen above, so the ring here always shows the share of the day's goal.
        snapshot.phase = .idle
        snapshot.runState = .idle
        return VStack(spacing: 10) {
            FocusWidgetView(snapshot: snapshot, date: Date(), layout: .medium)
                .frame(height: 122)
            Text(wellbeing.advice)
                .font(.caption)
                .foregroundStyle(wellbeing.mood == .overworked ? Palette.focus : Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(focusWidgetBackground))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
