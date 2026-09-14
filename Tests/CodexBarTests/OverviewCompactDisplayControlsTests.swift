import AppKit
import CodexBarCore
import Foundation
import SwiftUI
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

                let headerItem = controller.makeOverviewCompactHeaderItem(menu: menu, width: 468)
                #expect(headerItem.identifier == StatusItemController.overviewCompactHeaderItemID)
                #expect(headerItem.representedObject as? String == "overviewCompactHeader")
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
    func `settings adapters reflect on dropdown headers and trigger callback seam`() {
        let (controller, settings, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-adapters")
        defer { controller.prepareForAppShutdown() }

        settings.usageBarsFillOption = .remaining
        settings.resetTimesOption = .clock

        let layout = controller.overviewCompactLayout(for: menu)

        // Production By-provider header view wiring
        let tableHeader = controller.makeOverviewCompactTableHeaderView(menu: menu, width: layout.width, layout: layout)
        tableHeader.onUsageChange?(0)
        #expect(settings.usageBarsShowUsed)
        tableHeader.onUsageChange?(1)
        #expect(!settings.usageBarsShowUsed)
        tableHeader.onResetChange?(1)
        #expect(settings.resetTimesShowAbsolute)
        tableHeader.onResetChange?(0)
        #expect(!settings.resetTimesShowAbsolute)

        // Production By-period table view wiring
        let periodTable = controller.makeOverviewPeriodTableView(
            menu: menu,
            rows: [],
            width: layout.width,
            layout: layout)
        periodTable.onUsageChange?(0)
        #expect(settings.usageBarsShowUsed)
        periodTable.onResetChange?(1)
        #expect(settings.resetTimesShowAbsolute)
    }

    @Test
    func `production header and controls fitting sizes match column budgets and popover width`() {
        let (controller, _, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-budgets")
        defer { controller.prepareForAppShutdown() }

        let usageWidth = StatusItemController.dropdownHeaderWidth(for: .usage)
        let resetWidth = StatusItemController.dropdownHeaderWidth(for: .resetTime)

        #expect(usageWidth >= 78)
        #expect(resetWidth >= 90)

        let layout = controller.overviewCompactLayout(for: menu)
        #expect(layout.percentageWidth >= usageWidth)
        #expect(layout.resetWidth >= resetWidth)
        #expect(layout.width == 472)
        #expect(layout.barWidth(leading: 84) == 176)
        #expect(layout.barWidth(leading: 112) == 148)

        // Full production table header fits exact popover width
        let headerView = controller.makeOverviewCompactTableHeaderView(menu: menu, width: layout.width, layout: layout)
        let headerHost = NSHostingView(rootView: headerView)
        headerHost.layoutSubtreeIfNeeded()
        #expect(headerHost.fittingSize.width == layout.width)

        // Dropdown headers with resolved column widths fit within column bounds
        let usageDropdown = OverviewCompactDropdownHeader(
            axis: .usage,
            selectedIndex: 1,
            width: layout.percentageWidth,
            isHighlighted: false)
        let usageHost = NSHostingView(rootView: usageDropdown)
        usageHost.layoutSubtreeIfNeeded()
        #expect(usageHost.fittingSize.width <= layout.percentageWidth)

        let resetDropdown = OverviewCompactDropdownHeader(
            axis: .resetTime,
            selectedIndex: 0,
            width: layout.resetWidth,
            isHighlighted: false)
        let resetHost = NSHostingView(rootView: resetDropdown)
        resetHost.layoutSubtreeIfNeeded()
        #expect(resetHost.fittingSize.width <= layout.resetWidth)
    }

    @Test
    func `candidate reset sample dates cover all weekdays and wide times with various anchors`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        let midnight = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 0,
            minute: 0,
            second: 0)))
        let nonMidnight = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 14,
            hour: 15,
            minute: 30,
            second: 0)))

        for anchor in [midnight, nonMidnight] {
            let candidates = StatusItemController.candidateResetSampleDates(now: anchor, calendar: calendar)
            #expect(!candidates.isEmpty)

            // All candidates strictly within the 1d to 7d window
            for date in candidates {
                let delta = date.timeIntervalSince(anchor)
                #expect(delta >= 86400 && delta <= 604_800)
            }

            // Must cover all 7 calendar weekdays
            let weekdays = Set(candidates.map { calendar.component(.weekday, from: $0) })
            #expect(weekdays.count == 7)

            // Hours must include local 12:59 and 23:59
            let hours = Set(candidates.map { calendar.component(.hour, from: $0) })
            #expect(hours.contains(12))
            #expect(hours.contains(23))

            // Must include exact +7d boundary
            #expect(candidates.contains(anchor.addingTimeInterval(604_800)))
        }
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

    @Test
    func `usage popup factory builds titled pullsDown control with checked selection`() {
        for showUsed in [true, false] {
            let button = StatusItemController.makeUsagePopUpButton(showUsed: showUsed)
            #expect(button.pullsDown)
            #expect(!button.isBordered)
            #expect(button.numberOfItems == 3)
            #expect(button.itemTitle(at: 0) == (showUsed ? OverviewDisplayAxis.usage.choices[0] : "Left"))
            #expect(button.itemTitle(at: 1) == OverviewDisplayAxis.usage.choices[0])
            #expect(button.itemTitle(at: 2) == OverviewDisplayAxis.usage.choices[1])
            #expect(button.indexOfSelectedItem == (showUsed ? 1 : 2))
            #expect(button.target == nil)
            #expect(button.accessibilityLabel() == OverviewDisplayAxis.usage.label)
        }
    }

    @Test
    func `usage popup coordinator maps title slot to current segment`() {
        let button = StatusItemController.makeUsagePopUpButton(showUsed: true)
        let coordinator = OverviewUsagePopUpCoordinator()
        coordinator.selectedSegment = 0
        var received: [Int] = []
        coordinator.onSelect = { received.append($0) }
        button.selectItem(at: 0)
        coordinator.chose(button)
        button.selectItem(at: 1)
        coordinator.chose(button)
        button.selectItem(at: 2)
        coordinator.chose(button)
        #expect(received == [0, 0, 1])
        coordinator.selectedSegment = 1
        button.selectItem(at: 0)
        coordinator.chose(button)
        #expect(received == [0, 0, 1, 1])
    }

    @Test
    func `usage popup dispatch through production header closure flips the setting`() throws {
        let (controller, settings, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-popupwire")
        defer { controller.prepareForAppShutdown() }
        settings.usageBarsFillOption = .used
        let header = controller.makeOverviewCompactTableHeaderView(menu: menu, width: 400, layout: nil)
        let onSelect = try #require(header.onUsageChange)

        // Bind exactly as the SwiftUI host does, then dispatch through the real
        // AppKit action machinery instead of calling the closure directly.
        let button = StatusItemController.makeUsagePopUpButton(showUsed: true)
        let coordinator = OverviewUsagePopUpCoordinator()
        coordinator.selectedSegment = 0
        coordinator.onSelect = onSelect
        button.target = coordinator
        button.action = #selector(OverviewUsagePopUpCoordinator.chose(_:))
        let action = try #require(button.action)
        let target = try #require(button.target)

        button.selectItem(at: 2)
        NSApp.sendAction(action, to: target, from: button)
        #expect(!settings.usageBarsShowUsed)

        // Title slot re-affirms the now-current segment: no-op through the guard.
        coordinator.selectedSegment = 1
        button.selectItem(at: 0)
        NSApp.sendAction(action, to: target, from: button)
        #expect(!settings.usageBarsShowUsed)

        // Closed menu: the production closure refuses the stale dispatch.
        controller.openMenus.removeAll()
        button.selectItem(at: 1)
        NSApp.sendAction(action, to: target, from: button)
        #expect(!settings.usageBarsShowUsed)
    }
}
