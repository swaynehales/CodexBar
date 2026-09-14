import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct OverviewCompactTableLayoutTests {
    @Test
    func `clock budget preserves bar widths and narrow screens wrap`() {
        let wide = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50,
            headerWidth: 90)
        #expect(wide.width == 468)
        #expect(wide.resetWidth == 94)
        #expect(wide.barWidth(leading: 84) == 176)
        #expect(wide.barWidth(leading: 112) == 148)
        #expect(!wide.wrapClock)

        let narrow = OverviewCompactTableLayout.resolve(
            availableWidth: 380,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50,
            headerWidth: 90)
        #expect(narrow.width == 380)
        #expect(narrow.resetWidth >= 90)
        #expect(narrow.wrapClock)
        #expect(narrow.barWidth(leading: 112) >= 0)
    }

    @Test
    func `header and body columns share exact anchors in both groupings`() {
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50,
            headerWidth: 90)

        let gaps: CGFloat = 3 * CompactTableMetrics.columnSpacing
        let padding: CGFloat = 2 * CompactTableMetrics.horizontalPadding

        let providerBar = layout.barWidth(leading: CompactTableMetrics.periodColumnWidth)
        let totalProvider = CompactTableMetrics.periodColumnWidth + providerBar + layout.percentageWidth + layout
            .resetWidth + gaps + padding
        #expect(totalProvider == layout.width)
        #expect(providerBar == 176)

        let periodBar = layout.barWidth(leading: CompactTableMetrics.providerMaxWidth)
        let totalPeriod = CompactTableMetrics.providerMaxWidth + periodBar + layout.percentageWidth + layout
            .resetWidth + gaps + padding
        #expect(totalPeriod == layout.width)
        #expect(periodBar == 148)
    }

    @Test
    func `both option title widths fit within derived column budgets`() {
        let usageWidth = StatusItemController.dropdownHeaderWidth(for: .usage)
        let resetWidth = StatusItemController.dropdownHeaderWidth(for: .resetTime)

        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: usageWidth,
            clockWidth: resetWidth,
            clockLineWidth: 50,
            headerWidth: resetWidth)

        #expect(usageWidth <= layout.percentageWidth)
        #expect(resetWidth <= layout.resetWidth)
    }

    @Test
    func `shorter reset budgets reduce popover width compared to legacy 130pt minimum`() {
        // Legacy layout had unconditional 130pt reset minimum with 42pt percentage:
        // width = 296 + 42 + 130 = 468pt.
        // New layout derives resetWidth (94pt) from concise English clock (~86pt + 8pt)
        // and percentageWidth (78pt) for "REMAINING" dropdown:
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50,
            headerWidth: 90)

        #expect(layout.resetWidth == 94) // 36pt narrower reset column
        #expect(layout.resetWidth < 130)
        #expect(layout.width == 468)
        #expect(layout.barWidth(leading: 84) == 176)
        #expect(layout.barWidth(leading: 112) == 148)
    }

    @Test
    func `wrapped clock increases row height without widening the grid`() {
        let row = CompactTableRow(
            id: "example",
            provider: .codex,
            providerDisplayName: "Codex",
            showProvider: true,
            model: "",
            period: .weekly,
            periodLabel: "Week",
            presentation: .value,
            percent: 0,
            valueText: nil,
            statusText: nil,
            usedText: "—",
            resetText: OverviewCompactResetText(
                countdown: "7d", clock: "Sep 20 at 10:30 AM", clockDate: "Sep 20", clockTime: "10:30 AM"),
            resetsAt: nil,
            tint: ProviderAccentPalette.color(for: .codex),
            metric: nil)
        let countdown = NSHostingView(rootView: OverviewCompactTableBlockView(
            rows: [row], width: 380, showAbsolute: false, percentageWidth: 71, resetWidth: 80, wrapClock: true))
        let clock = NSHostingView(rootView: OverviewCompactTableBlockView(
            rows: [row], width: 380, showAbsolute: true, percentageWidth: 71, resetWidth: 80, wrapClock: true))
        #expect(countdown.fittingSize.width == clock.fittingSize.width)
        #expect(clock.fittingSize.height > countdown.fittingSize.height)
    }

    @Test
    func `long clock strings expand the budget while widths stay nonnegative`() {
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 71,
            clockWidth: 200,
            clockLineWidth: 95)
        #expect(layout.width == 575) // 296 + 71 + 208 = 575
        #expect(layout.resetWidth == 208)
        #expect(layout.barWidth(leading: 84) == 176)
        #expect(layout.barWidth(leading: 112) == 148)

        let constrained = OverviewCompactTableLayout.resolve(
            availableWidth: 200,
            percentageWidth: 71,
            clockWidth: 200,
            clockLineWidth: 95)
        #expect(constrained.resetWidth >= 0)
        #expect(constrained.barWidth(leading: 112) >= 0)
        #expect(constrained.width <= 200)
    }
}
