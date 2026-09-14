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
        let texts = tableRows.map(\.resetText)
        let font = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.metadataFontSize, weight: .regular)
        let bodyFont = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.emphasisFontSize, weight: .semibold)

        func measure(_ text: String, font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        let usageHeaderWidth = Self.dropdownHeaderWidth(for: .usage)
        let bodyPercentageWidth = (tableRows.map { measure($0.usedText, font: bodyFont) } +
            tableRows.compactMap { $0.valueText.map { measure($0, font: bodyFont) } }).max() ?? 42
        let desiredPercentage = max(42, ceil(max(usageHeaderWidth, bodyPercentageWidth)))

        let resetHeaderWidth = Self.dropdownHeaderWidth(for: .resetTime)
        let calendar = Calendar.current
        let locale = codexBarLocalizedLocale()

        let sampleDates = Self.candidateResetSampleDates(now: now, calendar: calendar)
        let sampleWidths = sampleDates.map { sampleDate in
            let sample = OverviewCompactResetText.make(
                resetsAt: sampleDate,
                now: now,
                calendar: calendar,
                locale: locale).clock
            return measure(sample, font: font)
        }
        let maxWeekdayWidth = sampleWidths.max() ?? 0
        let clockWidths = texts.map { measure($0.clock, font: font) } + [maxWeekdayWidth, resetHeaderWidth]
        let maxClockWidth = clockWidths.max() ?? maxWeekdayWidth
        let clockLineWidth = (texts.flatMap { [$0.clockDate, $0.clockTime].compactMap(\.self).map { measure(
            $0,
            font: font) } } + [resetHeaderWidth]).max() ?? resetHeaderWidth

        let screen = self.statusItems.values.first(where: { $0.menu === menu })?.button?.window?.screen
            ?? self.statusItem.button?.window?.screen
        let availableWidth = max(0, (screen?.visibleFrame.width ?? 1024) - 24)
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: availableWidth,
            percentageWidth: desiredPercentage,
            clockWidth: maxClockWidth,
            clockLineWidth: clockLineWidth,
            headerWidth: resetHeaderWidth)
        // NSMenu builds before menuWillOpen registers it in openMenus. Preserve that first budget too.
        self.overviewDisplayState.layouts[key] = layout
        return layout
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
