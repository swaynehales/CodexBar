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
    func `static table headers fit exact popover width without callbacks`() {
        let (controller, _, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-adapters")
        defer { controller.prepareForAppShutdown() }

        let layout = controller.overviewCompactLayout(for: menu)

        // Production By-provider header view wiring (no control callbacks)
        let tableHeader = controller.makeOverviewCompactTableHeaderView(menu: menu, width: layout.width, layout: layout)
        let tableHost = NSHostingView(rootView: tableHeader)
        tableHost.layoutSubtreeIfNeeded()
        #expect(tableHost.fittingSize.width == layout.width)

        // Production By-period table view wiring (no control callbacks)
        let periodTable = controller.makeOverviewPeriodTableView(
            menu: menu,
            rows: [],
            width: layout.width,
            layout: layout)
        let periodHost = NSHostingView(rootView: periodTable)
        periodHost.layoutSubtreeIfNeeded()
        #expect(periodHost.fittingSize.width == layout.width)
    }

    @Test
    func `production header and controls fitting sizes match column budgets and popover width`() {
        let (controller, _, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-budgets")
        defer { controller.prepareForAppShutdown() }

        // Content-based budgets: measured 100% plus padding, concise reset tiers plus
        // padding, shared 84pt leading in both groupings. No header-derived floors.
        let layout = controller.overviewCompactLayout(for: menu)
        let fullScale = NSAttributedString(
            string: "100%",
            attributes: [.font: NSFont.monospacedDigitSystemFont(
                ofSize: CompactTableMetrics.emphasisFontSize,
                weight: .semibold)]).size().width
        #expect(layout.percentageWidth == ceil(fullScale) + 8)
        #expect(layout.resetWidth < 98)
        #expect(layout.width == 290 + layout.percentageWidth + layout.resetWidth)
        #expect(layout.width < 472)
        #expect(CompactTableMetrics.providerMaxWidth == CompactTableMetrics.periodColumnWidth)
        #expect(layout.barWidth(leading: CompactTableMetrics.periodColumnWidth) ==
            layout.barWidth(leading: CompactTableMetrics.providerMaxWidth))

        // Full production table header fits exact popover width
        let headerView = controller.makeOverviewCompactTableHeaderView(menu: menu, width: layout.width, layout: layout)
        let headerHost = NSHostingView(rootView: headerView)
        headerHost.layoutSubtreeIfNeeded()
        #expect(headerHost.fittingSize.width == layout.width)

        // Header control row is a plain disabled item independent of data budgets.
        let controlsItem = controller.makeOverviewHeaderControlsItem(menu: menu, width: layout.width)
        #expect(controlsItem.isEnabled == false)
        #expect(Self.headerSegments(in: controlsItem).count == 2)
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
    func `header controls item shows refresh status below control rows`() throws {
        let (controller, _, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-statusrow")
        defer { controller.prepareForAppShutdown() }
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [])
        let status = try #require(controller.compactGlobalRefreshStatus)
        let item = controller.makeOverviewHeaderControlsItem(menu: menu, width: 400)
        let container = try #require(item.view)
        var labels: [String] = []
        func collect(_ view: NSView) {
            for subview in view.subviews {
                if let field = subview as? NSTextField {
                    labels.append(field.stringValue)
                }
                collect(subview)
            }
        }
        collect(container)
        #expect(labels.contains(status.label()))
    }

    private static func headerSegments(in item: NSMenuItem) -> [OverviewDisplayAxis: OverviewDisplaySegmentedControl] {
        var found: [OverviewDisplayAxis: OverviewDisplaySegmentedControl] = [:]
        func walk(_ view: NSView) {
            if let control = view as? OverviewDisplaySegmentedControl {
                found[control.axis] = control
            }
            for subview in view.subviews {
                walk(subview)
            }
        }
        if let view = item.view {
            walk(view)
        }
        return found
    }

    @Test
    func `narrow widths stagger groups and contain every frame`() throws {
        let (controller, _, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-stagger")
        defer { controller.prepareForAppShutdown() }

        let wide = controller.makeOverviewHeaderControlsItem(menu: menu, width: 400)
        let wideContainer = try #require(wide.view)
        let narrow = controller.makeOverviewHeaderControlsItem(menu: menu, width: 100)
        let container = try #require(narrow.view)
        // Forced stagger: stacked rows are taller than the single row.
        #expect(container.frame.height > wideContainer.frame.height)
        // Every placed frame stays inside the container horizontally.
        var frames: [CGRect] = []
        func collect(_ view: NSView) {
            for subview in view.subviews {
                frames.append(subview.frame)
                collect(subview)
            }
        }
        collect(container)
        #expect(!frames.isEmpty)
        for frame in frames {
            #expect(frame.minX >= 0)
            #expect(frame.maxX <= container.frame.width)
        }
    }

    @Test
    func `production segmented controls carry approved copy and flip settings through the action seam`() throws {
        let (controller, settings, menu) = Self
            .makeController(suiteName: "OverviewCompactDisplayControlsTests-segments")
        defer { controller.prepareForAppShutdown() }
        settings.usageBarsFillOption = .remaining
        settings.resetTimesOption = .clock

        let item = controller.makeOverviewHeaderControlsItem(menu: menu, width: 400)
        #expect(item.isEnabled == false)
        #expect(item.identifier == StatusItemController.overviewHeaderControlsItemID)
        let segments = Self.headerSegments(in: item)
        let usage = try #require(segments[.usage])
        let reset = try #require(segments[.resetTime])

        // Short approved labels with full descriptive tooltips and accessible names.
        #expect(OverviewDisplayAxis.usage.segmentTitles == [L("compact_header_used"), L("compact_header_free")])
        #expect(OverviewDisplayAxis.resetTime.segmentTitles == [L("compact_header_wait"), L("compact_header_when")])
        for axis in OverviewDisplayAxis.allCases {
            let control = try #require(segments[axis])
            #expect((0..<control.segmentCount).map { control.label(forSegment: $0) } == axis.segmentTitles)
            #expect((0..<control.segmentCount).map { control.toolTip(forSegment: $0) } == axis.segmentToolTips)
            #expect(control.accessibilityLabel() == axis.label)
            #expect(control.target === controller)
        }
        // Selection reflects current settings (remaining/clock).
        #expect(usage.selectedSegment == 1)
        #expect(reset.selectedSegment == 1)

        // Drive the alternate choice through the real action entry.
        usage.selectedSegment = 0
        controller.overviewDisplayChoiceChanged(usage)
        #expect(settings.usageBarsShowUsed)
        reset.selectedSegment = 0
        controller.overviewDisplayChoiceChanged(reset)
        #expect(!settings.resetTimesShowAbsolute)

        // Re-selecting the current segment is a no-op: no viewport request, same generation.
        let key = ObjectIdentifier(menu)
        controller.overviewDisplayState.viewportRequests.removeValue(forKey: key)
        let generation = controller.menuSession.menuInteractionGeneration(for: key)
        controller.overviewDisplayChoiceChanged(usage)
        #expect(settings.usageBarsShowUsed)
        #expect(controller.overviewDisplayState.viewportRequests[key] == nil)
        #expect(controller.menuSession.menuInteractionGeneration(for: key) == generation)

        // A control tracked to a closed menu refuses the dispatch.
        usage.trackedMenu = NSMenu()
        usage.selectedSegment = 1
        controller.overviewDisplayChoiceChanged(usage)
        #expect(settings.usageBarsShowUsed)
    }
}
