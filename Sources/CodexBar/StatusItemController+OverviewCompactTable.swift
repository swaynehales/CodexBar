import AppKit
import CodexBarCore

/// Compact-table wiring for the Overview menu (option B). Kept out of
/// StatusItemController+Menu.swift to stay under that file's length gate.
extension StatusItemController {
    struct OverviewDisplayRow {
        let provider: UsageProvider
        let model: UsageMenuCardView.Model
        /// Non-nil when the compact table is enabled and this provider produced rows.
        let tableRows: [CompactTableRow]?
    }

    func overviewDisplayRows(
        rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)]) -> [OverviewDisplayRow]
    {
        rows.compactMap { row in
            guard self.settings.overviewCompactTableEnabled else {
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

    func makeOverviewCompactItem(
        row: OverviewDisplayRow,
        showsHeader: Bool,
        submenu: NSMenu?,
        menuWidth: CGFloat,
        interactionMenu: NSMenu?) -> NSMenuItem
    {
        let tableRows = row.tableRows ?? []
        return self.makeMenuCardItem(
            OverviewCompactTableBlockView(rows: tableRows, showsHeader: showsHeader, width: menuWidth),
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
