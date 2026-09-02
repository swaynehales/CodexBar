import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OverviewGridLayoutSettingsTests {
    @Test
    func `overview grid layout defaults to list and persists across instances`() throws {
        let suite = "OverviewGridLayoutSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(settings.overviewGridLayout == .list)

        settings.overviewGridLayout = .grid
        #expect(settings.overviewGridLayout == .grid)

        let reloaded = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.overviewGridLayout == .grid)
    }

    @Test
    func `overview grid layout raw value survives unknown values`() throws {
        let suite = "OverviewGridLayoutSettingsTests-unknown-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("bogus", forKey: "overviewGridLayout")

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(settings.overviewGridLayout == .list)
    }

    @Test
    func `overview grid layout labels are localized`() {
        #expect(!OverviewGridLayout.list.label.isEmpty)
        #expect(!OverviewGridLayout.grid.label.isEmpty)
        #expect(OverviewGridLayout.list.label != OverviewGridLayout.grid.label)
    }
}
