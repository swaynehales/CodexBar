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

        let clock = UsageFormatter.resetDescription(
            from: resetsAt,
            now: now,
            calendar: calendar,
            locale: locale)

        var timeStyle = Date.FormatStyle().hour().minute().locale(locale)
        timeStyle.calendar = calendar
        timeStyle.timeZone = calendar.timeZone
        var dateStyle = Date.FormatStyle().month(.abbreviated).day().locale(locale)
        dateStyle.calendar = calendar
        dateStyle.timeZone = calendar.timeZone
        let clockTime = resetsAt.formatted(timeStyle)
        let clockDate: String? = if calendar.isDate(resetsAt, inSameDayAs: now) {
            nil
        } else {
            resetsAt.formatted(dateStyle)
        }

        return OverviewCompactResetText(
            countdown: countdown,
            clock: clock,
            clockDate: clockDate,
            clockTime: clockTime)
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
