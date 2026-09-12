import AppKit
import CodexBarCore

/// Compact-table wiring for the Overview menu (option B). Kept out of
/// StatusItemController+Menu.swift to stay under that file's length gate.
/// Compact-table grouping for the Overview tab. Transient by design (spec §6): resets to
/// By provider on relaunch.
enum OverviewTableGrouping {
    case provider
    case period
}

final class OverviewGroupingSegmentedControl: NSSegmentedControl {
    /// The tracked menu this control lives in, captured at build time; NSView's own `menu`
    /// property is the context menu, not the NSMenu hosting the item view.
    weak var trackedMenu: NSMenu?
}

extension StatusItemController {
    var overviewTableGrouping: OverviewTableGrouping {
        get { self.overviewTableGroupingState }
        set { self.overviewTableGroupingState = newValue }
    }

    @objc func overviewTableGroupingChanged(_ sender: OverviewGroupingSegmentedControl) {
        let grouping: OverviewTableGrouping = sender.selectedSegment == 1 ? .period : .provider
        guard grouping != self.overviewTableGrouping, let menu = sender.trackedMenu else { return }
        self.overviewTableGrouping = grouping
        // Mirror selectOverviewProvider's rebuild pattern: bump the content version (so
        // cached switcher content for the same selection is never served), then schedule
        // the rebuild and request an immediate in-place rebuild while the pointer is up.
        self.refreshProviderSelectionDependentUI(deferRendering: true)
        self.requestProviderSwitcherMenuRebuild(menu, provider: nil)
    }

    func makeOverviewGroupingToggleItem(menu: NSMenu, width: CGFloat) -> NSMenuItem {
        let control = OverviewGroupingSegmentedControl(
            labels: [L("overview_grouping_provider"), L("overview_grouping_period")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(self.overviewTableGroupingChanged(_:)))
        control.selectedSegment = self.overviewTableGrouping == .period ? 1 : 0
        control.trackedMenu = menu
        let contentWidth = width - 2 * CompactTableMetrics.horizontalPadding
        // Grow the control itself, not just its padding: 42pt segment (roughly 2x the
        // original 22pt) with a 13pt label, inside a 48pt container for breathing room
        // under the menu bar.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 48))
        control.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        control.frame = NSRect(
            x: CompactTableMetrics.horizontalPadding,
            y: 3,
            width: contentWidth,
            height: 42)
        control.autoresizingMask = [.width]
        container.addSubview(control)
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }

    /// By-period transpose: one read-only hosted table across all providers.
    func addOverviewPeriodTableItem(
        displayRows: [OverviewDisplayRow],
        menu: NSMenu,
        width: CGFloat) -> Bool
    {
        let allRows = displayRows.compactMap(\.tableRows).flatMap(\.self)
        guard !allRows.isEmpty else { return false }
        menu.addItem(self.makeOverviewPeriodTableItem(rows: allRows, width: width))
        return true
    }

    func makeOverviewPeriodTableItem(rows: [CompactTableRow], width: CGFloat) -> NSMenuItem {
        let sections = OverviewCompactTableModel.periodSections(rows: rows)
        return self.makeMenuCardItem(
            OverviewCompactPeriodTableView(sections: sections, showsHeader: true, width: width),
            id: "overviewCompactPeriod",
            width: width,
            heightCacheScope: "overview-compact-period",
            heightCacheFingerprint: rows
                .map { [$0.id, $0.usedText, $0.resetsInText, $0.valueText ?? ""].joined(separator: ",") }
                .joined(separator: "|"),
            submenu: nil,
            usesGPUSelection: true)
    }

    /// Fixed width for compact Overview table blocks. The descriptor-derived menu width is
    /// sized for stacked cards (~310pt) and starves the table; 456pt fits the By-provider
    /// 1:3:1 budget (84pt period track, 252pt bar, 84pt USED+IN anchors) without
    /// truncating the full period labels.
    static let compactOverviewMenuWidth: CGFloat = 456

    struct OverviewDisplayRow {
        let provider: UsageProvider
        let model: UsageMenuCardView.Model
        /// Non-nil when the compact table is enabled and this provider produced rows.
        let tableRows: [CompactTableRow]?
    }

    func overviewDisplayRows(
        rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)],
        compactEnabled: Bool) -> [OverviewDisplayRow]
    {
        rows.compactMap { row in
            guard compactEnabled else {
                return OverviewDisplayRow(provider: row.provider, model: row.model, tableRows: nil)
            }
            let tableRows = OverviewCompactTableModel.rows(
                provider: row.provider,
                model: row.model,
                snapshot: self.store.presentationSnapshot(for: row.provider))
            guard !tableRows.isEmpty else { return nil }
            return OverviewDisplayRow(provider: row.provider, model: row.model, tableRows: tableRows)
        }
    }

    /// Identifier marking the global By-provider header item inside a menu, so repeated
    /// block construction can never add it twice.
    static let overviewCompactHeaderItemID = NSUserInterfaceItemIdentifier("overviewCompactHeader")

    /// Adds the global By-provider table header exactly once, above the first provider
    /// block of a compact menu — never inside one (the old first-block placement bug).
    func ensureOverviewCompactHeaderInserted(
        row: OverviewDisplayRow,
        into menu: NSMenu,
        width: CGFloat)
    {
        guard row.tableRows != nil,
              !menu.items.contains(where: { $0.identifier == Self.overviewCompactHeaderItemID })
        else { return }
        menu.addItem(self.makeOverviewCompactHeaderItem(width: width))
    }

    /// Global By-provider header row, hosted as its own item above the first provider
    /// block; adding it to the menu exactly once is the caller's job.
    func makeOverviewCompactHeaderItem(width: CGFloat) -> NSMenuItem {
        let item = self.makeMenuCardItem(
            OverviewCompactTableHeaderView(width: width),
            id: "overviewCompactHeader",
            width: width,
            heightCacheScope: "overview-compact-header",
            heightCacheFingerprint: "v1",
            submenu: nil,
            usesGPUSelection: true)
        item.identifier = Self.overviewCompactHeaderItemID
        return item
    }

    func makeOverviewCompactItem(
        row: OverviewDisplayRow,
        submenu: NSMenu?,
        menuWidth: CGFloat,
        interactionMenu: NSMenu?) -> NSMenuItem
    {
        let tableRows = row.tableRows ?? []
        return self.makeMenuCardItem(
            OverviewCompactTableBlockView(rows: tableRows, width: menuWidth),
            id: "\(Self.overviewRowIdentifierPrefix)\(row.provider.rawValue)",
            width: menuWidth,
            heightCacheScope: "\(row.provider.rawValue)-compact",
            heightCacheFingerprint: tableRows
                .map { [$0.id, $0.usedText, $0.resetsInText, $0.valueText ?? ""].joined(separator: ",") }
                .joined(separator: "|"),
            submenu: submenu,
            containsInteractiveControls: row.model.subtitleStyle == .error || row.model.usesLiveSubtitle,
            usesGPUSelection: true,
            onClick: { [weak self, weak interactionMenu] in
                guard let self, let interactionMenu else { return }
                self.selectOverviewProvider(row.provider, menu: interactionMenu)
            })
    }
}
