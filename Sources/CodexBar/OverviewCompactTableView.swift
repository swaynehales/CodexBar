import CodexBarCore
import SwiftUI

/// Shared column metrics for both compact table views so the two groupings can never
/// drift apart in width. Tight paddings/spacings deliberately maximize the flexible
/// measure (bar) column — comparison legibility lives in the bars.
enum CompactTableMetrics {
    static let horizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 4
    /// Provider cell width in the By-period view's data grid (provider plus model symbol).
    static let providerMaxWidth: CGFloat = 112
    /// Fixed leading/percentage tracks; reset width comes from the shared measured layout.
    static let periodColumnWidth: CGFloat = 84
    static let usedColumnWidth: CGFloat = 42
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
        max(0, totalWidth - 2 * self.horizontalPadding - fixedColumns - CGFloat(gaps) * self.columnSpacing)
    }
}

/// Compact native dropdown header cell for table percentage and reset columns.
struct OverviewCompactDropdownHeader: View {
    let axis: OverviewDisplayAxis
    let selectedIndex: Int
    let width: CGFloat
    let isHighlighted: Bool
    var onChange: ((Int) -> Void)?

    var body: some View {
        let choices = self.axis.choices
        let currentTitle = (0..<choices.count).contains(self.selectedIndex) ? choices[self.selectedIndex] : ""
        Menu {
            ForEach(0..<choices.count, id: \.self) { index in
                Button {
                    self.onChange?(index)
                } label: {
                    HStack {
                        Text(choices[index])
                        if index == self.selectedIndex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(currentTitle)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .lineLimit(1)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: self.width > 0 ? self.width : nil, alignment: .trailing)
        .menuCardInteractiveControl()
        .accessibilityLabel(self.axis.label)
        .accessibilityValue(currentTitle)
    }
}

/// Global By-provider table header (PERIOD | bar | percentage dropdown | reset dropdown) plus its single divider.
/// Hosted as its own non-interactive menu item above the first provider block so the
/// header can never land inside a provider group. Column widths reuse the body's declared
/// constants (the bar cell keeps its computed track width) so the two hosted views align.
struct OverviewCompactTableHeaderView: View {
    let showUsed: Bool
    let width: CGFloat
    var showAbsolute = false
    var percentageWidth: CGFloat = CompactTableMetrics.usedColumnWidth
    var resetWidth: CGFloat = 130
    var wrapClock = false
    var onUsageChange: ((Int) -> Void)?
    var onResetChange: ((Int) -> Void)?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(horizontalSpacing: CompactTableMetrics.columnSpacing, verticalSpacing: 5) {
                GridRow {
                    Text(L("compact_header_period"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: CompactTableMetrics.periodColumnWidth, alignment: .leading)
                    Color.clear
                        .gridCellUnsizedAxes(.vertical)
                        .frame(width: CompactTableMetrics.measureWidth(
                            totalWidth: self.width,
                            fixedColumns: CompactTableMetrics.periodColumnWidth
                                + self.percentageWidth
                                + self.resetWidth,
                            gaps: 3))
                    // Interaction experiment (recovery slice): the usage cell is a live AppKit
                    // popup on the NSControl target/action path. Reset and By-period cells
                    // keep the SwiftUI Menu views until this path proves out in the menu.
                    OverviewUsagePopUpHeader(
                        showUsed: self.showUsed,
                        width: self.percentageWidth,
                        onSelect: self.onUsageChange)
                        .frame(width: self.percentageWidth, height: 28, alignment: .trailing)
                    OverviewCompactDropdownHeader(
                        axis: .resetTime,
                        selectedIndex: self.showAbsolute ? 1 : 0,
                        width: self.resetWidth,
                        isHighlighted: self.isHighlighted,
                        onChange: self.onResetChange)
                }
            }
            Divider()
        }
        .padding(.horizontal, CompactTableMetrics.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(width: self.width, alignment: .leading)
    }
}

/// One provider's block of the compact Overview table (By provider grouping).
/// Hosted one-per-`NSMenuItem` so click routing, submenus, and height caching keep
/// working exactly as they do for card rows; the menu item owns selection behavior.
struct OverviewCompactTableBlockView: View {
    let rows: [CompactTableRow]
    let width: CGFloat
    var showAbsolute = false
    var percentageWidth: CGFloat = CompactTableMetrics.usedColumnWidth
    var resetWidth: CGFloat = 130
    var wrapClock = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Provider heading lives OUTSIDE the data grid so the first data row is a
            // normal single-line row aligned with its siblings; the deliberate gap below
            // it separates heading from first data row. The menu item owns the
            // chevron/submenu affordance, which stays attached to this heading.
            if let heading = self.rows.first?.providerDisplayName {
                Text(heading)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.bottom, 5)
            }
            // One shared Grid for the provider's data rows; the global table header lives
            // in OverviewCompactTableHeaderView, hosted above the first provider block.
            Grid(horizontalSpacing: CompactTableMetrics.columnSpacing, verticalSpacing: 5) {
                ForEach(self.rows) { row in
                    // Keep bars centered when an absolute reset wraps to date and time.
                    GridRow(alignment: .center) {
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
        // PERIOD first, then the usage bar and the trailing anchors. The model qualifier
        // rides along as an SF Symbol after the period label ("All"/empty render none) —
        // there is no model text column in this schema. All rows are retained.
        HStack(alignment: .firstTextBaseline, spacing: CompactTableMetrics.columnSpacing) {
            Text(OverviewCompactTableModel.byProviderPeriodLabel(row.period))
                .font(.system(size: CompactTableMetrics.metadataFontSize))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .truncationMode(.tail)
            if let symbol = OverviewCompactTableModel.modelQualifierSymbol(row.model) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }
        }
        .frame(width: CompactTableMetrics.periodColumnWidth, alignment: .leading)
        switch row.presentation {
        case .bar:
            self.measureCell(for: row)
            Text(row.usedText)
                .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: self.percentageWidth, alignment: .trailing)
        case .value:
            // Balance text right-aligns in the USED column (mock placement); the bar
            // cell keeps the declared track width so USED/IN anchors never shift.
            Color.clear
                .frame(width: CompactTableMetrics.measureWidth(
                    totalWidth: self.width,
                    fixedColumns: CompactTableMetrics.periodColumnWidth
                        + self.percentageWidth
                        + self.resetWidth,
                    gaps: 3))
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: self.percentageWidth, alignment: .trailing)
            } else {
                Color.clear.gridCellUnsizedAxes(.vertical)
                    .frame(width: self.percentageWidth)
            }
        }
        OverviewCompactResetCell(
            text: row.resetText,
            showAbsolute: self.showAbsolute,
            width: self.resetWidth,
            wrapClock: self.wrapClock)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
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
                    fixedColumns: CompactTableMetrics.periodColumnWidth
                        + self.percentageWidth
                        + self.resetWidth,
                    gaps: 3))
        }
    }
}

/// By-period table: single-line provider/model rows grouped under period headings.
/// Read-only (no per-row click routing yet).
struct OverviewCompactPeriodTableView: View {
    let sections: [OverviewCompactTableModel.PeriodSection]
    let showsHeader: Bool
    let showUsed: Bool
    let width: CGFloat
    var showAbsolute = false
    var percentageWidth: CGFloat = CompactTableMetrics.usedColumnWidth
    var resetWidth: CGFloat = 130
    var wrapClock = false
    var onUsageChange: ((Int) -> Void)?
    var onResetChange: ((Int) -> Void)?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(horizontalSpacing: CompactTableMetrics.columnSpacing, verticalSpacing: 5) {
                if self.showsHeader {
                    GridRow {
                        Text(L("compact_header_provider"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                            .textCase(.uppercase)
                            .frame(width: CompactTableMetrics.providerMaxWidth, alignment: .leading)
                            .gridColumnAlignment(.leading)
                        Color.clear.gridCellUnsizedAxes(.vertical)
                        OverviewCompactDropdownHeader(
                            axis: .usage,
                            selectedIndex: self.showUsed ? 0 : 1,
                            width: self.percentageWidth,
                            isHighlighted: self.isHighlighted,
                            onChange: self.onUsageChange)
                        OverviewCompactDropdownHeader(
                            axis: .resetTime,
                            selectedIndex: self.showAbsolute ? 1 : 0,
                            width: self.resetWidth,
                            isHighlighted: self.isHighlighted,
                            onChange: self.onResetChange)
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
                    ForEach(section.groups.flatMap(\.self)) { row in
                        GridRow(alignment: .center) {
                            self.rowCells(for: row)
                        }
                    }
                    if section.id != self.sections.last?.id {
                        GridRow {
                            Divider().gridCellColumns(4).padding(.top, 6)
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
        HStack(alignment: .firstTextBaseline, spacing: CompactTableMetrics.columnSpacing) {
            Text(row.providerDisplayName)
                .font(.system(size: CompactTableMetrics.metadataFontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let symbol = OverviewCompactTableModel.modelQualifierSymbol(row.model) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .accessibilityLabel(row.model)
            }
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
                            + self.percentageWidth
                            + self.resetWidth,
                        gaps: 3))
            }
            Text(row.usedText)
                .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: self.percentageWidth, alignment: .trailing)
        case .value:
            // Balance right-aligns in the USED column (mock placement); the bar cell
            // keeps the declared track width so USED/IN anchors never shift.
            Color.clear
                .frame(width: CompactTableMetrics.measureWidth(
                    totalWidth: self.width,
                    fixedColumns: CompactTableMetrics.providerMaxWidth
                        + self.percentageWidth
                        + self.resetWidth,
                    gaps: 3))
            if let valueText = row.valueText, !valueText.isEmpty {
                Text(valueText)
                    .font(.system(size: CompactTableMetrics.emphasisFontSize, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: self.percentageWidth, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: self.percentageWidth)
            }
        }
        OverviewCompactResetCell(
            text: row.resetText,
            showAbsolute: self.showAbsolute,
            width: self.resetWidth,
            wrapClock: self.wrapClock)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

/// Derive date/time lines from the Date, never by splitting a localized clock string.
private struct OverviewCompactResetCell: View {
    let text: OverviewCompactResetText
    let showAbsolute: Bool
    let width: CGFloat
    let wrapClock: Bool

    var body: some View {
        let font = NSFont.monospacedDigitSystemFont(ofSize: CompactTableMetrics.metadataFontSize, weight: .regular)
        let exceedsWidth = (self.text.clock as NSString).size(withAttributes: [.font: font]).width > self.width
        Text(self.text.lines(showAbsolute: self.showAbsolute, wrapClock: self.wrapClock || exceedsWidth)
            .joined(separator: "\n"))
            .font(.system(size: CompactTableMetrics.metadataFontSize).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: self.width, alignment: .trailing)
    }
}
