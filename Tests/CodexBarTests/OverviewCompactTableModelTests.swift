import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

struct OverviewCompactTableModelTests {
    private static let now = Date(timeIntervalSince1970: 1_750_000_000)

    private static func metric(
        id: String,
        title: String = "Weekly",
        percent: Double = 19,
        statusText: String? = nil,
        resetsAt: Date? = nil) -> UsageMenuCardView.Model.Metric
    {
        UsageMenuCardView.Model.Metric(
            id: id,
            title: title,
            percent: percent,
            percentStyle: .used,
            statusText: statusText,
            resetText: nil,
            detailText: nil,
            detailLeftText: nil,
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true,
            resetsAt: resetsAt)
    }

    private static func model(
        provider: UsageProvider = .codex,
        name: String = "Codex",
        metrics: [UsageMenuCardView.Model.Metric] = [],
        planText: String? = nil) -> UsageMenuCardView.Model
    {
        UsageMenuCardView.Model(
            provider: provider,
            providerName: name,
            email: "",
            subtitleText: "",
            subtitleStyle: .info,
            planText: planText,
            metrics: metrics,
            usageNotes: [],
            openAIAPIUsage: nil,
            inlineUsageDashboard: nil,
            creditsText: nil,
            creditsRemaining: nil,
            creditsProgressPercent: nil,
            creditsScaleText: nil,
            creditsHintText: nil,
            creditsHintCopyText: nil,
            providerCost: nil,
            tokenUsage: nil,
            placeholder: nil,
            progressColor: .blue)
    }

    private static func snapshot(
        primary: RateWindow? = nil,
        secondary: RateWindow? = nil,
        extraRateWindows: [NamedRateWindow]? = nil,
        loginMethod: String? = nil,
        provider: UsageProvider = .codex) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: primary,
            secondary: secondary,
            extraRateWindows: extraRateWindows,
            updatedAt: self.now,
            identity: loginMethod.map {
                ProviderIdentitySnapshot(
                    providerID: provider.instanceID,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: $0)
            })
    }

    private func window(minutes: Int?) -> RateWindow {
        RateWindow(usedPercent: 10, windowMinutes: minutes, resetsAt: nil, resetDescription: nil)
    }

    @Test
    func `lane rows classify by provider and slot`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .codex,
            model: Self.model(metrics: [Self.metric(id: "primary"), Self.metric(id: "secondary")]),
            snapshot: Self.snapshot(),
            now: Self.now)
        #expect(rows.count == 2)
        #expect(rows[0].model == "All")
        #expect(rows[0].period == .session)
        #expect(rows[1].period == .weekly)
        #expect(rows[0].presentation == .bar)
        #expect(rows[0].usedText == "19%")
        #expect(rows[0].showProvider == true)
        #expect(rows[1].showProvider == false)
    }

    @Test
    func `kimi secondary lane is a session row`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .kimi,
            model: Self.model(provider: .kimi, name: "Kimi", metrics: [Self.metric(id: "secondary")]),
            snapshot: Self.snapshot(provider: .kimi),
            now: Self.now)
        #expect(rows.count == 1)
        #expect(rows[0].period == .session)
    }

    @Test
    func `extras resolve through the snapshot and unknown ids fall to other`() {
        let extra = NamedRateWindow(
            id: "factory-core-7d",
            title: "Core 7-day",
            window: self.window(minutes: 7 * 24 * 60))
        let mystery = NamedRateWindow(id: "something-new", title: "New", window: self.window(minutes: 2880))
        let rows = OverviewCompactTableModel.rows(
            provider: .factory,
            model: Self.model(
                provider: .factory,
                name: "Droid",
                metrics: [Self.metric(id: "factory-core-7d"), Self.metric(id: "something-new")]),
            snapshot: Self.snapshot(extraRateWindows: [extra, mystery], provider: .factory),
            now: Self.now)
        #expect(rows.count == 2)
        #expect(rows[0].model == "Core")
        #expect(rows[0].period == .weekly)
        #expect(rows[1].model == "All")
        #expect(rows[1].period == .other)
    }

    @Test
    func `status text becomes a value row and diagnostics are dropped`() {
        let offline = NamedRateWindow(
            id: "antigravity-offline-conversations",
            title: "Offline",
            window: self.window(minutes: nil),
            usageKnown: false)
        let rows = OverviewCompactTableModel.rows(
            provider: .antigravity,
            model: Self.model(provider: .antigravity, name: "Antigravity", metrics: [
                Self.metric(id: "antigravity-offline-conversations", statusText: "Unavailable - x"),
                Self.metric(id: "primary", statusText: "Refreshing"),
            ]),
            snapshot: Self.snapshot(extraRateWindows: [offline], provider: .antigravity),
            now: Self.now)
        #expect(rows.count == 1)
        #expect(rows[0].presentation == .value)
        #expect(rows[0].valueText == "Refreshing")
    }

    @Test
    func `synthetic placeholder primary is dropped`() {
        let phantom = RateWindow(
            usedPercent: 0,
            windowMinutes: 300,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        let rows = OverviewCompactTableModel.rows(
            provider: .claude,
            model: Self.model(provider: .claude, name: "Claude", metrics: [Self.metric(id: "primary")]),
            snapshot: Self.snapshot(primary: phantom, provider: .claude),
            now: Self.now)
        #expect(rows.isEmpty)
    }

    @Test
    func `mistral balance and renewal render as credits value rows`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .mistral,
            model: Self.model(provider: .mistral, name: "Mistral", metrics: [
                Self.metric(id: "mistral-balance", statusText: "$12.50 left"),
                Self.metric(id: "renewal", resetsAt: Self.now.addingTimeInterval(3600)),
            ]),
            snapshot: Self.snapshot(provider: .mistral),
            now: Self.now)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.presentation == .value && $0.period == .credits })
        #expect(rows[0].valueText == "$12.50 left")
        #expect(rows[1].resetsInText == "1h")
    }

    @Test
    func `balance row appends from login method with plan text`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .openrouter,
            model: Self.model(provider: .openrouter, name: "OpenRouter", planText: "$4.96"),
            snapshot: Self.snapshot(loginMethod: "balance: $4.96", provider: .openrouter),
            now: Self.now)
        #expect(rows.count == 1)
        #expect(rows[0].id == "openrouter:balance")
        #expect(rows[0].period == .credits)
        #expect(rows[0].valueText == "$4.96")
        #expect(rows[0].resetsInText == "—")
    }

    @Test
    func `reset countdown shortens to the mock in column`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .codex,
            model: Self.model(metrics: [
                Self.metric(id: "primary", resetsAt: Self.now.addingTimeInterval(4 * 3600)),
                Self.metric(id: "secondary"),
            ]),
            snapshot: Self.snapshot(),
            now: Self.now)
        #expect(rows[0].resetsInText == "4h")
        #expect(rows[1].resetsInText == "—")
    }

    @Test
    func `period sections group rows in canonical order with contiguous providers`() {
        let codex = OverviewCompactTableModel.rows(
            provider: .codex,
            model: Self.model(provider: .codex, name: "Codex", metrics: [
                Self.metric(id: "primary"),
                Self.metric(id: "secondary"),
            ]),
            snapshot: Self.snapshot(provider: .codex),
            now: Self.now)
        let droid = OverviewCompactTableModel.rows(
            provider: .factory,
            model: Self.model(provider: .factory, name: "Droid", metrics: [
                Self.metric(id: "primary"),
                Self.metric(id: "tertiary"),
            ]),
            snapshot: Self.snapshot(provider: .factory),
            now: Self.now)
        let sections = OverviewCompactTableModel.periodSections(rows: codex + droid)

        #expect(sections.map(\.period) == [.session, .weekly, .monthly])
        let session = sections[0]
        #expect(session.title == "Session")
        #expect(session.groups.count == 2)
        #expect(session.groups[0].first?.providerDisplayName == "Codex")
        #expect(session.groups[1].first?.providerDisplayName == "Droid")
        let weekly = sections[1]
        #expect(weekly.groups.count == 1)
        #expect(weekly.groups[0].map(\.period) == [.weekly])
        #expect(weekly.groups[0].first?.provider == .codex)
        let monthly = sections[2]
        #expect(monthly.groups.count == 1)
        #expect(monthly.groups[0].allSatisfy { $0.provider == .factory })
    }

    @Test
    func `multi unit countdowns keep only the largest unit`() {
        let rows = OverviewCompactTableModel.rows(
            provider: .codex,
            model: Self.model(metrics: [
                Self.metric(id: "primary", resetsAt: Self.now.addingTimeInterval(26 * 24 * 3600 + 2 * 3600)),
                Self.metric(id: "secondary", resetsAt: Self.now.addingTimeInterval(2 * 24 * 3600 + 4 * 3600)),
            ]),
            snapshot: Self.snapshot(),
            now: Self.now)
        #expect(rows[0].resetsInText == "26d")
        #expect(rows[1].resetsInText == "2d")
    }

    /// The By-provider period cell renders the full localized period label plus an optional
    /// qualifier symbol inside the leading track. If a label or the PERIOD header is ever
    /// wider than the track, the cell truncates silently — fail the build instead.
    @Test
    func `full period labels and period header fit the leading track width`() {
        let metadataFont = NSFont.systemFont(ofSize: CompactTableMetrics.metadataFontSize)
        // Symbol allowance: 4pt gap + a 10pt icon on qualifier-bearing rows.
        let symbolAllowance = CompactTableMetrics.columnSpacing + CGFloat(11)
        for period in [TablePeriod.session, .weekly, .monthly, .credits, .other] {
            let label = OverviewCompactTableModel.byProviderPeriodLabel(period)
            let width = NSAttributedString(string: label, attributes: [.font: metadataFont])
                .size().width
            let limit = CompactTableMetrics.periodColumnWidth - symbolAllowance
            #expect(
                width <= limit,
                "full label \"\(label)\" at \(width)pt does not fit \(Int(limit))pt track")
        }
        // The header explains the leading track; the By-provider header renders at
        // caption2 (11pt) with a 0.75 minimum scale factor as the last-resort shrink.
        let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let headerWidth = NSAttributedString(
            string: L("compact_header_period"),
            attributes: [.font: headerFont]).size().width
        #expect(
            headerWidth <= CompactTableMetrics.periodColumnWidth,
            "PERIOD header at \(headerWidth)pt does not fit \(Int(CompactTableMetrics.periodColumnWidth))pt")
    }

    /// Operator column budget for the By-provider view: 84pt PERIOD and USED+IN tracks around
    /// a 176pt bar, computed from the declared remaining menu width (padding and gaps included).
    @Test
    func `bar track meets the 84 176 84 column budget`() {
        // Mirrors StatusItemController.compactOverviewMenuWidth (main-actor isolated,
        // so the value is restated here); keep in sync when the menu width changes.
        let menuWidth: CGFloat = 380
        let leadingTrack = CompactTableMetrics.periodColumnWidth
        let trailingGroup = CompactTableMetrics.usedColumnWidth + CompactTableMetrics.inColumnWidth
        let gaps = 3
        let bar = CompactTableMetrics.measureWidth(
            totalWidth: menuWidth,
            fixedColumns: leadingTrack + trailingGroup,
            gaps: gaps)
        #expect(bar == 176, "bar track \(bar) is not the 176pt budget")
        #expect(
            abs(trailingGroup - leadingTrack) <= 2,
            "USED+IN anchors (\(trailingGroup)) drift from the period track (\(leadingTrack))")
        // The bar is the declared remainder: padding and gaps must be charged to it, not
        // forgotten, or the row overflows the menu.
        let accounted = bar + leadingTrack + trailingGroup
            + CGFloat(gaps) * CompactTableMetrics.columnSpacing
            + 2 * CompactTableMetrics.horizontalPadding
        #expect(
            accounted == menuWidth,
            "width accounting closes on \(accounted), not the \(menuWidth)pt menu")
    }

    /// The model qualifier rides after the period label as an SF Symbol; the named
    /// qualifier drives the mapping and unassigned ones render none.
    @Test
    func `model qualifiers map to their assigned symbols`() {
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Fable") == "f.circle")
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Gemini") == "sparkle")
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Claude/GPT") == "asterisk.circle")
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Claude") == "asterisk.circle")
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Core") == "c.circle")
        #expect(OverviewCompactTableModel.modelQualifierSymbol("All") == nil)
        #expect(OverviewCompactTableModel.modelQualifierSymbol("") == nil)
        #expect(OverviewCompactTableModel.modelQualifierSymbol("Sonnet") == nil)
    }
}
