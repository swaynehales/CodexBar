import CodexBarCore
import SwiftUI

/// Shared column metrics for both compact table views so the two groupings can never
/// drift apart in width. Tight paddings/spacings deliberately maximize the flexible
/// measure (bar) column — comparison legibility lives in the bars.
enum CompactTableMetrics {
    static let horizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 4
    static let providerMaxWidth: CGFloat = 112
    static let modelColumnWidth: CGFloat = 56
    static let periodColumnWidth: CGFloat = 58
    static let usedColumnWidth: CGFloat = 46
    static let inColumnWidth: CGFloat = 46
    /// Regular cell text sits ~3/4 of the way from the old caption (12) to the 13pt
    /// control text so the table stays slightly smaller than toggles/footer.
    static let bodyFontSize: CGFloat = 12.5
    /// Provider and used-percentage cells render at control-text size; the semibold
    /// weight carries the emphasis the operator asked for.
    static let emphasisFontSize: CGFloat = 13
}

/// One provider's block of the compact Overview table (By provider grouping).
/// Hosted one-per-`NSMenuItem` so click routing, submenus, and height caching keep
/// working exactly as they do for card rows; the menu item owns selection behavior.
struct OverviewCompactTableBlockView: View {
    let rows: [CompactTableRow]
    let showsHeader: Bool
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // One shared Grid so the header's columns resolve to the same widths as the
            // body rows; separate Grids size columns independently and drift apart.
            Grid(horizontalSpacing: CompactTableMetrics.columnSpacing, verticalSpacing: 5) {
                if self.showsHeader {
                    GridRow {
                        Text(L("compact_header_provider"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(maxWidth: CompactTableMetrics.providerMaxWidth, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        Text(L("compact_header_model"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.modelColumnWidth, alignment: .leading)
                        Text(L("compact_header_period"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.periodColumnWidth, alignment: .leading)
                        Color.clear.gridCellUnsizedAxes(.vertical)
                        Text(L("compact_header_used"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Text(L("compact_header_in"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.inColumnWidth, alignment: .trailing)
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
        .padding(.horizontal, CompactTableMetrics.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func rowCells(for row: CompactTableRow) -> some View {
        Text(row.showProvider ? row.providerDisplayName : "")
            .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: CompactTableMetrics.providerMaxWidth, alignment: .leading)
            .gridColumnAlignment(.leading)
        Text(row.model)
            .font(.system(size: CompactTableMetrics.bodyFontSize))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.modelColumnWidth, alignment: .leading)
        Text(row.periodLabel)
            .font(.system(size: CompactTableMetrics.bodyFontSize))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.periodColumnWidth, alignment: .leading)
        switch row.presentation {
        case .bar:
            self.measureCell(for: row)
            Text(row.usedText)
                .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
        case .value:
            // Balance text right-aligns in the USED column (mock placement); the bar
            // cell stays empty and IN reads "—".
            Color.clear.gridCellUnsizedAxes(.vertical)
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
            } else {
                Color.clear.gridCellUnsizedAxes(.vertical)
                    .frame(width: CompactTableMetrics.usedColumnWidth)
            }
        }
        Text(row.resetsInText)
            .font(.system(size: CompactTableMetrics.bodyFontSize).monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.inColumnWidth, alignment: .trailing)
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

/// By-period transposed table: one Grid, one section per period, provider shown once per
/// contiguous provider group inside each section. Read-only (no per-row click routing yet).
struct OverviewCompactPeriodTableView: View {
    let sections: [OverviewCompactTableModel.PeriodSection]
    let showsHeader: Bool
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(horizontalSpacing: CompactTableMetrics.columnSpacing, verticalSpacing: 5) {
                if self.showsHeader {
                    GridRow {
                        Text(L("compact_header_provider"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(maxWidth: CompactTableMetrics.providerMaxWidth, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        Text(L("compact_header_model"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.modelColumnWidth, alignment: .leading)
                        Text(L("compact_header_period"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.periodColumnWidth, alignment: .leading)
                        Color.clear.gridCellUnsizedAxes(.vertical)
                        Text(L("compact_header_used"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Text(L("compact_header_in"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.inColumnWidth, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Divider().gridCellColumns(6)
                    }
                }
                ForEach(self.sections) { section in
                    GridRow {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(6)
                            .padding(.top, 6)
                    }
                    ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                        ForEach(group) { row in
                            if row.presentation == .value {
                                GridRow(alignment: .firstTextBaseline) {
                                    self.rowCells(for: row, showsProvider: row.id == group.first?.id)
                                }
                            } else {
                                GridRow {
                                    self.rowCells(for: row, showsProvider: row.id == group.first?.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, CompactTableMetrics.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func rowCells(for row: CompactTableRow, showsProvider: Bool) -> some View {
        Text(showsProvider ? row.providerDisplayName : "")
            .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: CompactTableMetrics.providerMaxWidth, alignment: .leading)
            .gridColumnAlignment(.leading)
        Text(row.model)
            .font(.system(size: CompactTableMetrics.bodyFontSize))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.modelColumnWidth, alignment: .leading)
        // The section header carries the period label; per-row period cells stay empty
        // so the column does not repeat "Session" under its own header.
        Color.clear
            .frame(width: CompactTableMetrics.periodColumnWidth)
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
            Text(row.usedText)
                .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
        case .value:
            // Balance right-aligns in the USED column (mock placement).
            Color.clear
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: CompactTableMetrics.usedColumnWidth)
            }
        }
        Text(row.resetsInText)
            .font(.system(size: CompactTableMetrics.bodyFontSize).monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.inColumnWidth, alignment: .trailing)
    }
}
