import XCTest
@testable import FocusPlus

final class StartReminderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    func testRemindsAfterTenMinutesOfActivityAndThenEveryFifteen() {
        var logic = StartReminderLogic(threshold: 600)
        XCTAssertNil(logic.step(now: at(0), secondsSinceInput: 2, timerIdle: true, allowed: true))
        XCTAssertNil(logic.step(now: at(9), secondsSinceInput: 5, timerIdle: true, allowed: true))
        XCTAssertEqual(logic.step(now: at(10.1), secondsSinceInput: 1, timerIdle: true, allowed: true), 10)
        XCTAssertNil(logic.step(now: at(11), secondsSinceInput: 1, timerIdle: true, allowed: true), "not twice in a row")
        XCTAssertNil(logic.step(now: at(24), secondsSinceInput: 1, timerIdle: true, allowed: true))
        XCTAssertEqual(logic.step(now: at(25.2), secondsSinceInput: 1, timerIdle: true, allowed: true), 25)
    }

    func testShortPausesDoNotResetButWalkingAwayDoes() {
        var logic = StartReminderLogic(threshold: 600)
        XCTAssertNil(logic.step(now: at(0), secondsSinceInput: 1, timerIdle: true, allowed: true))
        // Reading for three minutes without touching anything still counts as being there.
        XCTAssertNil(logic.step(now: at(6), secondsSinceInput: 180, timerIdle: true, allowed: true))
        XCTAssertEqual(logic.step(now: at(10.5), secondsSinceInput: 10, timerIdle: true, allowed: true), 10)

        var away = StartReminderLogic(threshold: 600)
        XCTAssertNil(away.step(now: at(0), secondsSinceInput: 1, timerIdle: true, allowed: true))
        XCTAssertNil(away.step(now: at(8), secondsSinceInput: 320, timerIdle: true, allowed: true), "walked away")
        XCTAssertNil(away.step(now: at(11), secondsSinceInput: 1, timerIdle: true, allowed: true), "the count starts over")
        XCTAssertEqual(away.step(now: at(21.1), secondsSinceInput: 1, timerIdle: true, allowed: true), 10)
    }

    func testNoRemindersWhileATimerRunsOrWhenSwitchedOff() {
        var logic = StartReminderLogic(threshold: 600)
        XCTAssertNil(logic.step(now: at(0), secondsSinceInput: 1, timerIdle: true, allowed: true))
        XCTAssertNil(logic.step(now: at(12), secondsSinceInput: 1, timerIdle: false, allowed: true), "a timer is running")
        // After the timer, the ten minutes are counted afresh.
        XCTAssertNil(logic.step(now: at(40), secondsSinceInput: 1, timerIdle: true, allowed: true))
        XCTAssertNil(logic.step(now: at(45), secondsSinceInput: 1, timerIdle: true, allowed: true))
        XCTAssertEqual(logic.step(now: at(50.1), secondsSinceInput: 1, timerIdle: true, allowed: true), 10)

        var off = StartReminderLogic(threshold: 600)
        XCTAssertNil(off.step(now: at(0), secondsSinceInput: 1, timerIdle: true, allowed: false))
        XCTAssertNil(off.step(now: at(30), secondsSinceInput: 1, timerIdle: true, allowed: false))
    }

    func testNobodyThereNoCount() {
        var logic = StartReminderLogic(threshold: 600)
        XCTAssertNil(logic.step(now: at(0), secondsSinceInput: 90, timerIdle: true, allowed: true), "no recent input")
        XCTAssertNil(logic.step(now: at(15), secondsSinceInput: 200, timerIdle: true, allowed: true))
    }
}
