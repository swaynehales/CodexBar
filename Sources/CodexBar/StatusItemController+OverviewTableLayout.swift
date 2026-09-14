import AppKit
import CodexBarCore

extension StatusItemController {
    func adoptRenderedOverviewLayout(in menu: NSMenu) {
        // A fresh-looking or temporarily stale menu can reopen without rebuilding its retained items.
        if let layout = menu.items.compactMap({ ($0.view as? OverviewGroupingContainer)?.tableLayout }).first {
            self.overviewDisplayState.layouts[ObjectIdentifier(menu)] = layout
        }
    }

    func overviewCompactLayout(for menu: NSMenu) -> OverviewCompactTableLayout {
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
        let headerFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let bodyFont = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.emphasisFontSize, weight: .semibold)

        func measure(_ text: String, font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        let usageChoices = OverviewDisplayAxis.usage.choices
        let usageHeaderWidth = (usageChoices.map { measure($0.uppercased(), font: headerFont) + 12 }.max() ?? 0)
        let bodyPercentageWidth = (tableRows.map { measure($0.usedText, font: bodyFont) } +
            tableRows.compactMap { $0.valueText.map { measure($0, font: bodyFont) } }).max() ?? 42
        let desiredPercentage = max(42, ceil(max(usageHeaderWidth, bodyPercentageWidth)))

        let resetChoices = OverviewDisplayAxis.resetTime.choices
        let resetHeaderWidth = (resetChoices.map { measure($0.uppercased(), font: headerFont) + 12 }.max() ?? 0)
        let weekdaySample = OverviewCompactResetText.make(
            resetsAt: Date().addingTimeInterval(86400),
            now: Date(),
            calendar: .current,
            locale: codexBarLocalizedLocale()).clock
        let sampleWeekdayWidth = measure(weekdaySample, font: font)
        let clockWidths = texts.map { measure($0.clock, font: font) } + [sampleWeekdayWidth, resetHeaderWidth]
        let maxClockWidth = clockWidths.max() ?? sampleWeekdayWidth
        let clockLineWidth = texts.flatMap { [$0.clockDate, $0.clockTime].compactMap(\.self).map { measure(
            $0,
            font: font) } }.max() ?? 0

        let screen = self.statusItems.values.first(where: { $0.menu === menu })?.button?.window?.screen
            ?? self.statusItem.button?.window?.screen
        let availableWidth = max(0, (screen?.visibleFrame.width ?? 1024) - 24)
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: availableWidth,
            percentageWidth: desiredPercentage,
            clockWidth: maxClockWidth,
            clockLineWidth: clockLineWidth)
        // NSMenu builds before menuWillOpen registers it in openMenus. Preserve that first budget too.
        self.overviewDisplayState.layouts[key] = layout
        return layout
    }
}
