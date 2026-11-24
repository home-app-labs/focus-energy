import AppKit
import SwiftUI
import WidgetUI

/// Plain AppKit windows hosting SwiftUI views. A menu bar app has no main window,
/// so these are created on demand and brought to the front explicitly.
enum AppWindows {
    private static var windows: [String: NSWindow] = [:]

    static func showStats() {
        show(id: "stats", title: "Focus Energy Statistics", resizable: true) {
            StatsView(engine: .shared, settings: .shared, ledger: .shared)
        }
    }

    static func showLog() {
        show(id: "log", title: "Focus Energy Time Log", resizable: true) {
            TimeLogView(engine: .shared, ledger: .shared, settings: .shared)
        }
    }

    static func showSettings() {
        show(id: "settings", title: "Focus Energy Settings") {
            SettingsView(settings: .shared)
        }
    }

    /// Step by step: get the ntfy app, subscribe, check the connection.
    static func showPhoneSetup() {
        show(id: "phone", title: "Phone notifications") {
            PhoneSetupView(settings: .shared, push: .shared)
        }
    }

    /// The end-of-timer prompt floats above other apps, including full screen ones.
    static func showChoice() {
        show(id: "choice", title: "Focus Energy", floating: true) {
            ChoiceView(engine: .shared, settings: .shared, ledger: .shared)
        }
    }

    /// The main window: the same timer panel that opens from the menu bar.
    static func showMain() {
        show(id: "main", title: "Focus Energy") {
            PopoverView(engine: .shared, settings: .shared, ledger: .shared)
        }
    }

    /// Development aid: the three desktop widget layouts, drawn from the live state.
    static func showWidgetPreview() {
        show(id: "widgets", title: "Widget preview") {
            let snapshot = WidgetBridge.makeSnapshot(engine: .shared, settings: .shared, ledger: .shared, now: Date())
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    FocusWidgetView(snapshot: snapshot, date: Date(), layout: .small).focusWidgetCard(width: 170, height: 170)
                    FocusWidgetView(snapshot: snapshot, date: Date(), layout: .medium).focusWidgetCard(width: 364, height: 170)
                }
                FocusWidgetView(snapshot: snapshot, date: Date(), layout: .large).focusWidgetCard(width: 364, height: 382)
            }
            .padding(20)
        }
    }

    /// Development aid: writes every open window's contents to `<id>.png`.
    static func snapshot(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (id, window) in windows where window.isVisible {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            // Views draw on a transparent backing, so put the window colour underneath.
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSColor(white: dark ? 0.13 : 0.95, alpha: 1).setFill()
            NSRect(origin: .zero, size: view.bounds.size).fill()
            rep.draw(in: NSRect(origin: .zero, size: view.bounds.size), from: .zero,
                     operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let flat = NSBitmapImageRep(data: tiff) else { continue }
            try? flat.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("\(id).png"))
        }
    }

    static func closeChoice() {
        windows["choice"]?.close()
    }

    private static func show<Content: View>(id: String, title: String, resizable: Bool = false,
                                            floating: Bool = false, @ViewBuilder content: () -> Content) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            var style: NSWindow.StyleMask = [.titled, .closable]
            if resizable { style.insert([.resizable, .miniaturizable]) }
            let hosting = NSHostingController(rootView: content())
            window = NSWindow(contentViewController: hosting)
            window.styleMask = style
            window.title = title
            window.isReleasedWhenClosed = false
            if floating {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.hidesOnDeactivate = false
            }
            window.center()
            windows[id] = window
            if id == "choice" {
                // Closing the prompt after a break means "not now": the timer stops, nothing starts.
                // After focus the window stays a plain close, so that the session can still be extended.
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    let engine = TimerEngine.shared
                    if engine.runState == .finished, engine.phase.isBreak { engine.stop() }
                }
            }
        }
        if floating { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
