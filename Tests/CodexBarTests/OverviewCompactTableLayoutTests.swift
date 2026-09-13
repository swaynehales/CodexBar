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
            availableWidth: 1000, clockWidth: 120, clockLineWidth: 64, controlWidths: [170, 190])
        #expect(wide.width == 468)
        #expect(wide.resetWidth == 130)
        #expect(wide.barWidth(leading: 84) == 176)
        #expect(wide.barWidth(leading: 112) == 148)
        #expect(!wide.stacksControls)
        let narrow = OverviewCompactTableLayout.resolve(
            availableWidth: 380, clockWidth: 120, clockLineWidth: 64, controlWidths: [220, 240])
        #expect(narrow.width == 380)
        #expect(narrow.resetWidth >= 64)
        #expect(narrow.wrapClock)
        #expect(narrow.stacksControls)
        #expect(narrow.barWidth(leading: 112) > 0)
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
            rows: [row], width: 380, showAbsolute: false, resetWidth: 80, wrapClock: true))
        let clock = NSHostingView(rootView: OverviewCompactTableBlockView(
            rows: [row], width: 380, showAbsolute: true, resetWidth: 80, wrapClock: true))
        #expect(countdown.fittingSize.width == clock.fittingSize.width)
        #expect(clock.fittingSize.height > countdown.fittingSize.height)
    }

    @Test
    func `long clock strings expand the budget while widths stay nonnegative`() {
        let layout = OverviewCompactTableLayout.resolve(
            availableWidth: 1000, clockWidth: 200, clockLineWidth: 95, controlWidths: [180, 200])
        #expect(layout.width == 546)
        #expect(layout.resetWidth == 208)
        #expect(layout.barWidth(leading: 84) == 176)
        #expect(layout.barWidth(leading: 112) == 148)
        let constrained = OverviewCompactTableLayout.resolve(
            availableWidth: 200, clockWidth: 200, clockLineWidth: 95, controlWidths: [180, 200])
        #expect(constrained.resetWidth >= 0)
        #expect(constrained.barWidth(leading: 112) >= 0)
        #expect(constrained.width <= 200)
    }
}
