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

        var sampleWidths: [CGFloat] = []
        // Sample across all 7 weekdays and wide hour/minute forms (12:59 and 23:59)
        for dayOffset in 1...7 {
            for timeOffset in [46740.0, 86340.0] {
                let delta = Double(dayOffset) * 86400.0 - 86400.0 + timeOffset
                guard delta >= 86400.0, delta <= 604_800.0 else { continue }
                let sampleDate = now.addingTimeInterval(delta)
                let sample = OverviewCompactResetText.make(
                    resetsAt: sampleDate,
                    now: now,
                    calendar: calendar,
                    locale: locale).clock
                sampleWidths.append(measure(sample, font: font))
            }
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
}
