import XCTest
@testable import FocusPlus

final class ActivityTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// Polls every twenty seconds for `minutes`, with the idle time growing from `idle`.
    private func run(_ counter: inout ActivityCounter, minutes: Double, idle: TimeInterval, typing: Bool) -> TimeInterval {
        var total: TimeInterval = 0, quiet = idle
        for _ in 0..<Int(minutes * 3) {
            clock.addTimeInterval(20)
            quiet = typing ? 2 : quiet + 20
            total += counter.step(now: clock, secondsSinceInput: quiet)
        }
        return total
    }

    func testCountsWorkAndShortPausesButNotAbsence() {
        var counter = ActivityCounter()
        _ = counter.step(now: clock, secondsSinceInput: 1)
        var total = run(&counter, minutes: 30, idle: 0, typing: true)
        XCTAssertEqual(total, 1800, accuracy: 1)

        // Three minutes of reading still count.
        total += run(&counter, minutes: 3, idle: 0, typing: false)
        total += run(&counter, minutes: 10, idle: 0, typing: true)
        XCTAssertEqual(total, 43 * 60, accuracy: 1)

        // Forty minutes away: the quiet minutes that were counted at first are given back.
        total += run(&counter, minutes: 40, idle: 0, typing: false)
        XCTAssertEqual(total, 43 * 60, accuracy: 25)
        total += run(&counter, minutes: 5, idle: 0, typing: true)
        XCTAssertEqual(total, 48 * 60, accuracy: 45)
    }

    func testSleepIsNotCounted() {
        var counter = ActivityCounter()
        _ = counter.step(now: clock, secondsSinceInput: 1)
        clock.addTimeInterval(8 * 3600)
        XCTAssertEqual(counter.step(now: clock, secondsSinceInput: 3), 0, "the lid was closed all night")
        clock.addTimeInterval(20)
        XCTAssertEqual(counter.step(now: clock, secondsSinceInput: 3), 20)
    }

    func testPictureAndLog() {
        XCTAssertEqual(ActivityPicture(atMac: 370, focus: 270).line, "At the Mac 6h 10m · in focus 4h 30m · 1h 40m without a timer")
        XCTAssertEqual(ActivityPicture(atMac: 60, focus: 55).line, "At the Mac 1h · in focus 55m")
        XCTAssertEqual(ActivityPicture(atMac: 60, focus: 90).untimed, 0, "focus in a meeting, away from the keyboard")
        XCTAssertEqual(ActivityPicture(atMac: 0, focus: 0).line, "Time at the Mac is counted from now on")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("focusplus-activity-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ActivityLog(directory: directory)
        log.poll(now: clock, secondsSinceInput: 1)
        for _ in 0..<9 { clock.addTimeInterval(20); log.poll(now: clock, secondsSinceInput: 1) }
        XCTAssertEqual(log.minutes(on: clock), 3)
        log.save()
        XCTAssertEqual(ActivityLog(directory: directory).minutes(on: clock), 3)
    }
}
