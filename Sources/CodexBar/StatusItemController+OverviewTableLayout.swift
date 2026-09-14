import AppKit
import CodexBarCore

extension StatusItemController {
    func adoptRenderedOverviewLayout(in menu: NSMenu) {
        // A fresh-looking or temporarily stale menu can reopen without rebuilding its retained items.
        if let layout = menu.items.compactMap({ ($0.view as? OverviewGroupingContainer)?.tableLayout }).first {
            self.overviewDisplayState.layouts[ObjectIdentifier(menu)] = layout
        }
    }

    func overviewCompactLayout(for menu: NSMenu, now: Date = Date()) -> OverviewCompactTableLayout {
        let key = ObjectIdentifier(menu)
        if let layout = self.overviewDisplayState.layouts[key] {
            return layout
        }
        let providers = self.store.enabledProvidersForDisplay().compactMap(\.firstPartyProvider)
        let rows = self.overviewProviderScopes(enabledProviders: providers).visible.compactMap { provider in
            self.menuCardModel(for: provider).map { (provider: provider, model: $0) }
        }
        let tableRows = self.overviewDisplayRows(rows: rows, compactEnabled: true)
            .compactMap(\.tableRows).flatMap(\.self)
        let font = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.metadataFontSize, weight: .regular)
        let bodyFont = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.emphasisFontSize, weight: .semibold)

        func measure(_ text: String, font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        // Percentage budget: the widest used value or a full-scale 100%, plus modest
        // padding. Balance strings keep their existing truncation and never inflate
        // this budget; header titles never participate.
        let bodyPercentageWidth = tableRows.map { measure($0.usedText, font: bodyFont) }.max() ?? 0
        let fullScaleWidth = measure("100%", font: bodyFont)
        let desiredPercentage = ceil(max(bodyPercentageWidth, fullScaleWidth)) + 8

        // Reset budget: row countdown/clock strings plus exemplar CLOCK strings rendered
        // through the real formatter, so every compact tier is covered in the current
        // locale. Distant exemplar countdowns stay out of the budget: only actual rows
        // size the countdown column. One budget across countdown/clock modes.
        let calendar = Calendar.current
        let locale = codexBarLocalizedLocale()
        let rowTexts = tableRows.map(\.resetText)
        let exemplarClocks = Self.compactResetTierExemplars(now: now, calendar: calendar, locale: locale)
            .map(\.clock)
        let maxResetWidth = (rowTexts.flatMap { [$0.countdown, $0.clock] } + exemplarClocks)
            .map { measure($0, font: font) }.max() ?? 0
        let clockLineWidth = (rowTexts.flatMap { [$0.clockDate, $0.clockTime].compactMap(\.self) } +
            exemplarClocks)
            .map { measure($0, font: font) }.max() ?? 0

        let screen = self.statusItems.values.first(where: { $0.menu === menu })?.button?.window?.screen
            ?? self.statusItem.button?.window?.screen
        let availableWidth = max(0, (screen?.visibleFrame.width ?? 1024) - 24)
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: availableWidth,
            percentageWidth: desiredPercentage,
            clockWidth: maxResetWidth,
            clockLineWidth: clockLineWidth)
        // NSMenu builds before menuWillOpen registers it in openMenus. Preserve that first budget too.
        self.overviewDisplayState.layouts[key] = layout
        return layout
    }

    /// Tier exemplar dates rendered through the real reset formatter so the reset budget
    /// covers every compact tier in the current locale: time-only extremes, all seven
    /// weekdays, all twelve month/day forms, Now, and the missing date.
    static func compactResetTierExemplars(now: Date, calendar: Calendar, locale: Locale) -> [OverviewCompactResetText] {
        var dates: [Date] = []
        let startOfDay = calendar.startOfDay(for: now)
        // Guaranteed future time-only samples: today and tomorrow each contribute the
        // 12:59/23:59 times that still fall inside 0 < delta < 86,400, so every anchor
        // (including late night, when both of today's times are past) yields at least
        // one time-only exemplar.
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for (hour, minute) in [(12, 59), (23, 59)] {
                if let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                    let delta = candidate.timeIntervalSince(now)
                    if delta > 0, delta < 86400 {
                        dates.append(candidate)
                    }
                }
            }
        }
        dates += Self.candidateResetSampleDates(now: now, calendar: calendar)
        let year = calendar.component(.year, from: now)
        for month in 1...12 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 15
            components.hour = 12
            if let date = calendar.date(from: components) {
                // Mid-month dates in the past still sample a valid tier; push them a year
                // out so every month/day form is represented past the 7-day tier.
                if date.timeIntervalSince(now) > 604_800 {
                    dates.append(date)
                } else if let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
                    dates.append(nextYear)
                }
            }
        }
        dates.append(now.addingTimeInterval(-1))
        var texts = dates.map {
            OverviewCompactResetText.make(resetsAt: $0, now: now, calendar: calendar, locale: locale)
        }
        texts.append(OverviewCompactResetText.make(resetsAt: nil, now: now, calendar: calendar, locale: locale))
        return texts
    }

    static func candidateResetSampleDates(now: Date, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        let startOfDay = calendar.startOfDay(for: now)

        // Generate candidate local times for the next 8 days at 12:59:00 and 23:59:00
        for dayOffset in 1...8 {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for (hour, minute) in [(12, 59), (23, 59)] {
                if let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayDate) {
                    let delta = candidate.timeIntervalSince(now)
                    if delta >= 86400, delta <= 604_800 {
                        dates.append(candidate)
                    }
                }
            }
        }

        // Include exact +7d boundary (604,800s)
        let exactSevenDays = now.addingTimeInterval(604_800)
        dates.append(exactSevenDays)

        return dates
    }
}
