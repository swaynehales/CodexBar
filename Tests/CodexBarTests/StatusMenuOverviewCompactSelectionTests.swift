import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `compact overview table shows only the providers selected for overview`() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true
        settings.overviewCompactTableEnabled = true
        let connected: [UsageProvider] = [.claude, .gemini, .antigravity, .grok]
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: connected.contains(provider))
        }

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let enabledRoster = store.enabledFirstPartyProvidersForDisplay()
        #expect(Set(enabledRoster) == Set(connected))
        let now = Date()
        for provider in enabledRoster {
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 25,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: now),
                provider: provider)
        }
        for provider in [UsageProvider.gemini, .grok] {
            settings.setMergedOverviewProviderSelection(
                provider: provider,
                isSelected: false,
                activeProviders: enabledRoster)
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }
        let overviewRows = menu.items
            .compactMap { $0.representedObject as? String }
            .filter { $0.hasPrefix("overviewRow-") }

        #expect(Set(overviewRows) == ["overviewRow-claude", "overviewRow-antigravity"])
    }
}

extension StatusMenuTests {
    private static let sevenConnectedProviders: [UsageProvider] = [
        .openai,
        .claude,
        .gemini,
        .antigravity,
        .openrouter,
        .grok,
        .codex,
    ]

    @Test
    func `compact overview table lifts the six provider cap`() {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true
        settings.overviewCompactTableEnabled = true
        let connected = Self.sevenConnectedProviders
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: connected.contains(provider))
        }

        let store = self.makeCodexStore(settings: settings, dashboardAuthorized: false)
        let enabledRoster = store.enabledFirstPartyProvidersForDisplay()
        #expect(Set(enabledRoster) == Set(connected))
        let now = Date()
        for provider in enabledRoster {
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 25,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil),
                    secondary: nil,
                    updatedAt: now),
                provider: provider)
        }
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: UsageFetcher().loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let scopes = controller.overviewProviderScopes(enabledProviders: enabledRoster)
        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }
        let overviewRows = menu.items
            .compactMap { $0.representedObject as? String }
            .filter { $0.hasPrefix("overviewRow-") }

        #expect(scopes.visible == enabledRoster)
        #expect(Set(overviewRows) == Set(enabledRoster.map { "overviewRow-\($0.rawValue)" }))
    }

    @Test
    func `compact overview selection beyond six survives toggling the compact table`() {
        let settings = self.makeSettings()
        let active = Self.sevenConnectedProviders
        settings.overviewCompactTableEnabled = true
        for provider in active {
            settings.setMergedOverviewProviderSelection(provider: provider, isSelected: true, activeProviders: active)
        }
        #expect(settings.resolvedMergedOverviewProviders(activeProviders: active) == active)

        settings.overviewCompactTableEnabled = false
        #expect(settings.reconcileMergedOverviewSelectedProviders(activeProviders: active) == Array(active.prefix(6)))

        settings.overviewCompactTableEnabled = true
        #expect(settings.reconcileMergedOverviewSelectedProviders(activeProviders: active) == active)
    }
}

extension StatusMenuTests {
    @Test
    func `compact overview selection holds when the enabled providers change`() {
        let settings = self.makeSettings()
        settings.overviewCompactTableEnabled = true
        let active: [UsageProvider] = [.claude, .gemini, .antigravity]
        for provider in active {
            settings.setMergedOverviewProviderSelection(provider: provider, isSelected: true, activeProviders: active)
        }
        settings.setMergedOverviewProviderSelection(provider: .gemini, isSelected: false, activeProviders: active)

        let grown = active + [.grok]
        #expect(settings.reconcileMergedOverviewSelectedProviders(activeProviders: grown) == [.claude, .antigravity])
        #expect(settings.resolvedMergedOverviewProviders(activeProviders: grown) == [.claude, .antigravity])
    }
}
