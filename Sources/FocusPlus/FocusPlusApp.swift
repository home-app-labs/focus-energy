import SwiftUI
import Combine

@main
struct FocusPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = TimerEngine.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var ledger = Ledger.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(engine: engine, settings: settings, ledger: ledger)
        } label: {
            MenuBarLabel(engine: engine, settings: settings, ledger: ledger)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { AppWindows.showSettings() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Timer") {
                Button("Timer") { AppWindows.showMain() }.keyboardShortcut("0", modifiers: .command)
                Button("Statistics") { AppWindows.showStats() }.keyboardShortcut("1", modifiers: .command)
                Button("Time Log") { AppWindows.showLog() }.keyboardShortcut("2", modifiers: .command)
                Divider()
                Button("Set Up Phone Notifications…") { AppWindows.showPhoneSetup() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = TimerEngine.shared
        Notifier.shared.setUp()

        engine.onFinish = { phase in
            Notifier.shared.announce(finished: phase, engine: engine)
            PhonePush.shared.timerFinished(phase, engine: engine)
            if AppSettings.shared.popUpWhenFinished { AppWindows.showChoice() }
        }

        // Whatever resolves the prompt (window, menu bar or notification button), tidy up after it.
        engine.$runState
            .removeDuplicates()
            .filter { $0 != .finished }
            .receive(on: RunLoop.main)
            .sink { _ in
                AppWindows.closeChoice()
                Notifier.shared.clear()
            }
            .store(in: &subscriptions)

        // Keep the Dock icon in step with the timer.
        Publishers.CombineLatest4(engine.$remaining, engine.$runState, engine.$phase,
                                  AppSettings.shared.$showTimerInDock)
            .receive(on: RunLoop.main)
            .sink { _ in DockIcon.update() }
            .store(in: &subscriptions)

        WidgetBridge.shared.start()
        PhonePush.shared.start()

        // Pick up changes synced from another Mac: every half minute and whenever the app comes forward.
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().map { _ in }
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in })
            .sink { Ledger.shared.refresh() }
            .store(in: &subscriptions)

        AppWindows.showMain()
        runDebugHooks()
    }

    /// Clicking the Dock icon, or opening the app again, brings the timer window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.showMain()
        return false
    }

    /// Developer aids, all driven by environment variables:
    /// FOCUSPLUS_SHOW=stats,settings,panel opens those windows at launch,
    /// FOCUSPLUS_DEMO_SECONDS=5 runs a focus session that many seconds long,
    /// FOCUSPLUS_DEMO_ACTION=extend15|break is applied two seconds after launch,
    /// FOCUSPLUS_SNAPSHOT_DIR=/path saves PNGs of the open windows after eight seconds and quits,
    /// FOCUSPLUS_DATA_DIR=/path keeps the ledger somewhere other than Application Support.
    private func runDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        if let seconds = env["FOCUSPLUS_DEMO_SECONDS"].flatMap(Double.init) {
            TimerEngine.shared.startFocus(demoSeconds: seconds)
        }
        func open(_ names: String?) {
            for name in (names ?? "").split(separator: ",") {
                switch name {
                case "stats": AppWindows.showStats()
                case "settings": AppWindows.showSettings()
                case "panel": AppWindows.showMain()
                case "widgets": AppWindows.showWidgetPreview()
                case "log": AppWindows.showLog()
                case "phone": AppWindows.showPhoneSetup()
                default: break
                }
            }
        }
        open(env["FOCUSPLUS_SHOW"])
        // The same list, opened four seconds in: for windows that should show the state after a demo timer has ended.
        if let later = env["FOCUSPLUS_SHOW_LATER"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { open(later) }
        }
        if let action = env["FOCUSPLUS_DEMO_ACTION"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                switch action {
                case "extend15": TimerEngine.shared.extend(minutes: 15)
                case "break": TimerEngine.shared.startBreak()
                default: break
                }
            }
        }
        if let path = env["FOCUSPLUS_DUMP_MENU"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let lines = (NSApp.mainMenu?.items ?? []).flatMap { top in
                    (top.submenu?.items ?? []).map { "\(top.title) > \($0.title) [\($0.keyEquivalent)]" }
                }
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["FOCUSPLUS_DUMP_WINDOWS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let lines = NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) frame=\($0.frame) screen=\($0.screen?.localizedName ?? "none")" }
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let directory = env["FOCUSPLUS_SNAPSHOT_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                AppWindows.snapshot(to: URL(fileURLWithPath: directory, isDirectory: true))
                DockIcon.writePNG(to: URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("dock.png"))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        TimerEngine.shared.prepareForQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
