import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct OverviewCompactDisplayControlsTests {
    @Test
    func `display choices persist without refreshing and ignore closed menus`() {
        let settings = testSettingsStore(suiteName: "OverviewCompactDisplayControlsTests")
        settings.refreshFrequency = .manual
        settings.usageBarsShowUsed = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let controller = StatusItemController(
            store: store, settings: settings, account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(), preferencesSelection: PreferencesSelection(), statusBar: .system)
        defer { controller.prepareForAppShutdown() }
        let menu = NSMenu()
        controller.openMenus[ObjectIdentifier(menu)] = menu
        controller.overviewTableGrouping = .period
        let refresh = controller.compactGlobalRefreshStatus
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 0, menu: menu)
        #expect(settings.usageBarsShowUsed)
        #expect(settings.userDefaults.bool(forKey: "usageBarsShowUsed"))
        #expect(controller.overviewTableGrouping == .period)
        #expect(controller.compactGlobalRefreshStatus == refresh)
        #expect(controller.manualRefreshTasks.isEmpty)
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 1, menu: menu)
        #expect(!settings.usageBarsShowUsed)
        controller.openMenus.removeAll()
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 0, menu: menu)
        #expect(!settings.usageBarsShowUsed)
    }
}
