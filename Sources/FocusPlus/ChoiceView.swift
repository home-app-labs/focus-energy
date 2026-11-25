import SwiftUI

/// Shown on top of everything when a countdown ends: the moment to decide what happens next.
/// Choices come first; the Focus energy status sits underneath.
struct ChoiceView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var ledger: Ledger

    var body: some View {
        VStack(spacing: 22) {
            if engine.phase == .focus {
                focusDone
                TodayCard(engine: engine, settings: settings, ledger: ledger)
            } else {
                breakDone
                statusLine
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(width: 520)
    }

    private func header(symbol: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(color)
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private var focusDone: some View {
        let minutes = engine.session?.plannedMinutes ?? settings.focusMinutes
        let hint = engine.wellbeing.breakHint
        let breaks = BreakButtons(options: settings.breakOptions, highlighted: engine.suggestedBreakMinutes, prominent: true) {
            engine.startBreak(minutes: $0)
        }
        return VStack(spacing: 22) {
            header(symbol: "checkmark.circle.fill", color: Palette.ringFocus, title: "Focus session complete",
                   subtitle: "\(Format.duration(minutes: minutes)) of focus done")

            // Once a break is due it comes first and says why; working on is still one click away.
            if let hint {
                group(hint) { breaks }
                group("Or keep working") {
                    ExtendButtons(options: settings.extensionOptions) { engine.extend(minutes: $0) }
                }
            } else {
                group("How much longer do you want to work?") {
                    ExtendButtons(options: settings.extensionOptions, prominent: true) { engine.extend(minutes: $0) }
                }
                group("Or take a break") { breaks }
            }

            HStack(spacing: 8) {
                Button { engine.startFocus() } label: {
                    Label("New \(settings.focusMinutes) min session", systemImage: "arrow.clockwise")
                }
                .buttonStyle(TallButtonStyle(tint: Palette.start))

                Button { engine.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(TallButtonStyle())
            }
        }
    }

    private var breakDone: some View {
        VStack(spacing: 22) {
            header(symbol: "cup.and.saucer.fill", color: Palette.rest, title: "Break is over",
                   subtitle: "\(engine.breakName) · \(Format.duration(minutes: engine.liveBreakMinutes)) rested")

            // One way forward: the usual session. Another length is a click away in the main window.
            Button { engine.startFocus() } label: {
                Label("Start \(settings.focusMinutes) min focus", systemImage: "play.fill")
            }
            .buttonStyle(TallButtonStyle(tint: Palette.start, height: 54))

            group("Need a little more rest?") {
                BreakButtons(options: settings.breakOptions, adds: true, prominent: true) { engine.extend(minutes: $0) }
            }
        }
    }

    /// The day in two small lines: sessions, energy and rest, then the same advice as in the app and the widget.
    /// Closing the window stands for "not now" and stops the timer, so there is no Stop button.
    private var statusLine: some View {
        let wellbeing = engine.wellbeing
        return VStack(spacing: 8) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
            HStack(spacing: 18) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill").foregroundStyle(Palette.ringFocus)
                    Text("\(wellbeing.sessionsDone) of \(wellbeing.sessionsGoal) sessions · \(Int((wellbeing.focusShare * 100).rounded()))%")
                }
                HStack(spacing: 5) {
                    Text(wellbeing.mood.emoji)
                    Text("\(Int((wellbeing.energy * 100).rounded()))%").foregroundStyle(wellbeing.energyColor)
                }
                HStack(spacing: 5) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(Palette.ringRest)
                    Text(wellbeing.sessionsDone > 0
                         ? "rest \(Format.short(minutes: wellbeing.breakMinutes)) of \(Format.short(minutes: wellbeing.recommendedRest))"
                         : "rest \(Format.short(minutes: wellbeing.breakMinutes))")
                }
            }
            .font(.system(size: 13, weight: .medium)).monospacedDigit().padding(.top, 6)
            Text("\(wellbeing.adviceIcon) \(wellbeing.advice)").font(.caption)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
