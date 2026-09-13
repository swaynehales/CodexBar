import Foundation
import Testing
@testable import CodexBar

struct OverviewCompactRefreshStatusTests {
    @Test func `percentage header follows display preference`() {
        #expect(OverviewCompactTableModel.percentageHeader(showUsed: true) == L("compact_header_used"))
        #expect(OverviewCompactTableModel.percentageHeader(showUsed: false) == L("compact_header_remaining"))
    }

    @Test func `only completed global refreshes replace the persisted record`() throws {
        let previous = OverviewCompactRefreshStatus(completedAt: Date(timeIntervalSince1970: 100), hadFailures: false)
        let next = Date(timeIntervalSince1970: 200)
        #expect(previous.recordingCompletion(isGlobal: false, completed: true, at: next, hadFailures: true) == previous)
        #expect(previous.recordingCompletion(isGlobal: true, completed: false, at: next, hadFailures: true) == previous)
        let updated = previous.recordingCompletion(isGlobal: true, completed: true, at: next, hadFailures: true)
        #expect(updated.completedAt == next)
        #expect(updated.hadFailures)
        #expect(try JSONDecoder()
            .decode(OverviewCompactRefreshStatus.self, from: JSONEncoder().encode(updated)) == updated)
    }

    @Test func `refresh label includes the date only on older days and discloses failures`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let record = OverviewCompactRefreshStatus(completedAt: date, hadFailures: false)
        let today = record.label(now: date, calendar: calendar, locale: Locale(identifier: "en_US"))
        let older = record.label(
            now: date.addingTimeInterval(86400),
            calendar: calendar,
            locale: Locale(identifier: "en_US"))
        #expect(today != older)
        let failed = OverviewCompactRefreshStatus(completedAt: date, hadFailures: true)
        #expect(failed.label(now: date, calendar: calendar, locale: Locale(identifier: "en_US"))
            .contains(L("compact_refresh_partial")))
    }
}
