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
            clockLineWidth: 50)
        #expect(wide.width == 462)
        #expect(wide.resetWidth == 94)
        #expect(wide.barWidth(leading: 84) == 170)
        #expect(wide.barWidth(leading: 112) == 142)
        #expect(!wide.wrapClock)

        let narrow = OverviewCompactTableLayout.resolve(
            availableWidth: 380,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50)
        #expect(narrow.width == 380)
        #expect(narrow.resetWidth == 58)
        #expect(narrow.wrapClock)
        #expect(narrow.barWidth(leading: 112) >= 0)
    }

    @Test
    func `header and body columns share exact anchors in both groupings`() {
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 78,
            clockWidth: 86,
            clockLineWidth: 50)

        // Shared 84pt leading column: both groupings resolve identical bars.
        #expect(CompactTableMetrics.providerMaxWidth == CompactTableMetrics.periodColumnWidth)
        #expect(CompactTableMetrics.providerMaxWidth == 84)

        let gaps: CGFloat = 3 * CompactTableMetrics.columnSpacing
        let padding: CGFloat = 2 * CompactTableMetrics.horizontalPadding

        let providerBar = layout.barWidth(leading: CompactTableMetrics.periodColumnWidth)
        let totalProvider = CompactTableMetrics.periodColumnWidth + providerBar + layout.percentageWidth + layout
            .resetWidth + gaps + padding
        #expect(totalProvider == layout.width)
        #expect(providerBar == 170)

        let periodBar = layout.barWidth(leading: CompactTableMetrics.providerMaxWidth)
        #expect(periodBar == providerBar)
        let totalPeriod = CompactTableMetrics.providerMaxWidth + periodBar + layout.percentageWidth + layout
            .resetWidth + gaps + padding
        #expect(totalPeriod == layout.width)
    }

    @Test
    func `tier exemplars cover every compact clock tier without weekday time`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_789_387_200)
        let exemplars = StatusItemController.compactResetTierExemplars(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"))
        let clocks = exemplars.map(\.clock)
        #expect(!exemplars.isEmpty)
        // Missing-date tier present; every tier renders on one short line.
        #expect(clocks.contains("—"))
        #expect(clocks.allSatisfy { $0.count <= 12 })
    }

    @Test
    func `tier exemplars always include a future time-only sample`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // Late-night anchor: both of today's 12:59/23:59 are already past.
        let lateNight = Date(timeIntervalSince1970: 1_789_428_600) // Monday 23:30 UTC
        let midday = Date(timeIntervalSince1970: 1_789_387_200 + 7200) // Monday 14:00 UTC
        for localeID in ["en_US_POSIX", "de_DE"] {
            let locale = Locale(identifier: localeID)
            for anchor in [lateNight, midday] {
                let clocks = StatusItemController.compactResetTierExemplars(
                    now: anchor,
                    calendar: calendar,
                    locale: locale).map(\.clock)
                #expect(
                    clocks.contains(where: { $0.contains(":") }),
                    "no time-only exemplar for \(anchor) in \(localeID)")
            }
        }
    }

    @Test
    func `shorter reset budgets reduce popover width compared to legacy 130pt minimum`() {
        // Legacy layout had unconditional 130pt reset minimum with 42pt percentage:
        // width = 296 + 42 + 130 = 468pt.
        // Content layout derives resetWidth (68pt) from concise English clock (~60pt + 8pt)
        // and keeps the measured 42pt percentage budget:
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000,
            percentageWidth: 42,
            clockWidth: 60,
            clockLineWidth: 30)

        #expect(layout.resetWidth == 68)
        #expect(layout.resetWidth < 130)
        #expect(layout.width == 400)
        #expect(layout.barWidth(leading: 84) == 170)
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
        #expect(layout.width == 569) // 290 + 71 + 208 = 569
        #expect(layout.resetWidth == 208)
        #expect(layout.barWidth(leading: 84) == 170)
        #expect(layout.barWidth(leading: 84) == layout.barWidth(leading: CompactTableMetrics.providerMaxWidth))

        let constrained = OverviewCompactTableLayout.resolve(
            availableWidth: 200,
            percentageWidth: 71,
            clockWidth: 200,
            clockLineWidth: 95)
        #expect(constrained.resetWidth >= 0)
        #expect(constrained.barWidth(leading: CompactTableMetrics.providerMaxWidth) >= 0)
        #expect(constrained.width <= 200)
    }
}
