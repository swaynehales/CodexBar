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
