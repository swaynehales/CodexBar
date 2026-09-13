import Foundation

/// Last completed manual all-provider quota refresh, independent of per-provider snapshot dates.
struct OverviewCompactRefreshStatus: Codable, Equatable {
    static let defaultsKey = "overviewCompactGlobalRefreshStatus"
    let completedAt: Date
    let hadFailures: Bool

    func recordingCompletion(
        isGlobal: Bool,
        completed: Bool,
        at date: Date,
        hadFailures: Bool) -> Self
    {
        guard isGlobal, completed else { return self }
        return Self(completedAt: date, hadFailures: hadFailures)
    }

    func label(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = calendar.isDate(self.completedAt, inSameDayAs: now) ? .none : .medium
        formatter.timeStyle = .short
        let time = formatter.string(from: self.completedAt)
        if self.hadFailures {
            return L("compact_refresh_completed", time) + " · " + L("compact_refresh_partial")
        }
        return L("compact_refresh_updated", time)
    }
}
