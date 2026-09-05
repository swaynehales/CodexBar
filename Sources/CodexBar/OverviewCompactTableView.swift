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

    private static let horizontalPadding: CGFloat = 20
    private static let modelColumnWidth: CGFloat = 44
    private static let periodColumnWidth: CGFloat = 56
    private static let usedColumnWidth: CGFloat = 40
    private static let inColumnWidth: CGFloat = 30
    private static let columnSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if self.showsHeader {
                Grid(horizontalSpacing: Self.columnSpacing, verticalSpacing: 0) {
                    GridRow {
                        Text(L("compact_header_provider"))
                            .gridColumnAlignment(.leading)
                        Text(L("compact_header_model"))
                        Text(L("compact_header_period"))
                        Color.clear.gridCellUnsizedAxes(.vertical)
                        Text(L("compact_header_used"))
                            .gridColumnAlignment(.trailing)
                        Text(L("compact_header_in"))
                            .gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .textCase(.uppercase)
                }
                Divider()
            }
            Grid(horizontalSpacing: Self.columnSpacing, verticalSpacing: 5) {
                ForEach(self.rows) { row in
                    GridRow {
                        Text(row.showProvider ? row.providerDisplayName : "")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                        self.measureCell(for: row)
                        Text(row.presentation == .bar ? row.usedText : "")
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                            .frame(width: Self.usedColumnWidth, alignment: .trailing)
                        Text(row.resetsInText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .lineLimit(1)
                            .frame(width: Self.inColumnWidth, alignment: .trailing)
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
    private func measureCell(for row: CompactTableRow) -> some View {
        switch row.presentation {
        case .bar:
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
        case .value:
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
