import Foundation
import Combine

/// Push notifications to the phone through ntfy (https://ntfy.sh), with buttons that answer back.
///
/// When a timer ends the Mac publishes a message to a private topic; the ntfy app on the phone shows it.
/// Each button posts a short command ("extend:5", "break:60") to a second, reply topic,
/// which this Mac listens to and applies to the timer.
/// The topic names are random and act as the password: whoever knows them can read and send.
final class PhonePush: ObservableObject {
    static let shared = PhonePush()

    enum SendStatus: Equatable { case idle, sending, sent, failed(String) }

    /// The outcome of the last message sent from the Mac.
    @Published var sendStatus: SendStatus = .idle
    /// When the phone last answered a test with its "It works" button.
    @Published var confirmedAt: Date?
    /// What the "It works" button of a test notification posts back.
    static let ping = "ping"

    enum Command: Equatable {
        case extend(Int), rest(Int), focus(Int), complete, stop

        /// Parses "extend:15", "break:60", "focus:30", "complete", "stop".
        init?(_ text: String) {
            let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: ":")
            guard let name = parts.first else { return nil }
            let minutes = parts.count > 1 ? Int(parts[1]) : nil
            switch (name, minutes) {
            case ("extend", let m?) where (1...600).contains(m): self = .extend(m)
            case ("break", let m?) where (1...600).contains(m): self = .rest(m)
            case ("focus", let m?) where (1...600).contains(m): self = .focus(m)
            case ("complete", _): self = .complete
            case ("stop", _): self = .stop
            default: return nil
            }
        }

        var text: String {
            switch self {
            case .extend(let m): return "extend:\(m)"
            case .rest(let m): return "break:\(m)"
            case .focus(let m): return "focus:\(m)"
            case .complete: return "complete"
            case .stop: return "stop"
            }
        }
    }

    struct Button: Equatable {
        var label: String
        var command: Command
    }

    private let server = URL(string: "https://ntfy.sh")!
    private var listener: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var seen = Set<String>()
    private let settings = AppSettings.shared

    var replyTopic: String { settings.pushTopic + "-reply" }

    /// Starts or stops listening as the setting changes.
    func start() {
        settings.$pushEnabled.combineLatest(settings.$pushTopic)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, topic in
                self?.listener?.cancel()
                self?.listener = nil
                if enabled, !topic.isEmpty { self?.listen() }
            }
            .store(in: &subscriptions)
    }

    // MARK: Buttons

    /// The three buttons of the one notification, the most ntfy allows:
    /// more focus, more rest, or stop. Additions read as "+N min".
    static func buttons(finished phase: TimerEngine.Phase, settings: AppSettings) -> [Button] {
        func nearest(_ options: [Int], to wanted: Int) -> Int {
            options.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
        }
        let rest = nearest(settings.breakOptions, to: 10)
        if phase == .focus {
            let more = nearest(settings.extensionOptions, to: 15)
            return [Button(label: "+\(more) min focus", command: .extend(more)),
                    Button(label: "+\(rest) min break", command: .rest(rest)),
                    Button(label: "Stop", command: .stop)]
        }
        return [Button(label: "+\(settings.focusMinutes) min focus", command: .focus(settings.focusMinutes)),
                Button(label: "+\(rest) min break", command: .extend(rest)),
                Button(label: "Stop", command: .stop)]
    }

    // MARK: Sending

    private var pending: DispatchWorkItem?

    /// Tells the phone that a timer ended, unless the person reacts on the Mac within the delay from the settings.
    func timerFinished(_ phase: TimerEngine.Phase, engine: TimerEngine) {
        pending?.cancel()
        guard settings.pushEnabled else { return }
        let work = DispatchWorkItem { [weak self, weak engine] in
            // Answered on the Mac in the meantime: the prompt is gone and the phone stays quiet.
            guard let self, let engine, engine.runState == .finished, engine.phase == phase else { return }
            self.announce(phase, engine: engine)
        }
        pending = work
        // Development aid: FOCUSPLUS_PUSH_DELAY_SECONDS shortens the wait so that it can be tested.
        let override = ProcessInfo.processInfo.environment["FOCUSPLUS_PUSH_DELAY_SECONDS"].flatMap(Double.init)
        let delay = override ?? Double(max(0, settings.pushDelayMinutes)) * 60
        if delay == 0 { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    private func announce(_ phase: TimerEngine.Phase, engine: TimerEngine) {
        let focus = phase == .focus
        let minutes = engine.session?.plannedMinutes ?? settings.focusMinutes
        send(title: focus ? "Focus session complete" : "\(engine.breakName) is over",
             message: focus
                ? "\(Format.duration(minutes: minutes)) done. Today \(Format.short(minutes: engine.todayCoins)) of \(Format.short(minutes: settings.dailyGoal)). Extend or rest?"
                : "Ready for the next stretch of focus?",
             tags: [focus ? "white_check_mark" : "coffee"], priority: 4,
             buttons: Self.buttons(finished: phase, settings: settings))
    }

    func sendTest() {
        confirmedAt = nil
        send(title: "Focus Energy is connected",
             message: "Press \"It works\" to confirm. If you see no button, press and hold this notification.",
             tags: ["wave"], priority: 4, actions: [(label: "It works", body: Self.ping)])
    }

    private func send(title: String, message: String, tags: [String], priority: Int, buttons: [Button]) {
        send(title: title, message: message, tags: tags, priority: priority,
             actions: buttons.map { (label: $0.label, body: $0.command.text) })
    }

    private func send(title: String, message: String, tags: [String], priority: Int,
                      actions buttons: [(label: String, body: String)]) {
        guard !settings.pushTopic.isEmpty else { return }
        DispatchQueue.main.async { self.sendStatus = .sending }
        var body: [String: Any] = ["topic": settings.pushTopic, "title": title, "message": message,
                                   "tags": tags, "priority": priority]
        if !buttons.isEmpty {
            let reply = server.appendingPathComponent(replyTopic).absoluteString
            body["actions"] = buttons.prefix(3).map {
                ["action": "http", "label": $0.label, "url": reply, "method": "POST",
                 "body": $0.body, "clear": true] as [String: Any]
            }
        }
        var request = URLRequest(url: server)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { _, response, error in
            var status = SendStatus.sent
            if let error {
                NSLog("FocusPlus: push failed: \(error.localizedDescription)")
                status = .failed(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                NSLog("FocusPlus: push refused with status \(http.statusCode)")
                status = .failed("The service answered with error \(http.statusCode).")
            }
            DispatchQueue.main.async { self.sendStatus = status }
        }.resume()
    }

    // MARK: Listening for answers

    /// Keeps one streaming connection to the reply topic open and reconnects when it drops.
    private func listen() {
        let topic = replyTopic
        listener = Task { [weak self] in
            var since = String(Int(Date().timeIntervalSince1970))
            var delay: UInt64 = 2
            while !Task.isCancelled {
                guard let self,
                      var components = URLComponents(url: self.server.appendingPathComponent(topic).appendingPathComponent("json"),
                                                     resolvingAgainstBaseURL: false) else { return }
                components.queryItems = [URLQueryItem(name: "since", value: since)]
                do {
                    var request = URLRequest(url: components.url!)
                    request.timeoutInterval = 3600
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    delay = 2
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              json["event"] as? String == "message",
                              let id = json["id"] as? String, let text = json["message"] as? String else { continue }
                        since = id
                        await self.handle(id: id, text: text)
                    }
                } catch {
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 60)
            }
        }
    }

    @MainActor
    private func handle(id: String, text: String) {
        guard seen.insert(id).inserted else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.ping {
            confirmedAt = Date()
            send(title: "All set", message: "Your Mac heard the phone. Timer notifications will arrive here.",
                 tags: ["white_check_mark"], priority: 2, buttons: [])
            return
        }
        guard let command = Command(text) else { return }
        let summary = Self.apply(command, to: TimerEngine.shared)
        // A quiet confirmation, so the phone shows what the Mac did.
        send(title: summary.applied ? "Done" : "Not applied", message: summary.text, tags: [], priority: 2, buttons: [])
    }

    /// Applies a command from the phone. Returns what happened, in words.
    @discardableResult
    static func apply(_ command: Command, to engine: TimerEngine) -> (applied: Bool, text: String) {
        func ending() -> String {
            engine.runState == .running
                ? " Ends at \(Format.time(Date().addingTimeInterval(engine.remaining)))." : ""
        }
        switch command {
        case .extend(let minutes):
            guard engine.phase != .idle else { return (false, "No timer is running on the Mac.") }
            engine.extend(minutes: minutes)
            return (true, "Added \(minutes) min.\(ending())")
        case .rest(let minutes):
            engine.startBreak(minutes: minutes)
            return (true, "\(engine.breakName), \(minutes) min.\(ending())")
        case .focus(let minutes):
            engine.startFocus(minutes: minutes)
            return (true, "Focus, \(minutes) min.\(ending())")
        case .complete:
            guard engine.phase != .idle else { return (false, "No timer is running on the Mac.") }
            engine.completeNow()
            return (true, "Logged as completed.")
        case .stop:
            engine.stop()
            return (true, "Timer stopped.")
        }
    }
}
