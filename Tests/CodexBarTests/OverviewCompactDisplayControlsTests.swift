import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct OverviewCompactDisplayControlsTests {
    private static func makeController(suiteName: String) -> (StatusItemController, SettingsStore, NSMenu) {
        let settings = testSettingsStore(suiteName: suiteName)
        settings.refreshFrequency = .manual
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex").path,
            "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path,
        ]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        let menu = NSMenu()
        let key = ObjectIdentifier(menu)
        controller.openMenus[key] = menu
        controller.menuSession.beginTrackingSession(key)
        return (controller, settings, menu)
    }

    @Test
    func `display choices matrix exercises all four settings across both groupings`() {
        let (controller, settings, menu) = Self.makeController(suiteName: "OverviewCompactDisplayControlsTests-matrix")
        defer { controller.prepareForAppShutdown() }

        let groupings: [OverviewTableGrouping] = [.provider, .period]
        let configurations: [(usageSegment: Int, showUsed: Bool, resetSegment: Int, showAbsolute: Bool)] = [
            (0, true, 0, false), // Used, Countdown
            (0, true, 1, true), // Used, Clock
            (1, false, 0, false), // Remaining, Countdown
            (1, false, 1, true), // Remaining, Clock
        ]

        for grouping in groupings {
            controller.overviewTableGrouping = grouping
            let initialRefresh = controller.compactGlobalRefreshStatus

            for config in configurations {
                controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: config.usageSegment, menu: menu)
                controller.applyOverviewDisplayChoice(
                    axis: .resetTime,
                    selectedSegment: config.resetSegment,
                    menu: menu)

                #expect(settings.usageBarsShowUsed == config.showUsed)
                #expect(settings.usageBarsFillOption == (config.showUsed ? .used : .remaining))
                #expect(settings.resetTimesShowAbsolute == config.showAbsolute)
                #expect(settings.resetTimesOption == (config.showAbsolute ? .clock : .countdown))

                #expect(controller.overviewTableGrouping == grouping)
                #expect(controller.compactGlobalRefreshStatus == initialRefresh)
                #expect(controller.manualRefreshTasks.isEmpty)

                let usageControl = controller.makeOverviewDisplayPopUpButton(axis: .usage, menu: menu)
                #expect(usageControl.indexOfSelectedItem == config.usageSegment)

                let resetControl = controller.makeOverviewDisplayPopUpButton(axis: .resetTime, menu: menu)
                #expect(resetControl.indexOfSelectedItem == config.resetSegment)
            }
        }
    }

    @Test
    func `same choice is no-op and does not record new viewport request`() {
        let (controller, settings, menu) = Self.makeController(suiteName: "OverviewCompactDisplayControlsTests-noop")
        defer { controller.prepareForAppShutdown() }

        settings.usageBarsShowUsed = true
        let key = ObjectIdentifier(menu)
        controller.overviewDisplayState.viewportRequests.removeValue(forKey: key)

        let generation = controller.menuSession.menuInteractionGeneration(for: key)
        // Applying segment 0 (used) when already used is a no-op
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 0, menu: menu)
        #expect(settings.usageBarsShowUsed)
        #expect(controller.overviewDisplayState.viewportRequests[key] == nil)
        #expect(controller.menuSession.menuInteractionGeneration(for: key) == generation)
    }

    @Test
    func `invalid segments and closed menus are ignored`() {
        let (controller, settings, menu) = Self.makeController(suiteName: "OverviewCompactDisplayControlsTests-guards")
        defer { controller.prepareForAppShutdown() }

        settings.usageBarsShowUsed = false
        settings.resetTimesShowAbsolute = false

        // Invalid segments
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 99, menu: menu)
        #expect(!settings.usageBarsShowUsed)
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: -1, menu: menu)
        #expect(!settings.usageBarsShowUsed)
        controller.applyOverviewDisplayChoice(axis: .resetTime, selectedSegment: 2, menu: menu)
        #expect(!settings.resetTimesShowAbsolute)

        // Closed menu
        controller.openMenus.removeAll()
        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 0, menu: menu)
        #expect(!settings.usageBarsShowUsed)
        controller.applyOverviewDisplayChoice(axis: .resetTime, selectedSegment: 1, menu: menu)
        #expect(!settings.resetTimesShowAbsolute)
    }

    @Test
    func `settings adapters reflect on native controls`() {
        let (controller, settings, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-adapters")
        defer { controller.prepareForAppShutdown() }

        settings.usageBarsFillOption = .remaining
        settings.resetTimesOption = .clock

        let usageControl1 = controller.makeOverviewDisplayPopUpButton(axis: .usage, menu: menu)
        #expect(usageControl1.indexOfSelectedItem == 1)

        let resetControl1 = controller.makeOverviewDisplayPopUpButton(axis: .resetTime, menu: menu)
        #expect(resetControl1.indexOfSelectedItem == 1)

        settings.usageBarsFillOption = .used
        settings.resetTimesOption = .countdown

        let usageControl2 = controller.makeOverviewDisplayPopUpButton(axis: .usage, menu: menu)
        #expect(usageControl2.indexOfSelectedItem == 0)

        let resetControl2 = controller.makeOverviewDisplayPopUpButton(axis: .resetTime, menu: menu)
        #expect(resetControl2.indexOfSelectedItem == 0)
    }

    @Test
    func `choices persist to independent settings store with same suite`() {
        let suite = "OverviewCompactDisplayControlsTests-persist-\(UUID().uuidString)"
        let (controller, settings, menu) = Self.makeController(suiteName: suite)
        defer { controller.prepareForAppShutdown() }

        controller.applyOverviewDisplayChoice(axis: .usage, selectedSegment: 1, menu: menu)
        controller.applyOverviewDisplayChoice(axis: .resetTime, selectedSegment: 1, menu: menu)

        #expect(!settings.usageBarsShowUsed)
        #expect(settings.resetTimesShowAbsolute)

        let settings2 = SettingsStore(
            userDefaults: settings.userDefaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        #expect(!settings2.usageBarsShowUsed)
        #expect(settings2.usageBarsFillOption == .remaining)
        #expect(settings2.resetTimesShowAbsolute)
        #expect(settings2.resetTimesOption == .clock)
    }

    @Test
    func `viewport request distance and offset calculations handle flipped and unflipped geometries`() {
        // Flipped geometry (e.g. document starts at 0 at the top)
        let distFlipped = OverviewDisplayViewportRequest.distance(
            offset: 100,
            documentHeight: 500,
            clipHeight: 200,
            flipped: true)
        #expect(distFlipped == 100)

        let reqFlipped = OverviewDisplayViewportRequest(generation: 1, distanceFromTop: 100)
        let offsetFlipped = reqFlipped.offset(documentHeight: 500, clipHeight: 200, flipped: true)
        #expect(offsetFlipped == 100)

        // Clamping flipped
        let clampedFlipped = reqFlipped.offset(documentHeight: 250, clipHeight: 200, flipped: true)
        #expect(clampedFlipped == 50) // max(0, 250 - 200)

        // Unflipped geometry (document starts at bottom; top of document is documentHeight - clipHeight = 300)
        let distUnflippedTop = OverviewDisplayViewportRequest.distance(
            offset: 300,
            documentHeight: 500,
            clipHeight: 200,
            flipped: false)
        #expect(distUnflippedTop == 0) // At the top

        let distUnflippedScrolled = OverviewDisplayViewportRequest.distance(
            offset: 200,
            documentHeight: 500,
            clipHeight: 200,
            flipped: false)
        #expect(distUnflippedScrolled == 100) // 100pt down from top

        let reqUnflipped = OverviewDisplayViewportRequest(generation: 1, distanceFromTop: 100)
        let offsetUnflipped = reqUnflipped.offset(documentHeight: 500, clipHeight: 200, flipped: false)
        #expect(offsetUnflipped == 200) // 300 - 100 = 200

        // Clamping unflipped
        let clampedUnflipped = reqUnflipped.offset(documentHeight: 250, clipHeight: 200, flipped: false)
        #expect(clampedUnflipped == 0) // max is 50, distance clamped to 50, offset = 50 - 50 = 0
    }

    @Test
    func `viewport restore preserves offset and cancels on newer interaction or close`() throws {
        let (controller, _, menu) = Self.makeController(suiteName: "OverviewCompactDisplayControlsTests-cancel")
        defer { controller.prepareForAppShutdown() }
        let key = ObjectIdentifier(menu)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 500))
        let item = NSMenuItem()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        item.view = view
        menu.addItem(item)
        scroll.documentView = document
        document.addSubview(view)
        let generation = try #require(controller.menuSession.menuInteractionGeneration(for: key))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        controller.overviewDisplayState.viewportRequests[key] = OverviewDisplayViewportRequest(
            generation: generation, distanceFromTop: 100)
        controller.restoreOverviewDisplayViewportAfterLayout(in: menu)
        Self.drainTrackingCallbacks()
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(controller.overviewDisplayState.viewportRequests[key] == nil)

        controller.overviewDisplayState.viewportRequests[key] = OverviewDisplayViewportRequest(
            generation: generation, distanceFromTop: 0)
        controller.restoreOverviewDisplayViewportAfterLayout(in: menu)
        controller.menuSession.advanceMenuInteraction(for: key)
        Self.drainTrackingCallbacks()
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(controller.overviewDisplayState.viewportRequests[key] == nil)

        let nextGeneration = try #require(controller.menuSession.menuInteractionGeneration(for: key))
        controller.overviewDisplayState.viewportRequests[key] = OverviewDisplayViewportRequest(
            generation: nextGeneration, distanceFromTop: 0)
        controller.restoreOverviewDisplayViewportAfterLayout(in: menu)
        controller.forgetClosedMenu(menu)
        controller.openMenus[key] = menu
        controller.menuSession.beginTrackingSession(key)
        Self.drainTrackingCallbacks()
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(controller.overviewDisplayState.viewportRequests[key] == nil)
    }

    @Test
    func `preopen and retained reopened layouts preserve the rendered budget`() {
        let (controller, _, menu) = Self.makeController(suiteName: "OverviewCompactDisplayControlsTests-layout")
        defer { controller.prepareForAppShutdown() }
        let key = ObjectIdentifier(menu)
        controller.openMenus.removeValue(forKey: key)
        let first = controller.overviewCompactLayout(for: menu)
        #expect(controller.overviewDisplayState.layouts[key] == first)
        let header = controller.makeOverviewGroupingToggleItem(menu: menu, width: first.width)
        menu.addItem(header)
        controller.forgetClosedMenu(menu)
        #expect(controller.overviewDisplayState.layouts[key] == nil)
        controller.beginMenuTrackingSession(for: menu)
        #expect(controller.overviewDisplayState.layouts[key] == first)
        controller.openMenus[key] = menu
        for axis in OverviewDisplayAxis.allCases {
            for segment in [0, 1, 0] {
                controller.applyOverviewDisplayChoice(axis: axis, selectedSegment: segment, menu: menu)
                #expect(controller.overviewCompactLayout(for: menu) == first)
            }
        }
    }

    private static func drainTrackingCallbacks() {
        for _ in 0..<3 {
            CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.01, true)
        }
    }
}
