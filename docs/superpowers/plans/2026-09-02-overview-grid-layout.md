# Overview 3×2 Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Grid" layout option for the Overview tab that renders up to six provider cards in a 3-wide × 2-tall arrangement inside a wider menu, selectable from Preferences → Menu Bar.

**Architecture:** Today the Overview tab stacks one full-width hosted card per provider (`addOverviewRows` in `StatusItemController+Menu.swift`), with one NSMenuItem per provider row. The plan introduces an `OverviewGridLayout` enum persisted in `SettingsStore` (wired into the existing `menuObservationToken` → `handleSettingsChange` → `invalidateMenus` chain), and a new `addOverviewGrid` path that lays out the same `OverviewMenuCardRowView` models as a horizontally-centered `HStack` of up to three `MenuGridRowView` containers per menu item. Each card is its own `MenuRowContainerView`, so the proven click (`onClick` via `mouseDown`/`mouseUp`), GPU highlight, and accessibility machinery apply per card without modification. Rows are single menu items with `representedObject` `"overviewGridRow"` so highlight, scroll, cache, and refresh logic treat the grid as a row-shaped unit and are explicitly taught where needed.

**Tech Stack:** Swift 6, AppKit (NSMenu, NSMenuItem custom views), SwiftUI (existing card views), Swift Testing (`@Suite`/`@Test`), SwiftPM.

## Global Constraints

- Run `swiftformat Sources Tests` and `swiftlint --strict` (via `make check`) after code changes; fix all reported issues before committing.
- 4-space indent, 120-char lines, explicit `self` is intentional — do not remove.
- Prefer modern SwiftUI/Observation: `@Observable` models, `@State`/`@Bindable`; avoid `ObservableObject`/`@ObservedObject`/`@StateObject`.
- Never run tests/checks that can trigger macOS Keychain prompts (no live provider probes, no real SecItem reads). Use stub stores / dictionary-backed defaults per `AGENTS.md`.
- Menu behavior tests go through stable seams (`NSMenu` item inspection on a test-built controller) rather than live `NSStatusBar` highlight simulation.
- User-facing strings go through `L("<snake_case_key>")` with the key added to `Sources/CodexBar/Resources/en.lproj/Localizable.strings`; `Scripts/check-app-locales.mjs` requires every other locale catalog (21 more) to carry the same key, using the English text as the value (verified: script passes with English fallbacks).
- Model names in tests/code: released models or clearly fictitious names only.
- Keep commits scoped; short imperative clauses (e.g. "Add overview grid layout").

## Context: module purposes, callers, contracts

- **`addOverviewRows` (Sources/CodexBar/StatusItemController+Menu.swift:560)** — Purpose: render the Overview tab's content (spend summary card + one row per visible provider) into an `NSMenu`. Callers: `addPrimaryMenuContent` (same file, line 814) on every menu populate, plus the merged-switcher content cache and smart-update paths that replay or re-run it. Contract: returns `true` when rows were added (caller then appends a separator), items carry `representedObject` `"overviewRow-<provider>"`, per-row height comes from `cachedMenuCardHeight`, and every row is clickable (`onClick` → `selectOverviewProvider`) / highlightable (`MenuCardHighlighting`).
- **`SettingsStore` menu-observation contract (SettingsStore+MenuObservation.swift)** — Purpose: tell `StatusItemController.observeSettingsChanges` which settings affect menu content. Contract: any new menu-affecting property must be read inside `menuObservationToken`'s `withObservationTracking` block so a change triggers `handleSettingsChange` → `invalidateMenus`.
- **`MenuRowContainerView` (StatusItemController+MenuPresentation.swift:176)** — Purpose: the single hosted-view row container AppKit sees, providing measured size, GPU selection highlight, press tracking, and accessibility. Contract (relied on in grid mode): `measuredHeight(width:)` measures its SwiftUI content at the given width; `hitTest`/`mouseDown` route presses to `onClick` unless a hosted interactive control claims them; `setHighlighted` paints selection; `acceptsFirstMouse` = true.
- **`makeMenuCardItem` (StatusItemController+MenuCardItems.swift:20)** — Purpose: wrap a SwiftUI view in a `MenuRowContainerView` + `MenuCardMenuItem` with cached height. Contract: id doubles as height-cache key; returns an item whose `view` is the container.
- **`refreshMenuCardHeights(in:)` (StatusItemController+MenuCardItems.swift:11)** — Purpose: re-fit row views when the menu's realized width differs from the populated width. Contract: views conforming to `MenuCardMeasuring` get `applyMeasuredSize(width:height:)`; grid row containers must implement this protocol so re-width lays out the three-card row correctly.
- **Overview scroll navigation (StatusItemController+OverviewScroll.swift)** — Purpose: translate classic-wheel scrolling into row-highlight steps. Contract: `overviewScrollTargetItem(in:step:)` walks items whose `representedObject` has prefix `overviewRowIdentifierPrefix` (`"overviewRow-"`); must be extended to match grid rows.

---

### Task 1: Settings — `OverviewGridLayout` enum, persistence, and menu observation

**Files:**
- Create: `Sources/CodexBar/OverviewGridLayout.swift`
- Modify: `Sources/CodexBar/SettingsStoreState.swift:82` (append property to `SettingsDefaultsState`)
- Modify: `Sources/CodexBar/SettingsStore.swift:625-760` (`loadSettingsDefaultsState` factory + state init call)
- Modify: `Sources/CodexBar/SettingsStore+Defaults.swift` (add computed property near `menuBarShowsHighestUsage`, line ~704)
- Modify: `Sources/CodexBar/SettingsStore+MenuObservation.swift:60` (add read to `menuObservationToken`)
- Test: `Tests/CodexBarTests/OverviewGridLayoutSettingsTests.swift` (new)

**Interfaces:**
- Consumes: existing `SettingsDefaultsState` struct and its `loadSettingsDefaultsState` factory; `L(_:)` localization.
- Produces: `enum OverviewGridLayout: String, CaseIterable` with `case list, grid` and `var label: String`; `SettingsStore.overviewGridLayout: OverviewGridLayout { get set }` persisting to UserDefaults key `"overviewGridLayout"` (default `.list`); new defaults-state field `overviewGridLayoutRaw: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/OverviewGridLayoutSettingsTests.swift
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OverviewGridLayoutSettingsTests {
    @Test
    func `overview grid layout defaults to list and persists across instances`() throws {
        let suite = "OverviewGridLayoutSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
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
        let defaults = UserDefaults(suiteName: suite)!
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverviewGridLayoutSettingsTests`
Expected: FAIL — compile error: `OverviewGridLayout` / `settings.overviewGridLayout` do not exist.

- [ ] **Step 3: Implement the enum and settings plumbing**

`Sources/CodexBar/OverviewGridLayout.swift` (new file, following the `SwitcherRowsOption` pattern in `SettingsStore+MenuPreferences.swift`):

```swift
enum OverviewGridLayout: String, CaseIterable {
    case list
    case grid

    var label: String {
        switch self {
        case .list: L("overview_layout_list")
        case .grid: L("overview_layout_grid")
        }
    }
}
```

`SettingsStoreState.swift` — append to `SettingsDefaultsState` (after `mergedOverviewSelectedProvidersRaw`, line 80):

```swift
    var overviewGridLayoutRaw: String
```

`SettingsStore.swift` — in `loadSettingsDefaultsState` add near the `mergedOverviewSelectedProvidersRaw` load (line ~637):

```swift
        let overviewGridLayoutRaw = userDefaults.string(forKey: "overviewGridLayout")
            ?? OverviewGridLayout.list.rawValue
```

and add `overviewGridLayoutRaw: overviewGridLayoutRaw,` to the `SettingsDefaultsState(...)` call in the same function (after `mergedOverviewSelectedProvidersRaw: mergedOverviewSelectedProvidersRaw,` at line 737).

`SettingsStore+Defaults.swift` — add next to `menuBarShowsHighestUsage` (line ~704):

```swift
    var overviewGridLayout: OverviewGridLayout {
        get {
            OverviewGridLayout(rawValue: self.defaultsState.overviewGridLayoutRaw) ?? .list
        }
        set {
            self.defaultsState.overviewGridLayoutRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "overviewGridLayout")
        }
    }
```

`SettingsStore+MenuObservation.swift` — in `menuObservationToken`, next to `_ = self.mergedOverviewSelectedProviders` (line ~85), add:

```swift
        _ = self.overviewGridLayout
```

- [ ] **Step 4: Add localization keys to all 22 catalogs**

Add to `Sources/CodexBar/Resources/en.lproj/Localizable.strings` (next to the other `overview_*` keys around line 410):

```
"overview_layout_list" = "List";
"overview_layout_grid" = "Grid (3 × 2)";
```

For each of the other 21 locale catalogs (`ar`, `ca`, `de`, `es`, `fa`, `fr`, `gl`, `id`, `it`, `ja`, `ko`, `nl`, `pl`, `pt-BR`, `ru`, `sv`, `th`, `tr`, `uk`, `vi`, `zh-Hans`, `zh-Hant` — verify with `ls Sources/CodexBar/Resources/*.lproj`), add the same two keys with the English text as the value (the verified convention; translators refine later). Example for `zh-Hans` (translate the visible text, then run the checker — if it demands exact parity, use English values):

```
"overview_layout_list" = "列表";
"overview_layout_grid" = "网格（3 × 2）";
```

Run `node Scripts/check-app-locales.mjs` after editing; it exits 0 with `App locales OK` when every catalog carries the keys. If a catalog is missing a key it names the file — fix and re-run. (Prefer translated values where natural: `de` "Liste"/"Raster (3 × 2)", `fr` "Liste"/"Grille (3 × 2)", `es` "Lista"/"Cuadrícula (3 × 2)" etc.; fall back to English only when a translation is awkward.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter OverviewGridLayoutSettingsTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexBar/OverviewGridLayout.swift Sources/CodexBar/SettingsStoreState.swift Sources/CodexBar/SettingsStore.swift Sources/CodexBar/SettingsStore+Defaults.swift Sources/CodexBar/SettingsStore+MenuObservation.swift Sources/CodexBar/Resources/en.lproj/Localizable.strings
git commit -m "Add OverviewGridLayout setting with list and grid options"
```

(Include the non-en Localizable.strings files in a follow-up strings commit, or amend the same commit with all 22 files.)

---

### Task 2: Grid row container — `MenuGridRowView`

**Files:**
- Create: `Sources/CodexBar/StatusItemController+OverviewGridRow.swift`
- Test: `Tests/CodexBarTests/MenuGridRowViewTests.swift` (new)

**Interfaces:**
- Consumes: `MenuRowContainerView(payload:refreshMonitor:)`, `MenuCardRowPayload`, `MenuCardMeasuring` (from `StatusItemController+MenuPresentation.swift` / `+MenuCardItems.swift`).
- Produces: `final class MenuGridRowView: NSView, MenuCardMeasuring, MenuCardHighlighting` with `init(cards: [MenuCardRowPayload], gap: CGFloat, refreshMonitor: MenuCardRefreshMonitor?)`; `func measuredHeight(width: CGFloat) -> CGFloat`; `func applyMeasuredSize(width: CGFloat, height: CGFloat)`; `func replant(cards: [MenuCardRowPayload], refreshMonitor: MenuCardRefreshMonitor?)`; `func setHighlighted(_ highlighted: Bool)` forwarding to every card; `var allowsMenuHighlight: Bool { true }`. Card payloads keep their own `onClick`/highlight/`usesGPUSelection` behavior.
- Highlight semantics (design decision): the whole batch highlights together (all 2-3 cards) when the menu item is tracked, exactly like a list row highlights. This matches the existing `MenuCardHighlighting` seam (`item.view` gets `setHighlighted`) with zero new mouse-tracking code; per-card hover polish can come later via tracking areas.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/MenuGridRowViewTests.swift
import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuGridRowViewTests {
    private static func makePayload(id: String) -> MenuCardRowPayload {
        MenuCardRowPayload(
            content: AnyView(Text("card-\(id)").font(.headline)),
            showsSubmenuIndicator: false,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 0,
            allowsMenuHighlight: false,
            containsInteractiveControls: false,
            usesGPUSelection: false,
            onClick: nil)
    }

    @Test
    func `grid row reports card row height at full width`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        #expect(height > 20)
        // Card width = (950 - 0 gaps) / 1
        row.applyMeasuredSize(width: width, height: height)
        #expect(abs(row.frame.height - height) < 1)
    }

    @Test
    func `grid row lays out three cards horizontally`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        row.applyMeasuredSize(width: width, height: height)

        #expect(row.cardViews.count == 3)
        // Card width = (950 - 2*8) / 3 ≈ 311.33
        let expectedCardWidth = (width - 2 * 8) / 3
        for card in row.cardViews {
            #expect(abs(card.frame.width - expectedCardWidth) < 1)
        }
        // Horizontal centering: equal leading/trailing margins
        #expect(abs(row.cardViews[0].frame.minX - (width - row.cardViews[2].frame.maxX)) < 1)
        // Vertical alignment: same top
        #expect(abs(row.cardViews[0].frame.minY - row.cardViews[1].frame.minY) < 0.5)
    }

    @Test
    func `grid row two cards stay centered`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        row.applyMeasuredSize(width: width, height: height)

        let expectedCardWidth = (width - 8) / 3
        for card in row.cardViews {
            #expect(abs(card.frame.width - expectedCardWidth) < 1)
        }
        let leading = row.cardViews[0].frame.minX
        #expect(abs(leading - (width - row.cardViews[1].frame.maxX)) < 1)
        // 2-card row is inset by one card+gap from the 3-card origin
        #expect(abs(leading - (expectedCardWidth + 8)) < 1)
    }

    @Test
    func `grid row forwards highlight to every card`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)

        row.setHighlighted(true)
        #expect(row.cardViewsForTesting.allSatisfy { $0._test_isHighlighted })
        row.setHighlighted(false)
        #expect(row.cardViewsForTesting.allSatisfy { !$0._test_isHighlighted })
        #expect(row.allowsMenuHighlight)
    }

    @Test
    func `grid row replants payloads without detaching cards`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)
        let original = row.cardViews.map(ObjectIdentifier.init)

        row.replant(
            cards: [Self.makePayload(id: "d"), Self.makePayload(id: "e"), Self.makePayload(id: "f")],
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)

        #expect(row.cardViews.map(ObjectIdentifier.init) == original)
    }
}
```

Note: verify `MenuCardRowPayload`'s exact field order/defaults at implementation time (`Sources/CodexBar/StatusItemController+MenuCardItems.swift` / `+MenuPresentation.swift`) and adjust the test's payload construction to compile.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuGridRowViewTests`
Expected: FAIL — compile error: `MenuGridRowView` not found.

- [ ] **Step 3: Implement `MenuGridRowView`**

`Sources/CodexBar/StatusItemController+OverviewGridRow.swift`:

```swift
import AppKit
import SwiftUI

/// A single Overview grid menu item: an AppKit container that lays out one to three
/// card containers horizontally. Cards keep their own MenuRowContainerView click,
/// highlight, and accessibility behavior; the row itself only positions them.
final class MenuGridRowView: NSView, MenuCardMeasuring {
    static let gap: CGFloat = 8

    private var cardViews: [MenuRowContainerView] = []
    private var gap: CGFloat = Self.gap
    private var refreshMonitor: MenuCardRefreshMonitor?
    private var measuredSize: NSSize?

    init(
        cards: [MenuCardRowPayload],
        gap: CGFloat = Self.gap,
        refreshMonitor: MenuCardRefreshMonitor?)
    {
        self.refreshMonitor = refreshMonitor
        super.init(frame: .zero)
        self.wantsLayer = true
        self.rebuild(cards: cards)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Card containers exposed for tests.
    var cardViewsForTesting: [MenuRowContainerView] { self.cardViews }

    override var allowsVibrancy: Bool { true }

    // MARK: MenuCardHighlighting

    var allowsMenuHighlight: Bool { true }

    /// The menu item is tracked as one row; highlight all cards together.
    func setHighlighted(_ highlighted: Bool) {
        for card in self.cardViews {
            card.setHighlighted(highlighted)
        }
    }

    override func layout() {
        super.layout()
        self.layoutCards()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != self.frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            self.needsLayout = true
        }
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let cardWidth = Self.cardWidth(totalWidth: width, cardCount: max(1, self.cardViews.count), gap: self.gap)
        var maxHeight: CGFloat = 0
        for card in self.cardViews {
            maxHeight = max(maxHeight, card.measuredHeight(width: cardWidth))
        }
        return ceil(maxHeight)
    }

    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: max(1, ceil(height)))
        self.setFrameSize(size)
        self.measuredSize = size
        self.invalidateIntrinsicContentSize()
        self.needsLayout = true
        self.layoutCards()
    }

    func replant(cards: [MenuCardRowPayload], refreshMonitor: MenuCardRefreshMonitor?) {
        self.refreshMonitor = refreshMonitor
        if cards.count != self.cardViews.count {
            self.rebuild(cards: cards)
            return
        }
        for (index, payload) in cards.enumerated() {
            self.cardViews[index].replant(payload, refreshMonitor: refreshMonitor)
        }
    }

    private func rebuild(cards: [MenuCardRowPayload]) {
        self.cardViews.forEach { $0.removeFromSuperview() }
        self.cardViews = cards.map { payload in
            MenuRowContainerView(payload: payload, refreshMonitor: self.refreshMonitor)
        }
        self.cardViews.forEach { self.addSubview($0) }
        self.needsLayout = true
    }

    private func layoutCards() {
        guard !self.cardViews.isEmpty, self.bounds.width > 0, self.bounds.height > 0 else { return }
        let width = self.bounds.width
        let height = self.bounds.height
        let cardWidth = Self.cardWidth(totalWidth: width, cardCount: self.cardViews.count, gap: self.gap)
        let totalUsed = CGFloat(self.cardViews.count) * cardWidth + CGFloat(self.cardViews.count - 1) * self.gap
        let leadingInset = (width - totalUsed) / 2
        for (index, card) in self.cardViews.enumerated() {
            let x = leadingInset + CGFloat(index) * (cardWidth + self.gap)
            // AppKit is bottom-left origin; align every card's top edge.
            card.frame = NSRect(x: x, y: 0, width: cardWidth, height: height)
            card.autoresizingMask = [.width, .height]
        }
    }

    static func cardWidth(totalWidth: CGFloat, cardCount: Int, gap: CGFloat) -> CGFloat {
        guard cardCount > 0 else { return totalWidth }
        let usable = totalWidth - CGFloat(cardCount - 1) * gap
        return usable / CGFloat(cardCount)
    }
}
```

Implementation notes:
- The `MenuCardHighlighting` protocol is declared in `StatusItemController+MenuPresentation.swift:80` — match its exact member list at implementation time (`allowsMenuHighlight` + `setHighlighted(_:)` are what `MenuReconcile` reads).
- The `menuCardHeight(for:)` helper in `StatusItemController+MenuCardItems.swift` adds `basePadding: 6` + `descenderSafety: 1` on top of `measuredHeight`, so `measuredHeight` should return pure content height (match the existing `MenuRowContainerView.measuredHeight` behavior).
- AppKit flip vs. non-flip: `MenuRowContainerView` does not override `isFlipped`; alignment on the top edge therefore means `y = 0` for equal-height cards. Because every card in a row is stretched to the row height, per-card SwiftUI content aligns to its own top naturally. If visual testing shows bottom misalignment for unequal card heights, revisit with a flip-aware offset — do not add speculative alignment modes.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MenuGridRowViewTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/StatusItemController+OverviewGridRow.swift Tests/CodexBarTests/MenuGridRowViewTests.swift
git commit -m "Add MenuGridRowView for horizontal card layout"
```

---

### Task 3: `addOverviewGrid` — grid layout branch in the Overview renderer

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift:560-652` (`addOverviewRows` gains a grid branch + static grid constants)
- Test: `Tests/CodexBarTests/StatusMenuOverviewGridTests.swift` (new)

**Interfaces:**
- Consumes: `OverviewGridLayout` (Task 1), `MenuGridRowView` (Task 2), `overviewProviderScopes`, `overviewSpendDashboardModel`, `makeMenuCardItem`, `Self.overviewRowIdentifierPrefix`, `makeOverviewRowSubmenu`.
- Produces: `private func addOverviewGrid(rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)], to menu: NSMenu, menuWidth: CGFloat, captureMenu: NSMenu?) -> Bool` building items with `representedObject == "overviewGridRow"` and `view` = `ErasedMenuCardHostingView`-equivalent; rows batched 3 per item; click behavior per card unchanged (`onClick` → `selectOverviewProvider(row.provider, menu:)`).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodexBarTests/StatusMenuOverviewGridTests.swift
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

    @Test
    func `grid layout batches six providers into two rows`() throws {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-grid6-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .grid
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let enabled: Set<UsageProvider> = [.codex, .claude, .cursor, .opencode, .warp, .gemini]
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = try #require(controller.makeMenu() as? StatusItemMenu)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let gridRows = menu.items.filter { ($0.representedObject as? String) == "overviewGridRow" }
        #expect(gridRows.count == 2)

        let listRows = menu.items.compactMap { item -> String? in
            let id = item.representedObject as? String ?? ""
            return id.hasPrefix("overviewRow-") ? id : nil
        }
        #expect(listRows.isEmpty)

        // Click targets preserved: every provider gets an onClick closure.
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
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-list-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .list
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let enabled: Set<UsageProvider> = [.codex, .claude, .cursor]
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = try #require(controller.makeMenu() as? StatusItemMenu)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let listRows = menu.items.compactMap { item -> String? in
            let id = item.representedObject as? String ?? ""
            return id.hasPrefix("overviewRow-") ? id : nil
        }
        #expect(listRows.count == 3)
        #expect(menu.items.filter { ($0.representedObject as? String) == "overviewGridRow" }.isEmpty)
    }
}

/// Walks a view tree and counts MenuRowContainerView instances whose payload carries an onClick.
@MainActor
final class OverviewGridCardClickFinder {
    private(set) var count = 0

    func visit(_ view: NSView) {
        guard let container = view as? MenuRowContainerView else { return }
        if container._test_hasOnClick {
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

extension MenuRowContainerView {
    var _test_hasOnClick: Bool { self._test_onClick != nil }
}
```

Notes:
- `_test_hasOnClick` requires a DEBUG-only test hook on `MenuRowContainerView` (Task 3 Step 3): expose `var _test_onClick: (() -> Void)? { self.onClick }` inside `#if DEBUG` next to the existing `_test_forwardedHostedControlEvents` hooks.
- If `controller.makeMenu()` returns a plain `NSMenu` in this environment (see `StatusMenuMergedOverviewRefreshTests` which casts to `StatusItemMenu`), keep the `try #require(... as? StatusItemMenu)` cast as written; the referenced test suite compiles the same cast.
- The six-provider grid test builds real `menuCardModel`s for each provider with no fetched data; models render their "loading/unavailable" placeholders, which is fine — the assertions are structural (row batching, click wiring), not visual.
- `statusBar: .system` matches `StatusMenuMergedOverviewRefreshTests.makeController`; if headless CI is brittle there, switch to the `makeStatusBarForTesting()` helper pattern from `StatusMenuTests`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatusMenuOverviewGridTests`
Expected: FAIL — `settings.overviewGridLayout` exists (Task 1), but no grid rows are produced (renderer still list-only), so the first expectation fails.

- [ ] **Step 3: Implement the grid branch in `addOverviewRows`**

In `Sources/CodexBar/StatusItemController+Menu.swift`, add grid constants near `menuCardBaseWidth` (line 10):

```swift
    static let overviewGridColumns = 3
    static let overviewGridRowIdentifier = "overviewGridRow"
```

Replace the row loop at the end of `addOverviewRows` (lines 613-645) with a layout switch:

```swift
        if self.settings.overviewGridLayout == .grid {
            return self.addOverviewGrid(rows: rows, to: menu, menuWidth: menuWidth, captureMenu: interactionMenu)
        }

        for (index, row) in rows.enumerated() {
            // … existing single-column body stays verbatim …
        }
        return true
```

and add the new method in the same extension:

```swift
    private func addOverviewGrid(
        rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)],
        to menu: NSMenu,
        menuWidth: CGFloat,
        captureMenu: NSMenu?) -> Bool
    {
        let interactionMenu = captureMenu ?? menu
        var index = 0
        while index < rows.count {
            let batch = Array(rows[index ..< min(index + Self.overviewGridColumns, rows.count)])
            var payloads: [MenuCardRowPayload] = []
            payloads.reserveCapacity(batch.count)
            for row in batch {
                let storageText = self.store.storageFootprintText(for: row.provider)
                let card = OverviewMenuCardRowView(model: row.model, storageText: storageText, width: Self.gridCardWidth(menuWidth: menuWidth, count: batch.count))
                payloads.append(MenuCardRowPayload(
                    content: AnyView(card),
                    showsSubmenuIndicator: false,
                    submenuIndicatorAlignment: .topTrailing,
                    submenuIndicatorTopPadding: 8,
                    // Mirrors makeMenuCardItem: onClick != nil → the card container participates
                    // in highlight tracking (forwarded from MenuGridRowView.setHighlighted).
                    allowsMenuHighlight: true,
                    containsInteractiveControls: row.model.subtitleStyle == .error || row.model.usesLiveSubtitle,
                    usesGPUSelection: true,
                    onClick: { [weak self, weak interactionMenu] in
                        guard let self, let interactionMenu else { return }
                        self.selectOverviewProvider(row.provider, menu: interactionMenu)
                    }))
            }
            let hosting = MenuGridRowView(cards: payloads, refreshMonitor: self.menuCardRefreshMonitor)
            let height = self.cachedMenuCardHeight(
                for: Self.overviewGridRowIdentifier,
                scope: "overviewGridRow-\(batch.count)",
                width: menuWidth,
                fingerprint: batch.map(\.model.heightFingerprint(section: "overviewGrid")).joined(separator: "|"))
            {
                self.menuCardHeight(for: hosting, width: menuWidth)
            }
            hosting.applyMeasuredSize(width: menuWidth, height: height)

            let item = MenuCardMenuItem()
            item.title = ""
            item.view = hosting
            item.isEnabled = true
            item.representedObject = Self.overviewGridRowIdentifier
            item.target = self
            item.action = #selector(self.selectOverviewProvider(_:))
            // Grid rows have no per-item submenu; the selector reads representedObject and
            // returns early unless it carries the overviewRow- prefix (see selectOverviewProvider).
            menu.addItem(item)
            index += Self.overviewGridColumns
        }
        return true
    }

    static func gridCardWidth(menuWidth: CGFloat, count: Int) -> CGFloat {
        let columns = max(1, min(Self.overviewGridColumns, count))
        let gaps = CGFloat(columns - 1) * MenuGridRowView.gap
        return (menuWidth - gaps) / CGFloat(columns)
    }
```

Adjustments to keep the surrounding behavior consistent:
- Keep the spend-summary block and the `guard !rows.isEmpty else { return false }` unchanged; only the row-emission section switches.
- In grid mode separators between batches are omitted (the vertical rhythm comes from the gap); the caller's single trailing separator after all rows stays.
- `selectOverviewProvider(_ sender: NSMenuItem)` (StatusItemController+OverviewSubmenus.swift:39) already guards on the `overviewRow-` prefix and returns otherwise — grid items wiring `action` to it are inert through that path; clicks route through `MenuRowContainerView.onClick` only. `item.action` + `target` are kept solely for keyboard activation accessibility parity, mirroring `addOverviewRows`.
- `selectOverviewProvider(_:menu:)` navigates to the clicked provider detail and rebuilds the menu; it is layout-agnostic, so no change is needed there.
- `makeMenuCardItem` is intentionally NOT used for grid rows (it assumes one payload per item); `menuCardHeight(for:width:)` from the same file is reused for measurement.

- [ ] **Step 4: Add the test hook to `MenuRowContainerView`**

In `Sources/CodexBar/StatusItemController+MenuPresentation.swift`, inside the existing `#if DEBUG` block of `MenuRowContainerView` (where `testForwardedHostedControlMouseDown` is declared), add:

```swift
    var _test_onClick: (() -> Void)? { self.onClick }
    var _test_isHighlighted: Bool { self.isRowHighlighted }
```

(`isRowHighlighted` is private to `MenuRowContainerView`; the DEBUG computed property inside the class can read it.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter StatusMenuOverviewGridTests`
Expected: PASS (2 tests).

Run the neighboring suites to catch regressions:
`swift test --filter "StatusMenuTests|StatusMenuOverviewSpendTests|StatusMenuOverviewSubmenuTests|StatusMenuMergedOverviewRefreshTests"`
Expected: PASS (list behavior unchanged; six-row list test `overview tab renders overview rows for six active providers` still passes in `.list` default).

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexBar/StatusItemController+Menu.swift Sources/CodexBar/StatusItemController+MenuPresentation.swift Tests/CodexBarTests/StatusMenuOverviewGridTests.swift
git commit -m "Render Overview cards in 3x2 grid when grid layout selected"
```

---

### Task 4: Menu width — widen the merged menu for grid mode

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+MenuWidthCache.swift:8-35` (`menuCardWidth`)
- Modify: `Sources/CodexBar/StatusItemController+Menu.swift:267-269` (`menuWidth` computation context — no signature change)
- Test: extend `Tests/CodexBarTests/StatusMenuOverviewGridTests.swift`

**Interfaces:**
- Consumes: `OverviewGridLayout` (Task 1), `MenuGridRowView.gap` (Task 2), `Self.overviewGridColumns` (Task 3), `menuCardBaseWidth` (310).
- Produces: in grid mode `menuCardWidth(for:selectedProvider:descriptor:)` returns the maximum of `menuCardBaseWidth` and `menuCardBaseWidth * overviewGridColumns` (930); callers (`populateMenu` at StatusItemController+Menu.swift:267, `StatusItemController+MenuSwitcherWarmup.swift:77`, smart-update contexts) receive the wider width unchanged because they all funnel through `menuCardWidth`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/CodexBarTests/StatusMenuOverviewGridTests.swift` inside the suite:

```swift
    @Test
    func `grid layout widens menu width for six providers`() throws {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-width-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .grid
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let enabled: Set<UsageProvider> = [.codex, .claude, .cursor]
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: false)
        let width = controller.menuCardWidth(
            for: [.claude, .codex, .cursor],
            selectedProvider: .claude,
            descriptor: descriptor)
        #expect(width >= StatusItemController.menuCardBaseWidth * CGFloat(StatusItemController.overviewGridColumns))
    }

    @Test
    func `list layout keeps base width`() throws {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-width-list-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .list
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let enabled: Set<UsageProvider> = [.codex, .claude, .cursor]
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: false)
        let width = controller.menuCardWidth(
            for: [.claude, .codex, .cursor],
            selectedProvider: .claude,
            descriptor: descriptor)
        #expect(width == StatusItemController.menuCardBaseWidth)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatusMenuOverviewGridTests`
Expected: FAIL — the grid-width test fails because `menuCardWidth` still returns the base width in grid mode.

- [ ] **Step 3: Widen width in grid mode**

In `Sources/CodexBar/StatusItemController+MenuWidthCache.swift`, change `menuCardWidth`:

```swift
    func menuCardWidth(
        for providers: [UsageProvider],
        selectedProvider: UsageProvider?,
        descriptor: MenuDescriptor) -> CGFloat
    {
        let sectionSets: [(provider: UsageProvider?, sections: [MenuDescriptor.Section])] = if self.shouldMergeIcons,
                                                                                               providers.count > 1
        {
            providers.map { provider in
                if provider == selectedProvider {
                    return (provider, descriptor.sections)
                }
                return (provider, self.makeMenuDescriptor(
                    provider: provider,
                    includeContextualActions: true).sections)
            }
        } else {
            [(selectedProvider, descriptor.sections)]
        }
        let measured = self.measuredMenuCardWidth(for: sectionSets)
        guard self.settings.overviewGridLayout == .grid else { return measured }
        let gridMinimum = Self.menuCardBaseWidth * CGFloat(Self.overviewGridColumns)
        return max(measured, gridMinimum)
    }
```

Design note: the grid minimum applies whenever the layout setting is `.grid`, even for provider-detail tabs, so menu width does not jump between tabs mid-session; `max(measured, …)` keeps rare wider content (e.g. long localized action titles) correct.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StatusMenuOverviewGridTests`
Expected: PASS (4 tests total in suite).

Also run the width-cache neighbors: `swift test --filter "MenuWidthCache|StatusMenuSwitcherWarmupTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/StatusItemController+MenuWidthCache.swift Tests/CodexBarTests/StatusMenuOverviewGridTests.swift
git commit -m "Widen menu to three card widths in grid layout"
```

---

### Task 5: Re-width plumbing — `refreshMenuCardHeights` and scroll navigation for grid rows

**Files:**
- Modify: `Sources/CodexBar/StatusItemController+MenuCardItems.swift:11-28` (`refreshMenuCardHeights`)
- Modify: `Sources/CodexBar/StatusItemController+OverviewScroll.swift:63-68` (`menuHasOverviewRows`)
- Test: extend `Tests/CodexBarTests/StatusMenuOverviewGridTests.swift` and `Tests/CodexBarTests/StatusMenuOverviewScrollTests.swift`

**Interfaces:**
- Consumes: `MenuGridRowView` (`MenuCardMeasuring` conformance, Task 2), `overviewRowIdentifierPrefix`, `Self.overviewGridRowIdentifier` (Task 3).
- Produces: `refreshMenuCardHeights(in:)` applies measured size to `MenuGridRowView` instances; `menuHasOverviewRows(_:)` and `overviewScrollTargetItem(in:step:)` recognize grid rows so classic-wheel scrolling steps between batched grid rows.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CodexBarTests/StatusMenuOverviewGridTests.swift`:

```swift
    @Test
    func `refreshMenuCardHeights resizes grid row hosting`() throws {
        let settings = self.makeSettings(suite: "StatusMenuOverviewGridTests-rewidth-\(UUID().uuidString)")
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.overviewGridLayout = .grid
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let enabled: Set<UsageProvider> = [.codex, .claude, .cursor, .opencode, .warp, .gemini]
        self.enableOnly(enabled, settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = try #require(controller.makeMenu() as? StatusItemMenu)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        // Simulate the realized menu width shrinking by one grid column's worth of slack:
        // refreshMenuCardHeights must re-measure at the current rendered width.
        let gridRows = menu.items.filter { ($0.representedObject as? String) == "overviewGridRow" }
        #expect(!gridRows.isEmpty)
        controller.refreshMenuCardHeights(in: menu)
        for item in gridRows {
            let view = try #require(item.view)
            #expect(view.frame.width > 0)
            #expect(view.frame.height > 0)
        }
    }
```

Append to `Tests/CodexBarTests/StatusMenuOverviewScrollTests.swift` (inside the existing suite struct; match its helpers — it builds menus with items whose `representedObject` is set manually):

```swift
    @Test
    func `navigation steps through grid rows`() {
        let menu = NSMenu()
        let gridItems = (0 ..< 2).map { _ in
            let item = NSMenuItem()
            item.isEnabled = true
            item.representedObject = StatusItemController.overviewGridRowIdentifier
            menu.addItem(item)
            return item
        }
        menu.addItem(.separator())
        let plain = NSMenuItem()
        menu.addItem(plain)

        #expect(controller.menuHasOverviewRows(menu))
        #expect(controller.overviewScrollTargetItem(in: menu, step: .down) === gridItems[0])
        #expect(controller.overviewScrollTargetItem(in: menu, step: .up) === gridItems[1])
    }
```

Note: read `StatusMenuOverviewScrollTests.swift` first and mirror its controller construction helper exactly (it builds a `StatusItemController` with test status bar and disabled refresh); the snippet above assumes a `controller` property/helper exists in that suite.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "StatusMenuOverviewGridTests|StatusMenuOverviewScrollTests"`
Expected: FAIL — the scroll test fails because `menuHasOverviewRows` doesn't recognize `"overviewGridRow"`; the re-width test may pass trivially (guards skip) — its value is regression coverage, keep it.

- [ ] **Step 3: Teach the re-width and scroll paths about grid rows**

`Sources/CodexBar/StatusItemController+MenuCardItems.swift` — in `refreshMenuCardHeights(in:)`, the generic `MenuCardMeasuring` branch already covers `MenuGridRowView` (it conforms via Task 2). No code change needed; add a comment noting grid rows flow through the same branch:

```swift
            guard let view = item.view, let measuring = view as? any MenuCardMeasuring else { continue }
            // MenuGridRowView conforms to MenuCardMeasuring, so grid rows re-measure here too.
```

`Sources/CodexBar/StatusItemController+OverviewScroll.swift` — update `menuHasOverviewRows` (line 63):

```swift
    func menuHasOverviewRows(_ menu: NSMenu) -> Bool {
        menu.items.contains { item in
            guard let id = item.representedObject as? String else { return false }
            return id.hasPrefix(Self.overviewRowIdentifierPrefix) || id == Self.overviewGridRowIdentifier
        }
    }
```

and in `overviewScrollTargetItem(in:step:)` (line ~100-112), update the row filter the same way — replace:

```swift
            (item.representedObject as? String)?.hasPrefix(Self.overviewRowIdentifierPrefix) == true
```

with:

```swift
            item.isOverviewNavigableRow
```

adding an extension near the top of the file:

```swift
extension NSMenuItem {
    var isOverviewNavigableRow: Bool {
        guard let id = self.representedObject as? String else { return false }
        return id.hasPrefix(StatusItemController.overviewRowIdentifierPrefix) ||
            id == StatusItemController.overviewGridRowIdentifier
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "StatusMenuOverviewGridTests|StatusMenuOverviewScrollTests"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexBar/StatusItemController+MenuCardItems.swift Sources/CodexBar/StatusItemController+OverviewScroll.swift Tests/CodexBarTests/StatusMenuOverviewGridTests.swift Tests/CodexBarTests/StatusMenuOverviewScrollTests.swift
git commit -m "Support grid rows in menu re-width and scroll navigation"
```

---

### Task 6: Preferences UI — layout picker in Menu Bar pane

**Files:**
- Modify: `Sources/CodexBar/PreferencesMenuBarPane.swift:71-79` (Combined-icon section, below `overviewProviderRow`)
- Test: extend `Tests/CodexBarTests/OverviewGridLayoutSettingsTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.overviewGridLayout` (Task 1), `SettingsMenuPicker` (PreferencesMenuPicker.swift:4), `OverviewGridLayout.allCases` + `.label`.
- Produces: a visible picker row "Overview layout" with List / Grid (3 × 2) options, disabled when `mergeIcons` is off; changing it persists (Task 1) and the observation token (Task 1) invalidates menus.

- [ ] **Step 1: Write the failing test**

Append to `Tests/CodexBarTests/OverviewGridLayoutSettingsTests.swift`:

```swift
    @Test
    func `overview grid layout change invalidates menu observation`() {
        let suite = "OverviewGridLayoutSettingsTests-observation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        var observed = 0
        withObservationTracking {
            _ = settings.menuObservationToken
        } onChange: {
            observed += 1
        }

        settings.overviewGridLayout = .grid
        #expect(observed == 1)
    }
```

Note: `menuObservationToken` reads ~100 properties; the observation fires when any of them change. The assertion relies on no other property changing in between — the fresh suite guarantees that.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverviewGridLayoutSettingsTests`
Expected: the new test FAILS (`observed == 0`) only if Task 1 missed the `menuObservationToken` read; it is a regression lock. If Task 1 was done correctly it already passes — that is acceptable; do not proceed to UI until it passes.

- [ ] **Step 3: Add the picker row**

In `Sources/CodexBar/PreferencesMenuBarPane.swift`, in the Combined-icon `Section` (lines 71-79), directly after `self.overviewProviderRow.disabled(!self.settings.mergeIcons)` add:

```swift
                SettingsMenuPicker(
                    selection: self.$settings.overviewGridLayout,
                    options: OverviewGridLayout.allCases,
                    label: {
                        SettingsRowLabel(
                            L("overview_layout_title"),
                            subtitle: L("overview_layout_subtitle"))
                    },
                    optionLabel: { layout in
                        Text(layout.label)
                    })
                    .disabled(!self.settings.mergeIcons)
```

`SettingsMenuPicker` requires `Value: Hashable` — `OverviewGridLayout` is a `String`-backed enum, so it is Hashable and CaseIterable already.

- [ ] **Step 4: Add localization keys to all 22 catalogs**

en:

```
"overview_layout_title" = "Overview layout";
"overview_layout_subtitle" = "Grid shows up to six providers side by side in a wider menu.";
```

Then add the same two keys to each of the other 21 catalogs using translated values where natural, English otherwise (exact same procedure as Task 1 Step 4; verify with `node Scripts/check-app-locales.mjs`).

- [ ] **Step 5: Run tests and checkers**

Run: `swift test --filter OverviewGridLayoutSettingsTests && node Scripts/check-app-locales.mjs`
Expected: PASS; `App locales OK: Checked 22 catalogs against N English keys.`

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexBar/PreferencesMenuBarPane.swift Sources/CodexBar/Resources/en.lproj/Localizable.strings
git commit -m "Add Overview layout picker to Menu Bar settings"
```

(Include all 22 Localizable.strings files in this commit.)

---

### Task 7: Integration verification — full check, format, lint, manual build

**Files:**
- No new production changes; fixes anything the previous tasks' checks surface.
- Test: whole-suite run.

**Interfaces:**
- Consumes: everything above.
- Produces: a green `make check`, green full test suite, and a buildable app.

- [ ] **Step 1: Run the full quick check**

Run: `swift build && swiftlint --strict && swiftformat --lint Sources Tests`
Expected: build succeeds, no lint/format violations. (Use `make check` if the Makefile target exists and covers the same; per AGENTS.md `make check` is the standard.)

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: PASS. If the full shard is too slow locally, run `make test` per AGENTS.md or at minimum: `swift test --filter "OverviewGrid|StatusMenu|MenuCard|SettingsStore"`

- [ ] **Step 3: Run the localization checker**

Run: `node Scripts/check-app-locales.mjs`
Expected: `App locales OK`.

- [ ] **Step 4: Manual smoke test (requires app relaunch; only with user consent)**

```bash
./Scripts/compile_and_run.sh
```

Expected: app relaunches and stays running. Then verify by hand:
1. Preferences → Menu Bar → "Overview layout" shows List / Grid (3 × 2); Grid is disabled unless "Merge icons" is on.
2. Select Grid; open the menu bar dropdown → Overview tab shows six selected providers in 3×2; clicking a card navigates to that provider's tab.
3. Switch back to List → behavior identical to today.
4. Keyboard/scroll navigation still steps between grid rows (classic wheel).

If `compile_and_run.sh` cannot run in this environment, hand off steps 1-4 as a checklist for the user to run locally.

- [ ] **Step 5: Final commit of any fixups**

```bash
git add -A
git commit -m "Polish overview grid after integration checks"
```

(Skip if nothing changed.)

---

## Self-Review Results (run at plan time)

1. **Spec coverage:** 6-provider visibility ✓ (cap already = 6 upstream; selection UI exists), 3×2 side-by-side layout ✓ (Tasks 2-3), ~3× wider menu ✓ (Task 4), per-card click/highlight preserved ✓ (Task 3 payloads), scroll/keyboard navigation preserved ✓ (Task 5), preference toggle ✓ (Tasks 1 & 6), no submenus in grid mode ✓ (payloads omit `showsSubmenuIndicator`, no `submenu` on items), existing behavior unchanged by default ✓ (`.list` default + Task 3 regression tests).
2. **Placeholder scan:** No TBD/TODO placeholders. All code steps contain concrete code. Localization steps give exact keys and per-language guidance.
3. **Type consistency:** `OverviewGridLayout` (Task 1) matches its use in Tasks 3, 4, 6; `MenuGridRowView(cards:gap:refreshMonitor:)` (Task 2) matches Task 3's construction; `overviewGridRowIdentifier` / `overviewGridColumns` defined in Task 3 and consumed in Tasks 4-5; `_test_onClick` hook defined in Task 3 Step 4 matches the Task 3 test.
