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
    func `delta negative and zero produces localized now`() {
        let now = Date(timeIntervalSince1970: 1_789_387_200)

        // Zero delta (resetsAt == now)
        let textZero = OverviewCompactResetText.make(
            resetsAt: now,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(textZero.countdown == "now")
        #expect(textZero.clock == "Now")
        #expect(textZero.clockDate == nil)
        #expect(textZero.clockTime == "Now")
        #expect(textZero.lines(showAbsolute: true, wrapClock: false) == ["Now"])
        #expect(textZero.lines(showAbsolute: true, wrapClock: true) == ["Now"])
        #expect(textZero.lines(showAbsolute: false, wrapClock: false) == ["now"])

        // Negative delta (resetsAt earlier today)
        let earlierToday = now.addingTimeInterval(-3600)
        let textEarlier = OverviewCompactResetText.make(
            resetsAt: earlierToday,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(textEarlier.countdown == "now")
        #expect(textEarlier.clock == "Now")
        #expect(textEarlier.clockDate == nil)
        #expect(textEarlier.clockTime == "Now")
        #expect(textEarlier.lines(showAbsolute: true, wrapClock: false) == ["Now"])
        #expect(textEarlier.lines(showAbsolute: true, wrapClock: true) == ["Now"])

        // Negative delta (resetsAt on a previous day)
        let pastDay = now.addingTimeInterval(-100_000)
        let textPast = OverviewCompactResetText.make(
            resetsAt: pastDay,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(textPast.countdown == "now")
        #expect(textPast.clock == "Now")
        #expect(textPast.clockDate == nil)
        #expect(textPast.clockTime == "Now")
        #expect(textPast.lines(showAbsolute: true, wrapClock: false) == ["Now"])
        #expect(textPast.lines(showAbsolute: true, wrapClock: true) == ["Now"])
    }

    @Test
    func `delta boundaries 1s and 86399s produce time only`() {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // Monday 12:00:00 UTC

        // delta = 1 second
        let plus1s = now.addingTimeInterval(1)
        let text1s = OverviewCompactResetText.make(
            resetsAt: plus1s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text1s.clockDate == nil)
        #expect(text1s.clockTime != nil)
        #expect(text1s.clock == text1s.clockTime)
        #expect(text1s.lines(showAbsolute: true, wrapClock: false) == [text1s.clock])
        #expect(text1s.lines(showAbsolute: true, wrapClock: true) == [text1s.clock])

        // delta = 86,399 seconds (23h 59m 59s)
        let plus86399s = now.addingTimeInterval(86399)
        let text86399s = OverviewCompactResetText.make(
            resetsAt: plus86399s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text86399s.clockDate == nil)
        #expect(text86399s.clockTime != nil)
        #expect(text86399s.clock == text86399s.clockTime)
        #expect(text86399s.lines(showAbsolute: true, wrapClock: false) == [text86399s.clock])
        #expect(text86399s.lines(showAbsolute: true, wrapClock: true) == [text86399s.clock])
    }

    @Test
    func `delta boundaries 86400s and 86401s produce abbreviated weekday and time`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // Monday 12:00:00 UTC

        // delta = 86,400 seconds (exactly 24 hours -> Tuesday 12:00:00 UTC)
        let plus86400s = now.addingTimeInterval(86400)
        let text86400s = OverviewCompactResetText.make(
            resetsAt: plus86400s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text86400s.clockDate != nil)
        #expect(text86400s.clockTime != nil)
        #expect(text86400s.clock.contains("Tue"))
        #expect(text86400s.lines(showAbsolute: true, wrapClock: false) == [text86400s.clock])
        #expect(try text86400s.lines(showAbsolute: true, wrapClock: true) == [
            #require(text86400s.clockDate),
            #require(text86400s.clockTime),
        ])

        // delta = 86,401 seconds
        let plus86401s = now.addingTimeInterval(86401)
        let text86401s = OverviewCompactResetText.make(
            resetsAt: plus86401s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text86401s.clockDate != nil)
        #expect(text86401s.clockTime != nil)
        #expect(text86401s.clock.contains("Tue"))
        #expect(text86401s.lines(showAbsolute: true, wrapClock: false) == [text86401s.clock])
        #expect(try text86401s.lines(showAbsolute: true, wrapClock: true) == [
            #require(text86401s.clockDate),
            #require(text86401s.clockTime),
        ])
    }

    @Test
    func `delta boundaries 604799s and 604800s produce abbreviated weekday and time`() throws {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // Monday 12:00:00 UTC

        // delta = 604,799 seconds (6 days 23 hours 59 mins 59 secs)
        let plus604799s = now.addingTimeInterval(604_799)
        let text604799s = OverviewCompactResetText.make(
            resetsAt: plus604799s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text604799s.clockDate != nil)
        #expect(text604799s.clockTime != nil)
        #expect(text604799s.lines(showAbsolute: true, wrapClock: false) == [text604799s.clock])
        #expect(try text604799s.lines(showAbsolute: true, wrapClock: true) == [
            #require(text604799s.clockDate),
            #require(text604799s.clockTime),
        ])

        // delta = 604,800 seconds (exactly 7 days -> Monday 12:00:00 UTC next week)
        let plus604800s = now.addingTimeInterval(604_800)
        let text604800s = OverviewCompactResetText.make(
            resetsAt: plus604800s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text604800s.clockDate != nil)
        #expect(text604800s.clockTime != nil)
        #expect(text604800s.clock.contains("Mon"))
        #expect(text604800s.lines(showAbsolute: true, wrapClock: false) == [text604800s.clock])
        #expect(try text604800s.lines(showAbsolute: true, wrapClock: true) == [
            #require(text604800s.clockDate),
            #require(text604800s.clockTime),
        ])
    }

    @Test
    func `delta boundary 604801s produces abbreviated month and day only`() {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // 2026-09-14 12:00:00 UTC

        // delta = 604,801 seconds (7 days + 1 second -> 2026-09-21)
        let plus604801s = now.addingTimeInterval(604_801)
        let text604801s = OverviewCompactResetText.make(
            resetsAt: plus604801s,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text604801s.clockTime == nil)
        #expect(text604801s.clock.contains("Sep"))
        #expect(text604801s.clock.contains("21"))
        #expect(text604801s.clockDate == text604801s.clock)
        #expect(text604801s.lines(showAbsolute: true, wrapClock: false) == [text604801s.clock])
        #expect(text604801s.lines(showAbsolute: true, wrapClock: true) == [text604801s.clock])
    }

    @Test
    func `future reset after midnight but under 24 hours produces time only`() {
        // 2026-09-14 23:30:00 UTC
        let now = Date(timeIntervalSince1970: 1_789_428_600)
        // 2026-09-15 01:30:00 UTC (crossing midnight, delta = 7,200s < 86,400s)
        let resetsAt = Date(timeIntervalSince1970: 1_789_435_800)

        let text = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: self.locale)

        #expect(text.clockDate == nil)
        #expect(text.clockTime != nil)
        #expect(text.clock == text.clockTime)
        #expect(text.lines(showAbsolute: true, wrapClock: false) == [text.clock])
        #expect(text.lines(showAbsolute: true, wrapClock: true) == [text.clock])
    }

    @Test
    func `daylight saving time crossing respects elapsed delta thresholds`() throws {
        var pacificCal = Calendar(identifier: .gregorian)
        pacificCal.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let locale = Locale(identifier: "en_US")

        // 2026-03-08 01:00 PST (spring forward occurs at 02:00 -> 03:00)
        // 2026-03-08 01:00 PST = 2026-03-08 09:00:00 UTC (1772960400)
        let now = Date(timeIntervalSince1970: 1_772_960_400)

        // Reset at 03:30 PDT (delta = 5,400 elapsed seconds < 86,400)
        let resetsAtShort = now.addingTimeInterval(5400)
        let textShort = OverviewCompactResetText.make(
            resetsAt: resetsAtShort,
            now: now,
            calendar: pacificCal,
            locale: locale)

        #expect(textShort.clockDate == nil)
        #expect(textShort.clockTime?.contains("3:30") == true)
        #expect(textShort.lines(showAbsolute: true, wrapClock: true).count == 1)

        // Reset at 86,400 elapsed seconds (exactly 24h later) -> Monday 02:00 PDT
        let resetsAt24h = now.addingTimeInterval(86400)
        let text24h = OverviewCompactResetText.make(
            resetsAt: resetsAt24h,
            now: now,
            calendar: pacificCal,
            locale: locale)

        #expect(text24h.clockDate != nil)
        #expect(text24h.clockTime != nil)
        #expect(text24h.clock.contains("Mon"))
        #expect(text24h.lines(showAbsolute: true, wrapClock: true).count == 2)
    }

    @Test
    func `year crossing with delta beyond seven days produces month and day only without year`() {
        // 2026-12-30 12:00:00 UTC
        let now = Date(timeIntervalSince1970: 1_798_632_000)
        // 2027-01-15 12:00:00 UTC (delta = 16 days > 604,800s)
        let resetsAt = Date(timeIntervalSince1970: 1_800_014_400)

        let text = OverviewCompactResetText.make(
            resetsAt: resetsAt,
            now: now,
            calendar: self.calendar,
            locale: Locale(identifier: "en_US"))

        #expect(text.clockTime == nil)
        #expect(text.clock.contains("Jan"))
        #expect(text.clock.contains("15"))
        #expect(text.clock.contains("2026") == false)
        #expect(text.clock.contains("2027") == false)
        #expect(text.lines(showAbsolute: true, wrapClock: false) == [text.clock])
        #expect(text.lines(showAbsolute: true, wrapClock: true) == [text.clock])
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
}
