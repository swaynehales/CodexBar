import CodexBarCore
import SwiftUI

/// Shared column metrics for both compact table views so the two groupings can never
/// drift apart in width. Tight paddings/spacings deliberately maximize the flexible
/// measure (bar) column — comparison legibility lives in the bars.
enum CompactTableMetrics {
    static let horizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 4
    static let providerMaxWidth: CGFloat = 112
    static let periodColumnWidth: CGFloat = 50
    static let usedColumnWidth: CGFloat = 46
    static let inColumnWidth: CGFloat = 46
    /// Regular cell text sits ~3/4 of the way from the old caption (12) to the 13pt
    /// control text so the table stays slightly smaller than toggles/footer.
    static let metadataFontSize: CGFloat = 12
    /// Provider and used-percentage cells render at control-text size; the semibold
    /// weight carries the emphasis the operator asked for.
    static let emphasisFontSize: CGFloat = 13

    /// The bar track occupies the declared remainder after the fixed columns, so every
    /// bar starts and ends at shared x-positions instead of sizing to its intrinsic
    /// width. `fixedColumns` is the sum of the leading/trailing fixed column widths and
    /// `gaps` the Grid's horizontal gaps for that view's column count.
    static func measureWidth(totalWidth: CGFloat, fixedColumns: CGFloat, gaps: Int) -> CGFloat {
        totalWidth - 2 * self.horizontalPadding - fixedColumns - CGFloat(gaps) * self.columnSpacing
    }
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
                        // Two-line header labels the merged provider/model column: the
                        // body stacks the model beneath the provider, so the header does
                        // too (MODEL lighter than PROVIDER).
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("compact_header_provider"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .textCase(.uppercase)
                            Text(L("compact_header_model"))
                                .font(.caption)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .textCase(.uppercase)
                        }
                        .frame(width: CompactTableMetrics.providerMaxWidth, alignment: .leading)
                        .gridColumnAlignment(.leading)
                        Text(L("compact_header_period"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
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
                        Divider().gridCellColumns(5)
                    }
                }
                ForEach(self.rows) { row in
                    // Bottom alignment puts the first row's period/bar/USED/IN cells on
                    // the model subrow's line (the merged cell's bottom edge) instead of
                    // centering them between provider heading and model; single-line rows
                    // are unaffected since all their cells share one line.
                    GridRow(alignment: .bottom) {
                        self.rowCells(for: row)
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
        // Provider (emphasized) with the model stacked beneath it in the same column;
        // merging the two frees the rest of the row for the flexible bar column. The
        // provider line renders only on the group's first row: later rows are single-line
        // model subrows with no reserved blank provider height.
        VStack(alignment: .leading, spacing: 1) {
            if row.showProvider {
                Text(row.providerDisplayName)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(row.model)
                .font(.system(size: CompactTableMetrics.metadataFontSize))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: CompactTableMetrics.providerMaxWidth, alignment: .leading)
        .gridColumnAlignment(.leading)
        Text(OverviewCompactTableModel.abbreviatedPeriodLabel(row.period))
            .font(.system(size: CompactTableMetrics.metadataFontSize))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
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
            // cell keeps the declared track width so USED/IN anchors never shift.
            Color.clear
                .frame(width: CompactTableMetrics.measureWidth(
                    totalWidth: self.width,
                    fixedColumns: CompactTableMetrics.providerMaxWidth
                        + CompactTableMetrics.periodColumnWidth
                        + CompactTableMetrics.usedColumnWidth
                        + CompactTableMetrics.inColumnWidth,
                    gaps: 4))
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
            .font(.system(size: CompactTableMetrics.metadataFontSize).monospacedDigit())
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
                .frame(width: CompactTableMetrics.measureWidth(
                    totalWidth: self.width,
                    fixedColumns: CompactTableMetrics.providerMaxWidth
                        + CompactTableMetrics.periodColumnWidth
                        + CompactTableMetrics.usedColumnWidth
                        + CompactTableMetrics.inColumnWidth,
                    gaps: 4))
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
                        // Same two-line PROVIDER/MODEL cue as the By-provider view; the
                        // period concept is labeled by the section headers in this view.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("compact_header_provider"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .textCase(.uppercase)
                            Text(L("compact_header_model"))
                                .font(.caption)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .textCase(.uppercase)
                        }
                        .frame(width: CompactTableMetrics.providerMaxWidth, alignment: .leading)
                        .gridColumnAlignment(.leading)
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
                        Divider().gridCellColumns(4)
                    }
                }
                ForEach(self.sections) { section in
                    GridRow {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gridCellColumns(4)
                            .padding(.top, 6)
                    }
                    ForEach(Array(section.groups.enumerated()), id: \.offset) { groupIndex, group in
                        ForEach(group) { row in
                            // Bottom alignment keeps every row's data cells on the model
                            // subrow's line, first row included; see the By-provider view.
                            GridRow(alignment: .bottom) {
                                self.rowCells(for: row, showsProvider: row.id == group.first?.id)
                            }
                        }
                        // Subtle separator after each provider block but never between
                        // model subrows; the section header ends the last block.
                        if groupIndex < section.groups.count - 1 {
                            GridRow {
                                Divider().gridCellColumns(4)
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
        // Same provider→model nesting as the By-provider view: provider name once per
        // group on its own line, model subrows single-line beneath it with no reserved
        // blank provider height. The section header carries the period, so no per-row
        // period cell exists in this view.
        VStack(alignment: .leading, spacing: 1) {
            if showsProvider {
                Text(row.providerDisplayName)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(row.model)
                .font(.system(size: CompactTableMetrics.metadataFontSize))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: CompactTableMetrics.providerMaxWidth, alignment: .leading)
        .gridColumnAlignment(.leading)
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
                    .frame(width: CompactTableMetrics.measureWidth(
                        totalWidth: self.width,
                        fixedColumns: CompactTableMetrics.providerMaxWidth
                            + CompactTableMetrics.usedColumnWidth
                            + CompactTableMetrics.inColumnWidth,
                        gaps: 3))
            }
            Text(row.usedText)
                .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: CompactTableMetrics.usedColumnWidth, alignment: .trailing)
        case .value:
            // Balance right-aligns in the USED column (mock placement); the bar cell
            // keeps the declared track width so USED/IN anchors never shift.
            Color.clear
                .frame(width: CompactTableMetrics.measureWidth(
                    totalWidth: self.width,
                    fixedColumns: CompactTableMetrics.providerMaxWidth
                        + CompactTableMetrics.usedColumnWidth
                        + CompactTableMetrics.inColumnWidth,
                    gaps: 3))
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
            .font(.system(size: CompactTableMetrics.metadataFontSize).monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(width: CompactTableMetrics.inColumnWidth, alignment: .trailing)
    }
}
