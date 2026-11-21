import SwiftUI

/// Settings in two parts: General applies everywhere, Modes holds what each mode keeps for itself.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var ledger = Ledger.shared
    @ObservedObject private var updater = Updater.shared
    @State private var storageError: String?
    @State private var extensionsText = ""
    @State private var tab = ProcessInfo.processInfo.environment["FOCUSPLUS_SETTINGS_TAB"].flatMap(Int.init) ?? 0
    @State private var editing: WorkMode = .moderate

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("Modes").tag(0)
                Text("General").tag(1)
                Text("Notifications").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380).padding(.top, 14)
            if tab == 0 { modes } else if tab == 1 { general } else { phone }
        }
        .frame(width: 540, height: tab == 0 ? 560 : (tab == 1 ? 640 : 760))
        .onAppear {
            extensionsText = settings.extensionOptions.map(String.init).joined(separator: ", ")
            editing = settings.currentMode
        }
        .onDisappear(perform: applyExtensions)
        .onChange(of: extensionsText) { _ in applyExtensions(keepText: true) }
    }

    // MARK: Modes

    private var modes: some View {
        let mode = settings.settings(for: editing)
        let classic = mode.pomodoroRest
        return Form {
            Section {
                Picker("Mode in use", selection: $settings.currentMode) {
                    ForEach(WorkMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Text("The mode sets your limits for the day. You can also switch it from the top of the timer window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Edit a mode") {
                Picker("Mode", selection: $editing) {
                    ForEach(WorkMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Stepper("Focus per day: \(Format.duration(minutes: mode.focusGoal))",
                        value: binding(\.focusGoal), in: 30...960, step: 30)
                Stepper("Rest per day: \(Format.duration(minutes: mode.restGoal))",
                        value: binding(\.restGoal), in: 0...480, step: 15)
                Text("That is \(mode.restGoal * 60 / max(mode.focusGoal, 1)) min of rest per hour of focus. "
                     + "Classic Pomodoro for \(Format.duration(minutes: mode.focusGoal)) of focus gives "
                     + "\(Format.duration(minutes: classic.lowerBound)) to \(Format.duration(minutes: classic.upperBound)) of rest.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Default session: \(mode.sessionMinutes) min", value: binding(\.sessionMinutes), in: 5...240, step: 5)
                Stepper("Suggested break: \(mode.breakMinutes) min", value: binding(\.breakMinutes), in: 5...120, step: 5)
                Text("Past \(Format.duration(minutes: mode.focusGoal * 4 / 3)) a day counts as heavy, past \(Format.duration(minutes: mode.focusGoal * 10 / 6)) as overwork.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Reset \(editing.title) to defaults") { settings.reset(editing) }
                        .disabled(mode == editing.defaults)
                    Spacer()
                    Button("Use \(editing.title) now") { settings.currentMode = editing }
                        .disabled(settings.currentMode == editing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<ModeSettings, Int>) -> Binding<Int> {
        Binding(get: { settings.settings(for: editing)[keyPath: keyPath] },
                set: { value in settings.update(editing) { $0[keyPath: keyPath] = value } })
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Updates") {
                LabeledContent("Version \(updater.currentVersion)") {
                    Button("Check for updates") { updater.check() }
                        .disabled(!updater.canUpdate || updater.state == .checking)
                }
                updateStatus
                Toggle("Check for a new version once a day", isOn: $settings.autoCheckUpdates)
                Toggle("Install new versions automatically", isOn: $settings.autoInstallUpdates)
                Text("Updates come from the app's GitHub releases and are installed only if they carry the Home App Labs signature. "
                     + "Automatic installs wait until no timer is running and the app is in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Focus buttons") {
                TextField("Minutes", text: $extensionsText, prompt: Text("5, 10, 15, 30, 60"))
                    .onSubmit(applyExtensions)
                Text("The round buttons for starting and extending a session. Now: "
                     + settings.extensionOptions.map(String.init).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Breaks") {
                ForEach($settings.breakPresets) { $preset in
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(BreakPreset.symbolChoices, id: \.symbol) { choice in
                                Button { preset.symbol = choice.symbol } label: {
                                    Label(choice.label, systemImage: choice.symbol)
                                }
                            }
                            Divider()
                            Picker("How many", selection: $preset.count) {
                                Text("One").tag(1); Text("Two").tag(2); Text("Three").tag(3)
                            }
                        } label: {
                            Image(systemName: preset.symbol).frame(width: 22)
                        }
                        .menuStyle(.borderlessButton).fixedSize().help("Icon")
                        TextField("Name", text: $preset.name, prompt: Text("Name"))
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                        Text("\(preset.minutes) min").monospacedDigit().frame(width: 62, alignment: .trailing)
                        Stepper("Minutes", value: $preset.minutes, in: 5...240, step: 5).labelsHidden()
                        Button(role: .destructive) {
                            settings.breakPresets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).disabled(settings.breakPresets.count <= 1).help("Remove")
                    }
                }
                HStack {
                    Button("Add break") {
                        let longest = settings.breakPresets.map(\.minutes).max() ?? 0
                        settings.breakPresets.append(BreakPreset(minutes: longest + 15, name: "Break", symbol: "leaf.fill"))
                    }
                    .disabled(settings.breakPresets.count >= 6)
                    Spacer()
                    Button("Reset to defaults") { settings.breakPresets = BreakPreset.defaults }
                }
                Stepper("Long break: \(settings.longBreakMinutes) min", value: $settings.longBreakMinutes, in: 5...120, step: 5)
                Stepper("Suggest it after \(settings.longBreakEvery) sessions", value: $settings.longBreakEvery, in: 1...12)
            }
            Section("Menu bar and Dock") {
                Toggle("Show today's goal progress in the menu bar when idle", isOn: $settings.showCoinsInMenuBar)
                Toggle("Show the live timer on the Dock icon", isOn: $settings.showTimerInDock)
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin },
                                                        set: { settings.launchAtLogin = $0 }))
            }
            Section("Storage") {
                Toggle("Keep the time log in iCloud Drive", isOn: Binding(
                    get: { ledger.usesICloud },
                    set: { storageError = ledger.setICloud(enabled: $0) }))
                Text(storageError ?? (ledger.usesICloud
                        ? "Synced through iCloud Drive, in the folder \"Focus Energy\". Turn this on on your other Macs too."
                        : "The log is kept on this Mac only."))
                    .font(.caption).foregroundStyle(storageError == nil ? Color.secondary : Color.red)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Notifications

    private var phone: some View {
        Form {
            Section("On this Mac, when a timer ends") {
                Toggle("Open the choice window", isOn: $settings.popUpWhenFinished)
                Toggle("Play a sound", isOn: $settings.playSounds)
                Toggle("Show a notification", isOn: $settings.showNotifications)
            }
            Section("On this Mac, when no timer is running") {
                Toggle("Remind me when I work without a timer", isOn: $settings.remindToStart)
                if settings.remindToStart {
                    Stepper("After \(settings.remindAfterMinutes) min at the keyboard or mouse",
                            value: $settings.remindAfterMinutes, in: 5...60, step: 5)
                }
                Text("Repeats every 15 min while you keep working. Stops for the day once the daily focus goal is reached.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("On your phone") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Timer notifications on your iPhone", systemImage: "iphone.radiowaves.left.and.right")
                        .font(.headline)
                    Text("When a timer ends, the phone gets a notification with buttons such as \"+5 min\" or \"Lunch 60\". "
                         + "Your answer comes back to this Mac and is applied to the timer.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        AppWindows.showPhoneSetup()
                    } label: {
                        Text(settings.pushEnabled ? "Open the setup guide" : "Set up my phone")
                            .fontWeight(.semibold).padding(.horizontal, 10).padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.start).controlSize(.large)
                    Text("Three steps with a QR code, about two minutes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Send timer notifications to my phone", isOn: Binding(
                    get: { settings.pushEnabled },
                    set: { on in
                        if on, settings.pushTopic.isEmpty { settings.regeneratePushTopic() }
                        settings.pushEnabled = on
                    }))
                if settings.pushEnabled {
                    LabeledContent("Topic") {
                        Text(settings.pushTopic).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    }
                    Stepper(settings.pushDelayMinutes == 0
                                ? "Send at once when a timer ends"
                                : "Send after \(settings.pushDelayMinutes) min without a reaction on the Mac",
                            value: $settings.pushDelayMinutes, in: 0...30)
                    HStack {
                        Button("Send a test") { PhonePush.shared.sendTest() }
                        Spacer()
                        Button("New topic") { settings.regeneratePushTopic() }
                            .help("Use this if the topic name leaked. You will need to subscribe again on the phone.")
                    }
                }
                Text("Uses the free ntfy app. Only short texts leave the Mac; anyone who knows the topic name could read them, so keep it private.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var updateStatus: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .upToDate:
            Label("You have the latest version.", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.rest)
        case .available(let update):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(update.version) is available", systemImage: "arrow.down.circle.fill")
                    .fontWeight(.semibold).foregroundStyle(Palette.start)
                Text(update.notes).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(8).fixedSize(horizontal: false, vertical: true)
                Button("Update now") { updater.install() }.buttonStyle(.borderedProminent).tint(Palette.start)
            }
        case .downloading(let update):
            Text("Downloading version \(update.version)…").foregroundStyle(.secondary)
        case .installing(let update):
            Text("Installing version \(update.version). The app will reopen in a moment.").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.focus)
        }
    }

    private func applyExtensions() { applyExtensions(keepText: false) }

    private func applyExtensions(keepText: Bool) {
        let parsed = AppSettings.parseExtensions(extensionsText)
        guard !parsed.isEmpty else { return }
        if parsed != settings.extensionOptions {
            settings.extensionOptions = parsed
            Notifier.shared.registerCategories()
        }
        if !keepText { extensionsText = parsed.map(String.init).joined(separator: ", ") }
    }
}
