import XCTest
@testable import FocusPlus

final class TimerEngineTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!
    private var ledger: Ledger!
    private var engine: TimerEngine!
    private let settings = AppSettings.shared

    override func setUp() {
        clock = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("focusplus-tests-\(UUID().uuidString)")
        ledger = Ledger(directory: directory)
        // Most tests were written around a thirty minute session; the mode test resets this.
        settings.modes = [WorkMode.moderate.rawValue: ModeSettings(sessions: 12, sessionMinutes: 30, breakMinutes: 5)]
        settings.currentMode = .moderate
        settings.longBreakMinutes = 10
        settings.longBreakEvery = 4
        settings.breakPresets = BreakPreset.defaults
        engine = TimerEngine(settings: settings, ledger: ledger, now: { [unowned self] in self.clock }, startTicker: false)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func advance(minutes: Double) {
        clock.addTimeInterval(minutes * 60)
        engine.tick()
    }

    func testExtendingAFinishedSessionKeepsOneSession() {
        var finished: [TimerEngine.Phase] = []
        engine.onFinish = { finished.append($0) }

        engine.startFocus()
        advance(minutes: 30)
        XCTAssertEqual(engine.runState, .finished)
        XCTAssertEqual(finished, [.focus])
        XCTAssertEqual(engine.liveCoins, 30)
        XCTAssertTrue(ledger.entries.isEmpty, "session stays open until the user decides")

        engine.extend(minutes: 15)
        XCTAssertEqual(engine.runState, .running)
        XCTAssertEqual(engine.remaining, 15 * 60, accuracy: 0.01)
        advance(minutes: 15)
        XCTAssertEqual(engine.runState, .finished)
        engine.startBreak()

        XCTAssertEqual(ledger.entries.count, 1)
        XCTAssertEqual(ledger.entries[0].minutes, 45)
        XCTAssertEqual(ledger.entries[0].baseMinutes, 30)
        XCTAssertEqual(ledger.entries[0].extensions, [15])
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.todayCoins, 45)
    }

    func testTimeSpentDecidingIsNotCredited() {
        engine.startFocus()
        advance(minutes: 30)
        advance(minutes: 20) // prompt ignored for 20 minutes
        engine.extend(minutes: 10)
        advance(minutes: 10)
        engine.stop()
        XCTAssertEqual(ledger.entries.map(\.minutes), [40])
    }

    func testExtendingWhileRunningAddsToTheCountdown() {
        engine.startFocus()
        advance(minutes: 10)
        engine.extend(minutes: 15)
        XCTAssertEqual(engine.remaining, 35 * 60, accuracy: 0.01)
        XCTAssertEqual(engine.session?.plannedMinutes, 45)
        advance(minutes: 35)
        XCTAssertEqual(engine.runState, .finished)
        XCTAssertEqual(engine.liveCoins, 45)
    }

    func testStoppingEarlyCreditsOnlyFocusedMinutes() {
        engine.startFocus()
        advance(minutes: 12.6)
        engine.pause()
        engine.stop()
        XCTAssertEqual(ledger.entries.map(\.minutes), [12])
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.sessionsSinceLongBreak, 0, "an abandoned session does not count towards the long break")
    }

    func testPausedTimeEarnsNothing() {
        engine.startFocus()
        advance(minutes: 10)
        engine.pause()
        advance(minutes: 25)
        XCTAssertEqual(engine.liveCoins, 10)
        engine.resume()
        advance(minutes: 5)
        XCTAssertEqual(engine.liveCoins, 15)
        XCTAssertEqual(engine.remaining, 15 * 60, accuracy: 0.01)
    }

    func testLongBreakAfterConfiguredNumberOfSessions() {
        settings.longBreakEvery = 2
        engine.startFocus(); advance(minutes: 30)
        XCTAssertFalse(engine.nextBreakIsLong)
        engine.startBreak()
        XCTAssertEqual(engine.phase, .shortBreak)
        advance(minutes: 5)
        XCTAssertEqual(engine.runState, .finished)

        engine.startFocus(); advance(minutes: 30)
        XCTAssertTrue(engine.nextBreakIsLong)
        XCTAssertEqual(engine.nextBreakMinutes, 10)
        engine.startBreak()
        XCTAssertEqual(engine.phase, .longBreak)
        XCTAssertEqual(engine.sessionsSinceLongBreak, 0)
        XCTAssertEqual(engine.todayCoins, 60)
    }

    func testBreakOfAChosenLength() {
        engine.startFocus(); advance(minutes: 30)
        engine.startBreak(minutes: 15)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.remaining, 15 * 60, accuracy: 0.01)
        XCTAssertEqual(ledger.entries.map(\.minutes), [30])
        engine.extend(minutes: 5)
        XCTAssertEqual(engine.remaining, 20 * 60, accuracy: 0.01)
        advance(minutes: 20)
        XCTAssertEqual(engine.runState, .finished)
        XCTAssertEqual(engine.todayCoins, 30, "breaks earn nothing")
        XCTAssertEqual(settings.breakOptions, [5, 10, 15, 30, 60])
    }

    func testBreaksAreRecordedAndFeedWellbeing() {
        engine.startFocus(minutes: 60); advance(minutes: 60)
        XCTAssertEqual(engine.session?.baseMinutes, 60)
        XCTAssertEqual(engine.wellbeing.stretch, 60)
        engine.startBreak(minutes: 10); advance(minutes: 4)
        XCTAssertEqual(engine.todayBreakMinutes, 4)
        XCTAssertEqual(engine.wellbeing.stretch, 0)
        advance(minutes: 6); advance(minutes: 30) // prompt ignored for half an hour
        engine.startFocus(minutes: 45); advance(minutes: 20)
        XCTAssertEqual(ledger.breaks.map(\.minutes), [10])
        XCTAssertEqual(engine.todayBreakMinutes, 10)
        XCTAssertEqual(engine.todayCoins, 80)
        XCTAssertEqual(engine.wellbeing.stretch, 20)
        XCTAssertEqual(engine.wellbeing.recommendedRest, 10, "one five minute break for each of the two sessions done")
        XCTAssertEqual(Ledger(directory: directory).breakMinutes(on: clock), 10)
    }

    func testMoodAndVerdictScale() {
        func mood(_ focus: Int, rest: Int, stretch: Int = 30) -> Wellbeing.Mood {
            Wellbeing(focusMinutes: focus, breakMinutes: rest, goal: 360, stretch: stretch, sessionMinutes: 30).mood
        }
        XCTAssertEqual(mood(0, rest: 0), .idle)
        // Rest in step with the plan: two hours of rest for six of focus.
        XCTAssertEqual(mood(120, rest: 40), .energised)
        XCTAssertEqual(mood(360, rest: 120), .energised)
        XCTAssertEqual(mood(360, rest: 0, stretch: 150), .tired)
        XCTAssertEqual(mood(480, rest: 160), .steady)
        XCTAssertEqual(mood(600, rest: 200), .overworked)
        XCTAssertEqual(mood(720, rest: 240), .overworked)

        XCTAssertEqual(DayVerdict.of(coins: 0, goal: 360), DayVerdict.none)
        XCTAssertEqual(DayVerdict.of(coins: 120, goal: 360), .light)
        XCTAssertEqual(DayVerdict.of(coins: 300, goal: 360), .onTrack)
        XCTAssertEqual(DayVerdict.of(coins: 360, goal: 360), .great)
        XCTAssertEqual(DayVerdict.of(coins: 540, goal: 360), .heavy)
        XCTAssertEqual(DayVerdict.of(coins: 600, goal: 360), .overwork)
        XCTAssertEqual(DayVerdict.of(coins: 720, goal: 360), .overwork)
    }

    func testDayRatingAndWeek() {
        ledger.setRating(4, on: clock)
        ledger.addBreak(BreakEntry(start: clock, minutes: 15))
        ledger.add(FocusEntry(start: clock, end: clock.addingTimeInterval(1800), minutes: 30, baseMinutes: 30, extensions: []))
        let reloaded = Ledger(directory: directory)
        XCTAssertEqual(reloaded.rating(on: clock), 4)
        let week = reloaded.week(containing: clock)
        XCTAssertEqual(week.count, 7)
        let today = week.first { Calendar.current.isDate($0.day, inSameDayAs: clock) }
        XCTAssertEqual(today?.coins, 30)
        XCTAssertEqual(today?.breakMinutes, 15)
        XCTAssertEqual(today?.rating, 4)
        XCTAssertTrue(reloaded.week(offset: -1, containing: clock).allSatisfy { $0.coins == 0 })
        reloaded.setRating(nil, on: clock)
        XCTAssertNil(Ledger(directory: directory).rating(on: clock))
    }

    func testCompleteLogsTheWholeTimer() {
        // Lunch that was never switched on: start 60, press Complete straight away.
        engine.startBreak(minutes: 60)
        advance(minutes: 0.2)
        engine.completeNow()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(ledger.breaks.map(\.minutes), [60])
        XCTAssertEqual(ledger.breaks[0].start.timeIntervalSince(clock), -3600, accuracy: 1)

        engine.startFocus(minutes: 45)
        advance(minutes: 10)
        engine.pause()
        engine.completeNow()
        XCTAssertEqual(ledger.entries.map(\.minutes), [45])
        XCTAssertEqual(engine.sessionsSinceLongBreak, 1)
        XCTAssertEqual(engine.todayCoins, 45)
    }

    func testLoggingAndDeletingPastEntries() {
        engine.logPastBreak(minutes: 60)
        engine.logPastFocus(minutes: 30)
        XCTAssertEqual(engine.todayBreakMinutes, 60)
        XCTAssertEqual(engine.todayCoins, 30)
        XCTAssertEqual(engine.phase, .idle)
        ledger.removeBreak(ledger.breaks[0])
        ledger.remove(ledger.entries[0])
        let reloaded = Ledger(directory: directory)
        XCTAssertTrue(reloaded.breaks.isEmpty)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    func testTwoCopiesSharingAFolderMerge() {
        // Two Macs pointed at the same synced folder.
        let other = Ledger(directory: directory)
        let mine = FocusEntry(start: clock, end: clock.addingTimeInterval(1800), minutes: 30, baseMinutes: 30, extensions: [])
        let theirs = FocusEntry(start: clock.addingTimeInterval(3600), end: clock.addingTimeInterval(5400),
                                minutes: 30, baseMinutes: 30, extensions: [])
        ledger.add(mine)
        other.add(theirs)
        XCTAssertEqual(other.entries.map(\.id), [mine.id, theirs.id], "adding never drops the other side's entry")
        XCTAssertTrue(ledger.refresh())
        XCTAssertEqual(ledger.entries.map(\.id), [mine.id, theirs.id])
        XCTAssertFalse(ledger.refresh(), "nothing new, nothing to do")

        other.addBreak(BreakEntry(start: clock, minutes: 15))
        other.setRating(5, on: clock)
        ledger.refresh()
        XCTAssertEqual(ledger.breakMinutes(on: clock), 15)
        XCTAssertEqual(ledger.rating(on: clock), 5)

        // A delete on one side is not undone by the other side saving afterwards.
        ledger.remove(theirs)
        other.addBreak(BreakEntry(start: clock, minutes: 5))
        XCTAssertEqual(other.entries.map(\.id), [mine.id])
        XCTAssertEqual(Ledger(directory: directory).entries.map(\.id), [mine.id])
        other.setRating(nil, on: clock)
        ledger.refresh()
        XCTAssertNil(ledger.rating(on: clock))
        XCTAssertFalse(ledger.usesICloud)
    }

    func testBreaksCarryTheirPresetNamesAndModesSetLimits() {
        engine.startBreak(minutes: 60)
        XCTAssertEqual(engine.phaseTitle, "Lunch")
        engine.completeNow()
        engine.startBreak(minutes: 30)
        XCTAssertEqual(engine.phaseTitle, "Walk")
        engine.stop()
        engine.startBreak()
        XCTAssertEqual(engine.phaseTitle, "Coffee")
        engine.stop()
        XCTAssertEqual(ledger.breaks.first?.name, "Lunch")

        settings.breakPresets[0].name = "Tea"
        XCTAssertEqual(BreakKind(minutes: 5, settings: settings).name, "Tea")
        XCTAssertEqual(BreakKind(minutes: 20, settings: settings).name, "Long coffee", "closest shorter preset")

        // Moderate out of the box: fifteen rounds of 25 and 5, a 7.5 hour day.
        settings.modes = [:]
        XCTAssertEqual(WorkMode.allCases.map(\.title), ["Day off", "Chill", "Moderate", "Hardcore"])
        XCTAssertEqual(settings.dailyGoal, 375)
        XCTAssertEqual(settings.dailyRest, 75)
        XCTAssertEqual(settings.focusMinutes, 25)
        XCTAssertEqual(settings.settings(for: .moderate).dayMinutes, 450)
        XCTAssertEqual(settings.settings(for: .light).dayMinutes, 300)
        XCTAssertEqual(settings.settings(for: .hardcore).dayMinutes, 600)
        // Rest is due in the rhythm of the mode: 5 minutes for every 25 of focus.
        engine.logPastFocus(minutes: 100)
        XCTAssertEqual(engine.wellbeing.recommendedRest, 20)
        XCTAssertEqual(engine.wellbeing.sessionsDone, 4)
        XCTAssertEqual(engine.wellbeing.sessionsGoal, 15)

        settings.currentMode = .hardcore
        XCTAssertEqual(settings.dailyGoal, 500)
        XCTAssertEqual(engine.wellbeing.sessionsGoal, 20)

        // Each mode keeps its own edits; editing one that is not in use changes nothing live.
        settings.update(.light) { $0.sessions = 12 }
        XCTAssertEqual(settings.dailyGoal, 500)
        settings.currentMode = .light
        XCTAssertEqual(settings.dailyGoal, 300)
        settings.update(.light) { $0.sessionMinutes = 20 }
        XCTAssertEqual(settings.focusMinutes, 20, "editing the mode in use applies at once")
        settings.reset(.light)
        XCTAssertEqual(settings.dailyGoal, 250)
    }

    /// A day off asks for nothing, keeps the working mode's numbers, and ends by itself the next day.
    func testDayOff() {
        engine.logPastFocus(minutes: 400)
        XCTAssertNotNil(engine.wellbeing.breakHint)
        settings.currentMode = .dayOff
        XCTAssertEqual(settings.dailyGoal, 360, "the working mode's numbers stay")
        XCTAssertEqual(settings.focusMinutes, 30)
        XCTAssertEqual(engine.wellbeing.mood, .dayOff)
        XCTAssertEqual(engine.wellbeing.energy, 1)
        XCTAssertNil(engine.wellbeing.breakHint)
        XCTAssertEqual(engine.wellbeing.advice, "Rest today. Back to work tomorrow.")
        XCTAssertEqual(settings.summary(for: .dayOff), "No goal, no reminders, until tomorrow")
        settings.update(.dayOff) { $0.sessions = 3 }
        XCTAssertEqual(settings.dailyGoal, 360, "a day off has nothing to edit")

        settings.endDayOffIfOver(now: Date())
        XCTAssertEqual(settings.currentMode, .dayOff, "still the same day")
        settings.endDayOffIfOver(now: Date().addingTimeInterval(24 * 3600))
        XCTAssertEqual(settings.currentMode, .moderate)
        XCTAssertNotEqual(engine.wellbeing.mood, .dayOff)
    }

    /// Settings saved by earlier versions held minutes of focus: they turn into sessions.
    func testOldModeSettingsBecomeSessions() throws {
        let old = #"{"focusGoal":360,"restGoal":120,"sessionMinutes":30,"breakMinutes":5}"#
        let mode = try JSONDecoder().decode(ModeSettings.self, from: Data(old.utf8))
        XCTAssertEqual(mode, ModeSettings(sessions: 12, sessionMinutes: 30, breakMinutes: 5))
        let again = try JSONDecoder().decode(ModeSettings.self, from: JSONEncoder().encode(mode))
        XCTAssertEqual(again, mode)
    }

    /// After an hour without a break the app suggests one; after half the day, a long one.
    func testBreakHints() {
        XCTAssertNil(Wellbeing(focusMinutes: 50, breakMinutes: 5, goal: 375, stretch: 50).breakHint)
        XCTAssertEqual(Wellbeing(focusMinutes: 60, breakMinutes: 0, goal: 375, stretch: 60).breakHint,
                       "1 h without a break. Time for a coffee.")
        let half = Wellbeing(focusMinutes: 190, breakMinutes: 35, goal: 375, stretch: 25, longestBreak: 5)
        XCTAssertEqual(half.breakHint, "3 h 10 min of focus today. Take a long break.")
        XCTAssertNil(Wellbeing(focusMinutes: 190, breakMinutes: 60, goal: 375, stretch: 25, longestBreak: 30).breakHint)
        // In Hardcore the long break is due after four hours, not after half of the ten.
        XCTAssertTrue(Wellbeing(focusMinutes: 240, breakMinutes: 40, goal: 500, stretch: 0, longestBreak: 10).longBreakIsDue)
        XCTAssertFalse(Wellbeing(focusMinutes: 230, breakMinutes: 40, goal: 500, stretch: 0, longestBreak: 10).longBreakIsDue)

        // In the engine: three sessions back to back, then the finish window brings the break forward.
        engine.startFocus(); advance(minutes: 30); engine.startFocus(); advance(minutes: 30)
        XCTAssertNotNil(engine.wellbeing.breakHint)
        XCTAssertEqual(engine.suggestedBreakMinutes, 5)
        engine.startBreak(minutes: 30); advance(minutes: 30); engine.stop()
        XCTAssertNil(engine.wellbeing.breakHint)
    }

    /// The whole away-from-the-desk story, answered from the phone at each step.
    func testPhoneStoryStepAwayAndComeBack() {
        XCTAssertEqual(PhonePush.buttons().map(\.label), ["+5 min", "+15 min", "+30 min"])
        engine.startFocus(); advance(minutes: 30)
        XCTAssertEqual(engine.runState, .finished)

        // Eight minutes later, at the coffee machine: "+15 min". The session is logged and a break runs
        // for fifteen more minutes; the eight already spent away count as rest too.
        advance(minutes: 8)
        let first = PhonePush.apply(.away(15), to: engine)
        XCTAssertTrue(first.applied)
        XCTAssertTrue(first.text.contains("15 more min. Ends at "))
        XCTAssertTrue(engine.phase.isBreak)
        XCTAssertEqual(engine.runState, .running)
        XCTAssertEqual(Int(engine.remaining), 900)
        XCTAssertEqual(ledger.entries.map(\.minutes), [30])
        XCTAssertEqual(engine.liveBreakMinutes, 8)
        advance(minutes: 15)
        XCTAssertEqual(engine.runState, .finished, "the break is over and waits for an answer")

        // Still away four minutes after that: "+5 min" carries the same break on.
        advance(minutes: 4)
        XCTAssertTrue(PhonePush.apply(.away(5), to: engine).applied)
        XCTAssertEqual(Int(engine.remaining), 300)
        advance(minutes: 5)

        // Back at the Mac: focus starts there. One break of 8 + 15 + 4 + 5 minutes is logged.
        engine.startFocus()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(ledger.breaks.map(\.minutes), [32])
        XCTAssertEqual(ledger.breaks.first.map { Int(engine.session!.start.timeIntervalSince($0.start)) }, 32 * 60)
    }

    func testPhoneCommands() {
        XCTAssertEqual(PhonePush.Command("away:15"), .away(15))
        XCTAssertEqual(PhonePush.Command(" Away:30\n"), .away(30))
        XCTAssertNil(PhonePush.Command("away:0"))
        XCTAssertNil(PhonePush.Command("rm -rf"))
        XCTAssertNil(PhonePush.Command(""))
        XCTAssertEqual(PhonePush.Command(PhonePush.Command.away(15).text), .away(15))
        // Buttons of notifications sent by an earlier version still work.
        XCTAssertEqual(PhonePush.Command("extend:5"), .extend(5))
        XCTAssertEqual(PhonePush.Command("break:60"), .rest(60))
        XCTAssertEqual(PhonePush.Command("complete"), .complete)

        // A running break gets longer; a running focus session ends and rest begins.
        engine.startBreak(minutes: 10); advance(minutes: 4)
        XCTAssertTrue(PhonePush.apply(.away(5), to: engine).applied)
        XCTAssertEqual(Int(engine.remaining), 660)
        engine.stop()
        engine.startFocus(); advance(minutes: 12)
        XCTAssertTrue(PhonePush.apply(.away(15), to: engine).applied)
        XCTAssertTrue(engine.phase.isBreak)
        XCTAssertEqual(ledger.entries.map(\.minutes), [12])
        XCTAssertEqual(engine.liveBreakMinutes, 0)
        // With nothing running the phone can still start a break.
        engine.stop()
        XCTAssertTrue(PhonePush.apply(.away(5), to: engine).applied)
        XCTAssertFalse(PhonePush.apply(.extend(5), to: { engine.stop(); return engine }()).applied, "nothing running, nothing to extend")
    }

    func testStartingANewSessionClosesThePreviousOne() {
        engine.startFocus(); advance(minutes: 30)
        engine.startFocus(); advance(minutes: 7)
        XCTAssertEqual(ledger.entries.map(\.minutes), [30])
        XCTAssertEqual(engine.todayCoins, 37)
        XCTAssertEqual(engine.todaySessions, 2)
    }

    func testOpenSessionSurvivesACrash() {
        engine.startFocus()
        advance(minutes: 17.2)
        // Simulate a crash: a new ledger and engine read the same directory.
        // The app comes back long after the countdown would have ended.
        clock.addTimeInterval(3 * 3600)
        let revived = Ledger(directory: directory)
        XCTAssertTrue(revived.entries.isEmpty)
        let engine2 = TimerEngine(settings: settings, ledger: revived, now: { self.clock }, startTicker: false)
        XCTAssertEqual(revived.entries.map(\.minutes), [17])
        XCTAssertEqual(engine2.phase, .idle)
    }

    func testRunningSessionResumesAfterRestart() {
        engine.startFocus()
        advance(minutes: 10)
        engine.extend(minutes: 15)
        clock.addTimeInterval(2 * 60) // restart takes two minutes; the countdown kept going
        let revived = Ledger(directory: directory)
        let engine2 = TimerEngine(settings: settings, ledger: revived, now: { self.clock }, startTicker: false)
        XCTAssertEqual(engine2.phase, .focus)
        XCTAssertEqual(engine2.runState, .running)
        XCTAssertEqual(engine2.remaining, 33 * 60, accuracy: 0.01)
        XCTAssertEqual(engine2.session?.extensions, [15])
        XCTAssertEqual(engine2.liveCoins, 12)
        XCTAssertTrue(revived.entries.isEmpty)
        clock.addTimeInterval(33 * 60); engine2.tick()
        engine2.stop()
        XCTAssertEqual(revived.entries.map(\.minutes), [45])
    }

    func testUnansweredPromptDoesNotCarryIntoTheNextDay() {
        engine.startFocus(minutes: 5)
        advance(minutes: 5)
        XCTAssertEqual(engine.runState, .finished)
        let yesterday = clock
        advance(minutes: 24 * 60)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.runState, .idle)
        XCTAssertEqual(engine.todayCoins, 0)
        XCTAssertEqual(ledger.coins(on: yesterday), 5)
    }

    func testLedgerPersistsAndAggregates() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock).addingTimeInterval(9 * 3600)
        for (offset, minutes) in [(0, 45), (0, 30), (1, 60), (2, 20), (4, 90)] {
            let start = calendar.date(byAdding: .day, value: -offset, to: today)!
            ledger.add(FocusEntry(start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                  minutes: minutes, baseMinutes: 30, extensions: []))
        }
        let reloaded = Ledger(directory: directory)
        XCTAssertEqual(reloaded.entries.count, 5)
        XCTAssertEqual(reloaded.coins(on: clock), 75)
        XCTAssertEqual(reloaded.allTimeCoins, 245)
        XCTAssertEqual(reloaded.streak(now: clock), 3)
        XCTAssertEqual(reloaded.dailyTotals(lastDays: 5, endingAt: clock).map(\.coins), [90, 0, 20, 60, 75])
        XCTAssertEqual(reloaded.bestDay()?.coins, 90)
    }

    func testFormatting() {
        XCTAssertEqual(Format.clock(24 * 60 + 12.4), "24:13")
        XCTAssertEqual(Format.clock(3600 + 4 * 60 + 13), "1:04:13")
        XCTAssertEqual(Format.clock(0), "00:00")
        XCTAssertEqual(Format.duration(minutes: 75), "1 h 15 min")
        XCTAssertEqual(AppSettings.parseExtensions("5, 10,15 ; 60 x 10"), [5, 10, 15, 60])
    }
}
