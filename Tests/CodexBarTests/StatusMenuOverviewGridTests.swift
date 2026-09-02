import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuOverviewGridTests {
    private func makeSettings(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func enableOnly(_ providers: Set<UsageProvider>, settings: SettingsStore) {
        for provider in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: providers.contains(provider))
        }
    }

    private func makeController(settings: SettingsStore) -> StatusItemController {
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        return StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
    }

    private func openOverviewMenu(
        suite: String,
        layout: OverviewGridLayout,
        enabled: Set<UsageProvider>) throws -> (StatusItemController, NSMenu)
    {
        let settings = self.makeSettings(suite: suite)
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = layout
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = try #require(controller.makeMenu() as? StatusItemMenu)
        controller.menuWillOpen(menu)
        return (controller, menu)
    }

    @Test
    func `grid layout batches six providers into two rows`() throws {
        let (controller, menu) = try self.openOverviewMenu(
            suite: "StatusMenuOverviewGridTests-grid6-\(UUID().uuidString)",
            layout: .grid,
            enabled: [.codex, .claude, .cursor, .opencode, .warp, .gemini])
        defer { controller.menuDidClose(menu) }

        let gridRows = menu.items
            .filter { ($0.representedObject as? String) == StatusItemController.overviewGridRowIdentifier }
        #expect(gridRows.count == 2)

        let listRows = menu.items.compactMap { item -> String? in
            let id = item.representedObject as? String ?? ""
            return id.hasPrefix("overviewRow-") ? id : nil
        }
        #expect(listRows.isEmpty)

        var clickTargets = 0
        for item in gridRows {
            let hosting = try #require(item.view)
            let finder = OverviewGridCardClickFinder()
            hosting.enumerateDescendants(finder.visit)
            clickTargets += finder.count
        }
        #expect(clickTargets == 6)
    }

    @Test
    func `list layout keeps single column behavior`() throws {
        let (controller, menu) = try self.openOverviewMenu(
            suite: "StatusMenuOverviewGridTests-list-\(UUID().uuidString)",
            layout: .list,
            enabled: [.codex, .claude, .cursor])
        defer { controller.menuDidClose(menu) }

        let listRows = menu.items.compactMap { item -> String? in
            let id = item.representedObject as? String ?? ""
            return id.hasPrefix("overviewRow-") ? id : nil
        }
        #expect(listRows.count == 3)
        #expect(menu.items
            .filter { ($0.representedObject as? String) == StatusItemController.overviewGridRowIdentifier }.isEmpty)
    }

    @Test
    func `refreshMenuCardHeights keeps grid rows at rendered width`() throws {
        let (controller, menu) = try self.openOverviewMenu(
            suite: "StatusMenuOverviewGridTests-rewidth-\(UUID().uuidString)",
            layout: .grid,
            enabled: [.codex, .claude, .cursor, .opencode, .warp, .gemini])
        defer { controller.menuDidClose(menu) }

        let gridRows = menu.items
            .filter { ($0.representedObject as? String) == StatusItemController.overviewGridRowIdentifier }
        #expect(gridRows.count == 2)

        controller.refreshMenuCardHeights(in: menu)
        let renderedWidth = controller.renderedMenuWidth(for: menu)
        for item in gridRows {
            let view = try #require(item.view)
            #expect(abs(view.frame.width - renderedWidth) <= 0.5)
            #expect(view.frame.height > 0)
        }
    }

    @Test
    func `grid layout widens menu width`() {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-width-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .grid
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true
        self.enableOnly([.codex, .claude, .cursor], settings: settings)

        let controller = self.makeController(settings: settings)
        let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: false)
        let width = controller.menuCardWidth(
            for: [.claude, .codex, .cursor],
            selectedProvider: .claude,
            descriptor: descriptor)
        #expect(width >= StatusItemController.menuCardBaseWidth * CGFloat(StatusItemController.overviewGridColumns))
    }

    @Test
    func `list layout keeps base width`() {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-width-list-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .list
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true
        self.enableOnly([.codex, .claude, .cursor], settings: settings)

        let controller = self.makeController(settings: settings)
        let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: false)
        let width = controller.menuCardWidth(
            for: [.claude, .codex, .cursor],
            selectedProvider: .claude,
            descriptor: descriptor)
        #expect(width == StatusItemController.menuCardBaseWidth)
    }
}

/// Walks a view tree and counts MenuRowContainerView instances whose payload carries an onClick.
@MainActor
final class OverviewGridCardClickFinder {
    private(set) var count = 0

    func visit(_ view: NSView) {
        guard let container = view as? MenuRowContainerView else { return }
        if container._test_onClick != nil {
            self.count += 1
        }
    }
}

extension NSView {
    func enumerateDescendants(_ visit: (NSView) -> Void) {
        visit(self)
        for sub in subviews {
            sub.enumerateDescendants(visit)
        }
    }
}
