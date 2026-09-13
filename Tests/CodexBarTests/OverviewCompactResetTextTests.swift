import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct OverviewCompactResetTextTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private var locale: Locale {
        Locale(identifier: "en_US_POSIX")
    }

    @Test
    func `missing reset date produces em dash in all modes`() {
        let text = OverviewCompactResetText.make(
            resetsAt: nil,
            now: Date(),
            calendar: self.calendar,
            locale: self.locale)

        #expect(text.countdown == "—")
        #expect(text.clock == "—")
        #expect(text.clockDate == nil)
        #expect(text.clockTime == nil)

        #expect(text.lines(showAbsolute: false, wrapClock: false) == ["—"])
        #expect(text.lines(showAbsolute: false, wrapClock: true) == ["—"])
        #expect(text.lines(showAbsolute: true, wrapClock: false) == ["—"])
        #expect(text.lines(showAbsolute: true, wrapClock: true) == ["—"])
    }

    @Test
    func `today reset renders single line in both unwrapped and wrapped modes`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200)
        let resetsAt = now.addingTimeInterval(3.5 * 3600)

        let text = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text.countdown == "3h")
        #expect(text.clock == UsageFormatter.resetDescription(
            from: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale))
        #expect(text.clockDate == nil)
        #expect(text.clockTime != nil)

        #expect(text.lines(showAbsolute: false, wrapClock: false) == ["3h"])
        #expect(text.lines(showAbsolute: false, wrapClock: true) == ["3h"])
        #expect(text.lines(showAbsolute: true, wrapClock: false) == [text.clock])
        #expect(try text.lines(showAbsolute: true, wrapClock: true) == [#require(text.clockTime)])
    }

    @Test
    func `tomorrow reset wraps to two lines when wrapClock is enabled`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200)
        let resetsAt = Date(timeIntervalSince1970: 1_789_486_200)

        let text = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text.clock == UsageFormatter.resetDescription(
            from: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale))
        #expect(text.clockDate != nil)
        #expect(text.clockTime != nil)

        #expect(text.lines(showAbsolute: false, wrapClock: false) == [text.countdown])
        #expect(text.lines(showAbsolute: true, wrapClock: false) == [text.clock])
        #expect(try text.lines(showAbsolute: true, wrapClock: true) == [
            #require(text.clockDate),
            #require(text.clockTime),
        ])
    }

    @Test
    func `future day reset wraps to two lines when wrapClock is enabled`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200)
        let resetsAt = Date(timeIntervalSince1970: 1_789_992_000)

        let text = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text.countdown == "7d")
        #expect(text.clock == UsageFormatter.resetDescription(
            from: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale))
        #expect(text.clockDate != nil)
        #expect(text.clockTime != nil)

        #expect(text.lines(showAbsolute: true, wrapClock: false) == [text.clock])
        #expect(try text.lines(showAbsolute: true, wrapClock: true) == [
            #require(text.clockDate),
            #require(text.clockTime),
        ])
    }

    @Test
    func `expired reset date preserves existing formatter semantics`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200)

        // Expired earlier today (10:00:00 UTC)
        let earlierToday = Date(timeIntervalSince1970: 1_789_380_000)
        let textToday = OverviewCompactResetText.make(
            resetsAt: earlierToday,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(textToday.countdown == "now")
        #expect(textToday.clock == UsageFormatter.resetDescription(
            from: earlierToday,
            now: now,
            calendar: self.calendar,
            locale: self.locale))
        #expect(textToday.clockDate == nil)
        #expect(textToday.clockTime != nil)
        #expect(textToday.lines(showAbsolute: false, wrapClock: false) == ["now"])
        #expect(textToday.lines(showAbsolute: true, wrapClock: false) == [textToday.clock])
        #expect(try textToday.lines(showAbsolute: true, wrapClock: true) == [#require(textToday.clockTime)])

        // Expired on a previous day (2026-09-10 12:00:00 UTC)
        let pastDay = Date(timeIntervalSince1970: 1_789_128_000)
        let textPast = OverviewCompactResetText.make(
            resetsAt: pastDay,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(textPast.countdown == "now")
        #expect(textPast.clock == UsageFormatter.resetDescription(
            from: pastDay,
            now: now,
            calendar: self.calendar,
            locale: self.locale))
        #expect(textPast.clockDate != nil)
        #expect(textPast.clockTime != nil)
        #expect(textPast.lines(showAbsolute: false, wrapClock: false) == ["now"])
        #expect(textPast.lines(showAbsolute: true, wrapClock: false) == [textPast.clock])
        #expect(try textPast.lines(showAbsolute: true, wrapClock: true) == [
            #require(textPast.clockDate),
            #require(textPast.clockTime),
        ])
    }

    @Test
    func `countdown compact duration extracts largest unit`() {
        let now = Date(timeIntervalSince1970: 1_789_387_200)

        // 45 minutes ahead
        let in45m = now.addingTimeInterval(45 * 60)
        let text45m = OverviewCompactResetText.make(
            resetsAt: in45m,
            now: now,
            calendar: self.calendar,
            locale: self.locale)
        #expect(text45m.countdown == "45m")

        // 2 hours ahead
        let in2h = now.addingTimeInterval(2 * 3600)
        let text2h = OverviewCompactResetText.make(
            resetsAt: in2h,
            now: now,
            calendar: self.calendar,
            locale: self.locale)
        #expect(text2h.countdown == "2h")

        // 3 days ahead
        let in3d = now.addingTimeInterval(3 * 86400)
        let text3d = OverviewCompactResetText.make(
            resetsAt: in3d,
            now: now,
            calendar: self.calendar,
            locale: self.locale)
        #expect(text3d.countdown == "3d")
    }

    @Test
    func `clock formatting respects 12-hour and 24-hour locales`() {
        let now = Date(timeIntervalSince1970: 1_789_387_200)
        let resetsAt = now.addingTimeInterval(3.5 * 3600)

        // 12-hour locale: en_US
        let locale12 = Locale(identifier: "en_US")
        let text12 = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: locale12)
        #expect(text12.clockTime?.contains("PM") == true || text12.clockTime?.contains("p.m.") == true)

        // 24-hour locale: de_DE
        let locale24 = Locale(identifier: "de_DE")
        let text24 = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: locale24)
        #expect(text24.clockTime?.contains("15:30") == true)
        #expect(text24.clockTime?.contains("PM") == false)
    }

    @Test
    func `date context and timezone boundaries drive today versus another day determination`() throws {
        let now = Date(timeIntervalSince1970: 1_789_428_600)
        let resetsAt = Date(timeIntervalSince1970: 1_789_435_800)

        // The reset crosses midnight in UTC.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let textUTC = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: utcCalendar,
            locale: self.locale)
        #expect(textUTC.clockDate != nil)
        #expect(textUTC.lines(showAbsolute: true, wrapClock: true).count == 2)

        // In Asia/Tokyo (+9h):
        // Both instants are on the same day in Tokyo.
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let textTokyo = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: tokyoCalendar,
            locale: self.locale)
        #expect(textTokyo.clockDate == nil)
        #expect(textTokyo.lines(showAbsolute: true, wrapClock: true).count == 1)
    }
}
