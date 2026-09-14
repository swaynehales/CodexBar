import CodexBarCore
import Foundation

struct OverviewCompactResetText: Equatable, Sendable {
    let countdown: String
    let clock: String
    let clockDate: String?
    let clockTime: String?

    init(
        countdown: String,
        clock: String,
        clockDate: String? = nil,
        clockTime: String? = nil)
    {
        self.countdown = countdown
        self.clock = clock
        self.clockDate = clockDate
        self.clockTime = clockTime
    }

    static func make(
        resetsAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = codexBarLocalizedLocale()) -> OverviewCompactResetText
    {
        guard let resetsAt else {
            return OverviewCompactResetText(
                countdown: "—",
                clock: "—",
                clockDate: nil,
                clockTime: nil)
        }

        let countdownDesc = UsageFormatter.resetCountdownDescription(from: resetsAt, now: now)
        let countdown: String = if countdownDesc.hasPrefix("in ") {
            String(countdownDesc.dropFirst(3).split(separator: " ").first ?? "—")
        } else {
            countdownDesc
        }

        let delta = resetsAt.timeIntervalSince(now)

        if delta <= 0 {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.calendar = calendar
            formatter.locale = locale
            let localizedNow = formatter.localizedString(for: now, relativeTo: now).capitalized(with: locale)
            return OverviewCompactResetText(
                countdown: countdown,
                clock: localizedNow,
                clockDate: nil,
                clockTime: localizedNow)
        }

        var timeStyle = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        timeStyle.calendar = calendar
        timeStyle.timeZone = calendar.timeZone

        if delta < 86400 {
            let clockTime = resetsAt.formatted(timeStyle)
            return OverviewCompactResetText(
                countdown: countdown,
                clock: clockTime,
                clockDate: nil,
                clockTime: clockTime)
        }

        if delta <= 604_800 {
            var weekdayTimeStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute().locale(locale)
            weekdayTimeStyle.calendar = calendar
            weekdayTimeStyle.timeZone = calendar.timeZone

            var weekdayStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(locale)
            weekdayStyle.calendar = calendar
            weekdayStyle.timeZone = calendar.timeZone

            let clock = resetsAt.formatted(weekdayTimeStyle)
            let clockDate = resetsAt.formatted(weekdayStyle)
            let clockTime = resetsAt.formatted(timeStyle)

            return OverviewCompactResetText(
                countdown: countdown,
                clock: clock,
                clockDate: clockDate,
                clockTime: clockTime)
        }

        var monthDayStyle = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(locale)
        monthDayStyle.calendar = calendar
        monthDayStyle.timeZone = calendar.timeZone
        let clock = resetsAt.formatted(monthDayStyle)

        return OverviewCompactResetText(
            countdown: countdown,
            clock: clock,
            clockDate: clock,
            clockTime: nil)
    }

    func lines(showAbsolute: Bool, wrapClock: Bool) -> [String] {
        if !showAbsolute {
            return [self.countdown]
        }
        if wrapClock {
            if let clockDate = self.clockDate, let clockTime = self.clockTime {
                return [clockDate, clockTime]
            }
            if let clockTime = self.clockTime {
                return [clockTime]
            }
        }
        return [self.clock]
    }
}
