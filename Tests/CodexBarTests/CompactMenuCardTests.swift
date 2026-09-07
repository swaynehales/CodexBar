import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CompactMenuCardTests {
    /// Claude windows well ahead of the sustainable rate, so pace text and stripe both render.
    private static func input(
        now: Date,
        metadata: ProviderMetadata,
        compactCards: Bool,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = .absolute,
        isRefreshing: Bool = false,
        lastError: String? = nil) -> UsageMenuCardView.Model.Input
    {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 60,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 70,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "claude@example.com",
                accountOrganization: nil,
                loginMethod: "Max"))
        return .init(
            provider: .claude,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "claude@example.com", plan: "Max"),
            isRefreshing: isRefreshing,
            lastError: lastError,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: resetTimeDisplayStyle,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            paceVisible: true,
            compactCards: compactCards,
            now: now)
    }

    @Test
    func `default keeps forecast text and the Resets prefix`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(Self.input(now: now, metadata: metadata, compactCards: false))

        #expect(model.compactCards == false)
        let primary = try #require(model.metrics.first { $0.id == "primary" })
        #expect(primary.detailLeftText != nil)
        #expect(try #require(primary.resetText).hasPrefix("Resets "))
    }

    @Test
    func `compact clears text under bars but keeps the pace stripe`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(Self.input(now: now, metadata: metadata, compactCards: true))

        #expect(model.compactCards)
        #expect(!model.metrics.isEmpty)
        for metric in model.metrics {
            #expect(metric.detailText == nil)
            #expect(metric.detailLeftText == nil)
            #expect(metric.detailRightText == nil)
            #expect(metric.sessionEquivalentDetail == nil)
        }
        let primary = try #require(model.metrics.first { $0.id == "primary" })
        #expect(primary.pacePercent != nil)
    }

    @Test
    func `compact drops the Resets prefix and keeps the date`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(Self.input(now: now, metadata: metadata, compactCards: true))

        let primary = try #require(model.metrics.first { $0.id == "primary" })
        let resetText = try #require(primary.resetText)
        #expect(!resetText.hasPrefix("Resets"))
        #expect(resetText == UsageFormatter.resetDescription(
            from: now.addingTimeInterval(4 * 3600),
            now: now))
    }

    @Test
    func `compact countdown reads as a bare relative time`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(Self.input(
            now: now,
            metadata: metadata,
            compactCards: true,
            resetTimeDisplayStyle: .countdown))

        let primary = try #require(model.metrics.first { $0.id == "primary" })
        let resetText = try #require(primary.resetText)
        #expect(resetText.hasPrefix("in "))
        #expect(!resetText.contains("Resets"))
    }

    @Test
    func `compact drops informational usage notes`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 33,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            updatedAt: now,
            dataConfidence: .percentOnly)
        func make(compact: Bool) -> UsageMenuCardView.Model {
            UsageMenuCardView.Model.make(.init(
                provider: .claude,
                metadata: metadata,
                snapshot: snapshot,
                credits: nil,
                creditsError: nil,
                dashboard: nil,
                dashboardError: nil,
                tokenSnapshot: nil,
                tokenError: nil,
                account: AccountInfo(email: nil, plan: nil),
                isRefreshing: false,
                lastError: nil,
                usageBarsShowUsed: true,
                resetTimeDisplayStyle: .absolute,
                tokenCostUsageEnabled: false,
                showOptionalCreditsAndExtraUsage: true,
                hidePersonalInfo: false,
                compactCards: compact,
                now: now))
        }
        #expect(!make(compact: false).usageNotes.isEmpty)
        #expect(make(compact: true).usageNotes.isEmpty)
    }

    /// Both gates clear overlapping detail slots; together they must still leave the
    /// bar, the stripe-free pace state, and the metric set intact.
    @Test
    func `compact combined with hidden pace keeps metrics and drops all detail text`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.kiro])
        let snapshot = try UsageSnapshot(
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(86400),
                resetDescription: nil),
            details: [ProviderDetailSection(rows: [
                ProviderDetailSection.Row(label: "Bonus credits left", value: "500", secondaryValue: "of 1000"),
            ])],
            updatedAt: now)
        func make(compact: Bool, paceVisible: Bool) -> UsageMenuCardView.Model {
            UsageMenuCardView.Model.make(.init(
                provider: .kiro,
                metadata: metadata,
                snapshot: snapshot,
                credits: nil,
                creditsError: nil,
                dashboard: nil,
                dashboardError: nil,
                tokenSnapshot: nil,
                tokenError: nil,
                account: AccountInfo(email: nil, plan: nil),
                isRefreshing: false,
                lastError: nil,
                usageBarsShowUsed: true,
                resetTimeDisplayStyle: .countdown,
                tokenCostUsageEnabled: false,
                showOptionalCreditsAndExtraUsage: true,
                hidePersonalInfo: false,
                paceVisible: paceVisible,
                compactCards: compact,
                now: now))
        }
        let baseline = make(compact: false, paceVisible: true)
        let both = make(compact: true, paceVisible: false)
        #expect(both.metrics.count == baseline.metrics.count)
        #expect(both.metrics.map(\.id) == baseline.metrics.map(\.id))
        for metric in both.metrics {
            #expect(metric.pacePercent == nil)
            #expect(metric.detailText == nil)
            #expect(metric.detailLeftText == nil)
            #expect(metric.detailRightText == nil)
            #expect(metric.sessionEquivalentDetail == nil)
            #expect(metric.resetText != nil)
        }
    }

    @Test
    func `toggling compact invalidates tracked layout compatibility`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let standard = UsageMenuCardView.Model.make(Self.input(now: now, metadata: metadata, compactCards: false))
        let compact = UsageMenuCardView.Model.make(Self.input(now: now, metadata: metadata, compactCards: true))
        #expect(standard.hasCompatibleTrackedLayout(with: standard))
        #expect(!standard.hasCompatibleTrackedLayoutIgnoringMetrics(with: compact))
    }

    @Test
    func `compact keeps the subtitle model so errors can still surface`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(Self.input(
            now: now,
            metadata: metadata,
            compactCards: true,
            lastError: "Token expired"))

        #expect(model.subtitleStyle == .error)
        #expect(model.subtitleText.contains("Token expired"))
    }
}

struct CompactResetLineTests {
    @Test
    func `provider reset descriptions lose the prefix in compact form`() {
        let window = RateWindow(
            usedPercent: 10,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: "Resets in 3 days")
        #expect(UsageFormatter.resetLine(for: window, style: .absolute) == "Resets in 3 days")
        #expect(UsageFormatter.resetLine(for: window, style: .absolute, includesPrefix: false) == "in 3 days")
    }

    @Test
    func `reset now keeps a word in compact form`() {
        let now = Date()
        let window = RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: now, resetDescription: nil)
        let line = UsageFormatter.resetLine(for: window, style: .countdown, includesPrefix: false, now: now)
        #expect(line == "now")
    }
}

@MainActor
struct CompactMenuCardSettingsTests {
    @Test
    func `defaults compact cards to off`() throws {
        let suite = "SettingsStoreTests-compact-menu-cards-defaults"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let store = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(store.compactMenuCards == false)

        store.compactMenuCards = true
        #expect(store.compactMenuCards == true)
        #expect(defaults.object(forKey: "compactMenuCards") as? Bool == true)
    }
}
