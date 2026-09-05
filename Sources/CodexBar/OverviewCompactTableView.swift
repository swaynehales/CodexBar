import CodexBarCore
import SwiftUI

/// One provider's block of the compact Overview table (By provider grouping).
/// Hosted one-per-`NSMenuItem` so click routing, submenus, and height caching keep
/// working exactly as they do for card rows; the menu item owns selection behavior.
struct OverviewCompactTableBlockView: View {
    let rows: [CompactTableRow]
    let showsHeader: Bool
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private static let horizontalPadding: CGFloat = 16
    private static let columnSpacing: CGFloat = 6
    private static let providerMaxWidth: CGFloat = 104
    private static let modelColumnWidth: CGFloat = 40
    private static let periodColumnWidth: CGFloat = 44
    private static let usedColumnWidth: CGFloat = 32
    private static let inColumnWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One shared Grid so the header's columns resolve to the same widths as the
            // body rows; separate Grids size columns independently and drift apart.
            Grid(horizontalSpacing: Self.columnSpacing, verticalSpacing: 5) {
                if self.showsHeader {
                    GridRow {
                        Text(L("compact_header_provider"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(maxWidth: Self.providerMaxWidth, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        Text(L("compact_header_model"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: Self.modelColumnWidth, alignment: .leading)
                        Text(L("compact_header_period"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: Self.periodColumnWidth, alignment: .leading)
                        Color.clear.gridCellUnsizedAxes(.vertical)
                        Text(L("compact_header_used"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: Self.usedColumnWidth, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Text(L("compact_header_in"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: Self.inColumnWidth, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Divider().gridCellColumns(6)
                    }
                }
                ForEach(self.rows) { row in
                    // Value rows have no bar cell, so center alignment reads as vertically
                    // off against the footnote provider name; baseline-align them instead.
                    if row.presentation == .value {
                        GridRow(alignment: .firstTextBaseline) {
                            self.rowCells(for: row)
                        }
                    } else {
                        GridRow {
                            self.rowCells(for: row)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func rowCells(for row: CompactTableRow) -> some View {
        Text(row.showProvider ? row.providerDisplayName : "")
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.providerMaxWidth, alignment: .leading)
            .gridColumnAlignment(.leading)
        Text(row.model)
            .font(.caption)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: Self.modelColumnWidth, alignment: .leading)
        Text(row.periodLabel)
            .font(.caption)
            .lineLimit(1)
            .frame(width: Self.periodColumnWidth, alignment: .leading)
        switch row.presentation {
        case .bar:
            self.measureCell(for: row)
            Text(row.usedText)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .frame(width: Self.usedColumnWidth, alignment: .trailing)
        case .value:
            // Balance/renewal text spans the bar + USED columns. Caption
            // size keeps the row height and baseline matching bar rows.
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gridCellColumns(2)
            } else {
                Color.clear.gridCellUnsizedAxes(.vertical)
                    .gridCellColumns(2)
            }
        }
        Text(row.resetsInText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: Self.inColumnWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func measureCell(for row: CompactTableRow) -> some View {
        if let metric = row.metric {
            UsageProgressBar(
                percent: metric.percent,
                tint: Color(red: row.tint.red, green: row.tint.green, blue: row.tint.blue),
                accessibilityLabel: metric.percentStyle.accessibilityLabel,
                pacePercent: metric.pacePercent,
                paceOnTop: metric.paceOnTop,
                warningMarkerPercents: metric.warningMarkerPercents,
                workdayMarkerPercents: metric.workdayMarkerPercents,
                workdayTickAppearance: metric.workdayTickAppearance)
        }
    }
}
