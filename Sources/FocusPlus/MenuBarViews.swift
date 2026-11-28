import SwiftUI

/// What sits in the menu bar: the countdown while a timer runs, today's coins otherwise.
struct MenuBarLabel: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ledger: Ledger

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let text { Text(text).monospacedDigit() }
        }
    }

    /// Bolt while working, coffee cup on a break, pause sign when paused,
    /// bell when a decision is waiting, and a play button when ready to start.
    private var symbol: String {
        switch (engine.phase, engine.runState) {
        case (_, .finished): return "bell.badge.fill"
        case (_, .paused): return "pause.circle.fill"
        case (.focus, _): return "bolt.fill"
        case (.shortBreak, _), (.longBreak, _): return "cup.and.saucer.fill"
        default: return "play.circle"
        }
    }

    private var text: String? {
        switch engine.runState {
        case .running, .paused: return Format.clock(engine.remaining)
        case .finished: return engine.phase == .focus ? "Done" : "Break over"
        case .idle:
            // Ready: how much of today's goal is done, e.g. "21%".
            guard settings.showCoinsInMenuBar, !settings.currentMode.isDayOff else { return nil }
            let percent = Double(engine.todayCoins) / Double(max(settings.dailyGoal, 1)) * 100
            return "\(Int(percent.rounded()))%"
        }
    }
}

/// The panel that opens from the menu bar.
struct PopoverView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ledger: Ledger

    var body: some View {
        VStack(spacing: 14) {
            UpdateBanner()
            ModePicker(settings: settings)
            timerCard
            controls
            section(focusTitle) {
                if engine.phase == .focus {
                    ExtendButtons(options: settings.extensionOptions) { engine.extend(minutes: $0) }
                } else {
                    ExtendButtons(options: settings.startOptions, adds: false,
                                  onLog: { engine.logPastFocus(minutes: $0) }) {
                        engine.startFocus(minutes: $0)
                    }
                }
            }
            section(breakTitle) {
                if engine.phase.isBreak {
                    BreakButtons(options: settings.breakOptions, adds: true) { engine.extend(minutes: $0) }
                } else {
                    BreakButtons(options: settings.breakOptions,
                                 highlighted: engine.phase == .focus ? engine.nextBreakMinutes : nil,
                                 onLog: { engine.logPastBreak(minutes: $0) }) {
                        engine.startBreak(minutes: $0)
                    }
                }
            }
            Divider()
            DayRatingRow(ledger: ledger, day: engine.today)
            Divider()
            ActivityLine(activity: .shared, engine: engine)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 400)
    }

    private var focusTitle: String {
        switch (engine.phase, engine.runState) {
        case (.focus, .finished): return "Keep going"
        case (.focus, _): return "Extend this session"
        default: return "Start focus for"
        }
    }

    private var breakTitle: String {
        guard engine.phase.isBreak else { return "Take a break" }
        return engine.runState == .finished ? "A little more rest" : "Longer break"
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack {
            Circle().fill(Palette.tint(for: engine.phase)).frame(width: 8, height: 8)
            Text(statusTitle).font(.headline)
            if let session = engine.session {
                Text("· " + sessionSummary(session)).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusTitle: String {
        switch engine.runState {
        case .paused: return "\(engine.phaseTitle) · paused"
        case .finished: return engine.phase == .focus ? "Session complete" : "Break is over"
        default: return engine.phaseTitle
        }
    }

    private func sessionSummary(_ session: ActiveSession) -> String {
        let added = session.extensions.reduce(0, +)
        return added > 0 ? "\(session.baseMinutes) + \(added) = \(Format.duration(minutes: session.plannedMinutes))"
                         : "\(Format.duration(minutes: session.baseMinutes)) session"
    }

    /// The top card: the countdown inside a big ring on the left, today's focus and rest on the right,
    /// energy underneath. Same look as the desktop widget.
    private var timerCard: some View {
        let wellbeing = engine.wellbeing
        return VStack(spacing: 14) {
            header
            HStack(spacing: 18) {
                timerRing(size: 150)
                VStack(alignment: .leading, spacing: 14) {
                    statBar(symbol: "bolt.fill", value: Format.duration(minutes: wellbeing.focusMinutes),
                            detail: "today \(wellbeing.sessionsDone) of \(wellbeing.sessionsGoal) sessions · \(Int((wellbeing.focusShare * 100).rounded()))%",
                            share: wellbeing.focusShare, color: Palette.ringFocus)
                    energyBlock(wellbeing)
                }
                .frame(maxWidth: .infinity)
            }
            energyRow(wellbeing)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func timerRing(size: CGFloat) -> some View {
        let idle = engine.phase == .idle
        let finished = engine.runState == .finished
        let paused = engine.runState == .paused
        let tint = idle ? Palette.start : Palette.tint(for: engine.phase)
        let left = idle || finished ? 1 : 1 - engine.progress
        let line = size * 0.085
        return ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, left))
                .stroke(tint.opacity(idle ? 0.35 : (paused ? 0.5 : 1)), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: left)
            VStack(spacing: 2) {
                Image(systemName: ringSymbol).font(.system(size: size * 0.10, weight: .semibold)).foregroundStyle(tint)
                Text(idle ? Format.clock(Double(settings.focusMinutes * 60)) : Format.clock(engine.remaining))
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(idle || paused ? Color.white.opacity(0.6) : .white)
                    .contentTransition(.numericText())
                Text(ringCaption).font(.system(size: size * 0.085, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, line + 6)
        }
        .frame(width: size, height: size)
    }

    private var ringSymbol: String {
        switch (engine.phase, engine.runState) {
        case (_, .finished): return "bell.badge.fill"
        case (_, .paused): return "pause.fill"
        case (.focus, _): return "bolt.fill"
        case (.idle, _): return "play.fill"
        default: return "cup.and.saucer.fill"
        }
    }

    private var ringCaption: String {
        switch (engine.phase, engine.runState) {
        case (.focus, .finished): return "extend or rest"
        case (_, .finished): return "break is over"
        case (_, .paused): return "paused"
        case (.idle, _): return "ready"
        case (.focus, _): return "\(Format.short(minutes: engine.liveCoins)) focused"
        default: return "\(Format.short(minutes: engine.liveBreakMinutes)) rested"
        }
    }

    private func statBar(symbol: String, value: String, detail: String, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
            }
            bar(share: share, color: color)
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    private func bar(share: Double, color: Color, height: CGFloat = 6) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(color).frame(width: max(height, proxy.size.width * min(1, max(0, share))))
                    .opacity(share > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }

    /// Energy in place of a separate break bar: the mood face, the level, and the rest taken against
    /// what the finished sessions call for. Same block as in the desktop widget.
    private func energyBlock(_ wellbeing: Wellbeing) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(wellbeing.mood.emoji).font(.system(size: 15))
                Text("\(Int((wellbeing.energy * 100).rounded()))%")
                    .font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                Text(wellbeing.mood.title).font(.caption).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            bar(share: wellbeing.energy, color: wellbeing.energyColor)
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(Palette.ringRest)
                Text(wellbeing.dayOff || wellbeing.sessionsDone == 0
                     ? "rest \(Format.short(minutes: wellbeing.breakMinutes))"
                     : "rest \(Format.short(minutes: wellbeing.breakMinutes)) of \(Format.short(minutes: wellbeing.recommendedRest))")
            }
            .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    /// The status line under the ring. The widget shows the very same text.
    private func energyRow(_ wellbeing: Wellbeing) -> some View {
        Text("\(wellbeing.adviceIcon) \(wellbeing.advice)").font(.caption)
            .foregroundStyle(wellbeing.mood == .overworked ? Palette.focus : Color.white.opacity(0.7))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            switch (engine.phase, engine.runState) {
            case (.idle, _):
                bigButton("Start \(settings.focusMinutes) min focus", "play.fill", tint: Palette.start) { engine.startFocus() }
            case (.focus, .finished):
                bigButton("New session", "arrow.clockwise", tint: Palette.start) { engine.startFocus() }
                bigButton("Stop", "stop.fill") { engine.stop() }
            case (_, .finished):
                bigButton("Start \(settings.focusMinutes) min focus", "play.fill", tint: Palette.start) { engine.startFocus() }
                bigButton("Stop", "stop.fill") { engine.stop() }
            default:
                // Running or paused: pause or resume, count it as done in full, or stop and keep only the time so far.
                pauseResume
                bigButton("Complete", "checkmark", tint: Palette.rest) { engine.completeNow() }
                    .help("Count the whole \(Format.duration(minutes: Int(engine.plannedSeconds / 60))) as done and log it")
                bigButton("Stop", "stop.fill") { engine.stop() }
                    .help("Stop now and keep only the time so far")
            }
        }
    }

    /// Blue starts or resumes, red pauses.
    @ViewBuilder private var pauseResume: some View {
        if engine.runState == .paused {
            bigButton("Resume", "play.fill", tint: Palette.start) { engine.resume() }
        } else {
            bigButton("Pause", "pause.fill", tint: Palette.focus) { engine.pause() }
        }
    }

    private func bigButton(_ title: String, _ symbol: String, tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(TallButtonStyle(tint: tint))
    }

    private var footer: some View {
        HStack {
            Button { AppWindows.showStats() } label: { Label("Statistics", systemImage: "chart.bar.fill") }
            Button { AppWindows.showLog() } label: { Label("Time log", systemImage: "list.bullet.rectangle") }
            Button { AppWindows.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

/// A slim line at the top of the panel when a new version is waiting.
struct UpdateBanner: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        if let update = updater.available {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.start)
                if case .available = updater.state {
                    Text("Version \(update.version) is available").font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    Button("Update") { updater.install() }.buttonStyle(.borderedProminent).tint(Palette.start).controlSize(.small)
                } else {
                    Text("Installing version \(update.version)…").font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.start.opacity(0.14)))
        }
    }
}
