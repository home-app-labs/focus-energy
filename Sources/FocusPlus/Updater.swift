import AppKit
import Combine
import CryptoKit

/// What a release says about itself: the file `update.json` attached to every GitHub release.
struct UpdateManifest: Codable, Equatable {
    var version: String
    var notes: String
    /// Where the zipped app is.
    var url: URL
    /// Ed25519 signature of that zip, base64.
    var signature: String
    var size: Int
}

/// The rules of updating, free of side effects so they can be tested.
enum UpdateRules {
    /// The public half of the Home App Labs signing key. An update is installed only if its zip
    /// carries a valid signature made with the private half, which never leaves the maker's Mac.
    static let publicKey = "vh7pReSK4pGF4WswlyibOJyEIm1fj9QF8B3pmy5X+ck="
    static let maxBytes = 100 * 1024 * 1024

    /// "1.10.0" is newer than "1.9.3". Anything that is not plain numbers and dots is never newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int]? {
            let pieces = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            return pieces.isEmpty || pieces.contains(nil) ? nil : pieces.map { $0! }
        }
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func isSigned(_ data: Data, signature: String, publicKey: String = publicKey) -> Bool {
        guard let rawKey = Data(base64Encoded: publicKey), let rawSignature = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else { return false }
        return key.isValidSignature(rawSignature, for: data)
    }
}

/// Finds new versions on GitHub, checks that they are genuine, and swaps the app for the new one.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate
        case available(UpdateManifest)
        case downloading(UpdateManifest)
        case installing(UpdateManifest)
        case failed(String)
    }

    struct Failure: Error { var message: String }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    private let settings = AppSettings.shared
    private let environment = ProcessInfo.processInfo.environment
    private var timers = Set<AnyCancellable>()
    private var prepared: (manifest: UpdateManifest, app: URL)?

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    private var manifestURL: URL {
        environment["FOCUSPLUS_UPDATE_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/home-app-labs/focus-energy/releases/latest/download/update.json")!
    }

    /// Updating swaps the .app this process runs from, so there has to be one.
    var canUpdate: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var available: UpdateManifest? {
        switch state {
        case .available(let m), .downloading(let m), .installing(let m): return m
        default: return nil
        }
    }

    func start() {
        guard canUpdate else { return }
        announceIfJustUpdated()
        // A first look shortly after launch, then once a day.
        DispatchQueue.main.asyncAfter(deadline: .now() + (environment["FOCUSPLUS_UPDATE_URL"] == nil ? 30 : 1)) { [weak self] in
            self?.checkIfDue()
        }
        Timer.publish(every: 3600, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.checkIfDue() }.store(in: &timers)
        // With automatic installs on, wait for a quiet moment: no timer running and the app in the background.
        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.installIfQuiet() }.store(in: &timers)
    }

    private func checkIfDue() {
        guard settings.autoCheckUpdates else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 24 * 3600 { return }
        check()
    }

    func check() {
        guard canUpdate, state != .checking else { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        Task { @MainActor in
            do {
                var request = URLRequest(url: manifestURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    // A release without update.json, or none at all, simply means there is nothing to offer.
                    throw Failure(message: http.statusCode == 404 ? "" : "The update server answered with error \(http.statusCode).")
                }
                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                lastChecked = Date()
                if UpdateRules.isNewer(manifest.version, than: currentVersion) {
                    state = .available(manifest)
                    if environment["FOCUSPLUS_UPDATE_AUTOINSTALL"] == "1" { install() } else { installIfQuiet() }
                } else {
                    state = .upToDate
                }
            } catch let failure as Failure {
                lastChecked = Date()
                state = failure.message.isEmpty ? .upToDate : .failed(failure.message)
            } catch {
                state = .failed("Could not check for updates: \(error.localizedDescription)")
            }
        }
    }

    private func installIfQuiet() {
        guard settings.autoInstallUpdates, case .available = state else { return }
        guard TimerEngine.shared.phase == .idle, !NSApp.isActive else { return }
        install()
    }

    /// Downloads the update, checks it, and replaces the running app with it.
    func install() {
        guard case .available(let manifest) = state else { return }
        state = .downloading(manifest)
        Task { @MainActor in
            do {
                let app = try await self.download(manifest)
                state = .installing(manifest)
                try self.swap(with: app)
            } catch let failure as Failure {
                state = .failed(failure.message)
            } catch {
                state = .failed("The update could not be installed: \(error.localizedDescription)")
            }
        }
    }

    /// Fetches the zip and returns the unpacked, verified app.
    private func download(_ manifest: UpdateManifest) async throws -> URL {
        guard manifest.size > 0, manifest.size <= UpdateRules.maxBytes else { throw Failure(message: "The update has an unexpected size.") }
        var request = URLRequest(url: manifest.url)
        request.timeoutInterval = 120
        let (zip, _) = try await URLSession.shared.data(for: request)
        guard zip.count == manifest.size else { throw Failure(message: "The download was incomplete. Please try again.") }
        guard UpdateRules.isSigned(zip, signature: manifest.signature) else {
            throw Failure(message: "The update is not signed by Home App Labs, so it was not installed.")
        }

        // Unpack next to the installed app, so that moving it into place later is instant.
        let destination = Bundle.main.bundleURL
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: destination, create: true)
        let zipURL = work.appendingPathComponent("update.zip")
        try zip.write(to: zipURL)
        guard Self.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path]) else { throw Failure(message: "The update could not be unpacked.") }
        try? FileManager.default.removeItem(at: zipURL)

        let apps = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard apps.count == 1, let app = apps.first, let info = Bundle(url: app)?.infoDictionary else {
            throw Failure(message: "The update does not contain the app.")
        }
        // The signature proves who made the zip. These checks make sure it is this app, and really a newer one.
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == manifest.version,
              UpdateRules.isNewer(manifest.version, than: currentVersion) else {
            throw Failure(message: "The update is not a newer version of this app.")
        }
        guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else {
            throw Failure(message: "The update is damaged.")
        }
        return app
    }

    /// Hands over to a small script that waits for this app to quit, moves the new one into place and opens it.
    private func swap(with newApp: URL) throws {
        let destination = Bundle.main.bundleURL
        guard !destination.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path),
              FileManager.default.isWritableFile(atPath: destination.path) else {
            throw Failure(message: "The app cannot replace itself here. Move it to the Applications folder, or download the installer from homeapplabs.com.")
        }
        let script = """
        #!/bin/sh
        # Waits for the old app to quit, then swaps in the new one. Puts the old one back if that fails.
        PID="$1"; NEW="$2"; DEST="$3"; RELAUNCH="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        BACKUP="$DEST.previous"
        rm -rf "$BACKUP"
        mv "$DEST" "$BACKUP" || exit 1
        if mv "$NEW" "$DEST"; then rm -rf "$BACKUP"; else mv "$BACKUP" "$DEST"; exit 1; fi
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1
        # Desktop widgets keep the old version until the system's widget service restarts.
        pkill -x FocusPlusWidget 2>/dev/null
        killall chronod 2>/dev/null
        [ "$RELAUNCH" = "1" ] && open "$DEST"
        rm -rf "$(dirname "$NEW")"
        """
        let scriptURL = newApp.deletingLastPathComponent().appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination.path,
                             environment["FOCUSPLUS_UPDATE_NO_RELAUNCH"] == "1" ? "0" : "1"]
        try process.run()

        settings.updatedFromVersion = currentVersion
        TimerEngine.shared.prepareForQuit()
        ActivityLog.shared.save()
        NSApp.terminate(nil)
    }

    private func announceIfJustUpdated() {
        guard let old = settings.updatedFromVersion else { return }
        settings.updatedFromVersion = nil
        if UpdateRules.isNewer(currentVersion, than: old) {
            Notifier.shared.note(title: "Focus Energy was updated", body: "Now on version \(currentVersion).")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
