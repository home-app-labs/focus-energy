import XCTest
import WidgetUI

/// The widget often has to draw from an old snapshot: the system limits how often it reloads.
final class WidgetSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Riga")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Saturday 21 November, 23:40: a break has just ended, four hours of focus done. The week is Mon 16 to Sun 22.
    private func saturdayEvening(runState: WidgetSnapshot.RunState = .finished, endsAt: Date? = nil) -> WidgetSnapshot {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let week = labels.enumerated().map { index, label in
            WidgetSnapshot.Day(day: date(16 + index, 0), label: label, coins: index == 5 ? 241 : 0,
                               emoji: index == 5 ? "🙂" : "😴", isToday: index == 5, isFuture: index > 5)
        }
        let point = WidgetSnapshot.Point(date: date(21, 23, 40), coins: 241, breakMinutes: 50, recommendedRest: 60,
                                         energy: 0.9, moodEmoji: "😄", moodTitle: "Full of energy", advice: "10 min of rest owed.")
        return WidgetSnapshot(phase: .rest, runState: runState, endsAt: endsAt, plannedSeconds: 600, remainingSeconds: 0,
                              goal: 480, defaultFocusMinutes: 45, points: [point], week: week)
    }

    func testSameDayIsLeftAlone() {
        let snapshot = saturdayEvening()
        XCTAssertEqual(snapshot.resolved(at: date(21, 23, 59), calendar: calendar), snapshot)
    }

    func testAfterMidnightTheDayStartsFromZero() {
        let sunday = saturdayEvening().resolved(at: date(22, 0, 22), calendar: calendar)
        XCTAssertEqual(sunday.runState, .idle)
        XCTAssertEqual(sunday.phase, .idle)
        XCTAssertEqual(sunday.points.map(\.coins), [0])
        XCTAssertEqual(sunday.points.first?.breakMinutes, 0)
        XCTAssertEqual(sunday.week.filter(\.isToday).map(\.label), ["Sun"])
        XCTAssertTrue(sunday.week.allSatisfy { !$0.isFuture })
        XCTAssertEqual(sunday.week[5].coins, 241, "Saturday keeps what was done")
    }

    func testANewWeekStartsEmpty() {
        let monday = saturdayEvening().resolved(at: date(23, 9), calendar: calendar)
        XCTAssertEqual(monday.week.map(\.label), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(monday.week.filter(\.isToday).map(\.label), ["Mon"])
        XCTAssertEqual(monday.week.filter(\.isFuture).count, 6)
        XCTAssertTrue(monday.week.allSatisfy { $0.coins == 0 })
        XCTAssertEqual(monday.week[0].day, date(23, 0))
    }

    func testATimerRunningAcrossMidnightKeepsCounting() {
        let running = saturdayEvening(runState: .running, endsAt: date(22, 0, 30))
        let stillGoing = running.resolved(at: date(22, 0, 10), calendar: calendar)
        XCTAssertEqual(stillGoing.runState, .running)
        XCTAssertEqual(stillGoing.points.map(\.coins), [241])
        // Once it has ended, the new day shows.
        XCTAssertEqual(running.resolved(at: date(22, 0, 31), calendar: calendar).runState, .idle)
    }
}
