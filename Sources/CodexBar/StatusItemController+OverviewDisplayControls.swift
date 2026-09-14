import AppKit
import CodexBarCore
import SwiftUI

enum OverviewDisplayAxis: CaseIterable {
    case usage
    case resetTime

    var label: String {
        L(self == .usage ? "section_usage" : "reset_times_title")
    }

    var choices: [String] {
        switch self {
        case .usage: [L("compact_header_used"), L("compact_header_remaining")]
        case .resetTime: [L("reset_times_countdown"), L("reset_times_clock")]
        }
    }

    /// Short segment labels for the restored header controls (approved copy).
    var segmentTitles: [String] {
        switch self {
        case .usage: [L("compact_header_used"), L("compact_header_left")]
        case .resetTime: [L("compact_header_in"), L("compact_header_at")]
        }
    }

    /// Full descriptive names shown as per-segment tooltips.
    var segmentToolTips: [String] {
        self.choices
    }
}

struct OverviewDisplayState {
    var layouts: [ObjectIdentifier: OverviewCompactTableLayout] = [:]
    var viewportRequests: [ObjectIdentifier: OverviewDisplayViewportRequest] = [:]
}

/// Restored segmented control for the header control row: a real NSControl with
/// target/action inside a plain disabled menu item (the host the operator verified
/// working). Segment labels are the short approved copy; tooltips and accessibility
/// labels carry the full descriptive names.
final class OverviewDisplaySegmentedControl: NSSegmentedControl {
    var axis: OverviewDisplayAxis = .usage
    weak var trackedMenu: NSMenu?
}

/// Placement of one labeled segment group inside the header control row.
private struct HeaderSegmentPlacement {
    static let labelHeight: CGFloat = 13
    static let rowGap: CGFloat = 4
    let segmentX: CGFloat
    let top: CGFloat
}

struct OverviewDisplayViewportRequest {
    let id = UUID()
    let generation: Int
    let distanceFromTop: CGFloat

    static func distance(offset: CGFloat, documentHeight: CGFloat, clipHeight: CGFloat, flipped: Bool) -> CGFloat {
        let maximum = max(0, documentHeight - clipHeight)
        return min(maximum, max(0, flipped ? offset : maximum - offset))
    }

    func offset(documentHeight: CGFloat, clipHeight: CGFloat, flipped: Bool) -> CGFloat {
        let maximum = max(0, documentHeight - clipHeight)
        let distance = min(maximum, max(0, self.distanceFromTop))
        return flipped ? distance : maximum - distance
    }
}

extension StatusItemController {
    @objc func overviewDisplayChoiceChanged(_ sender: OverviewDisplaySegmentedControl) {
        guard let menu = sender.trackedMenu else { return }
        self.applyOverviewDisplayChoice(axis: sender.axis, selectedSegment: sender.selectedSegment, menu: menu)
    }

    /// Header control row: labeled usage/reset segments over the right-side columns in
    /// a plain disabled item (the proven host). Control widths never feed data budgets;
    /// groups stagger vertically only when they cannot sit side by side.
    func makeOverviewHeaderControlsItem(
        menu: NSMenu,
        width: CGFloat,
        layout: OverviewCompactTableLayout? = nil) -> NSMenuItem
    {
        let resetWidth = layout?.resetWidth ?? 68
        let usageGroup = self.makeHeaderSegmentGroup(axis: .usage, menu: menu)
        let resetGroup = self.makeHeaderSegmentGroup(axis: .resetTime, menu: menu)
        let horizontalPadding = CompactTableMetrics.horizontalPadding
        let contentWidth = max(0, width - 2 * horizontalPadding)
        let usageSegW = min(usageGroup.control.frame.width, contentWidth)
        let resetSegW = min(resetGroup.control.frame.width, contentWidth)
        let resetSegX = max(horizontalPadding, width - horizontalPadding - resetSegW)
        let percentageRight = width - horizontalPadding - resetWidth - CompactTableMetrics.columnSpacing
        let usageSegX = max(horizontalPadding, percentageRight - usageSegW)
        // Segments overlap when the usage cell cannot clear the reset group; stack the
        // groups (usage above reset, same column alignment) instead of compressing them.
        let staggered = percentageRight > resetSegX
        let labelHeight = HeaderSegmentPlacement.labelHeight
        let singleRowHeight: CGFloat = 6 + labelHeight + HeaderSegmentPlacement.rowGap +
            usageGroup.control.frame.height + 6
        let containerHeight = staggered ? 2 * singleRowHeight - 6 : singleRowHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: containerHeight))
        container.autoresizingMask = [.width]
        self.placeHeaderSegmentGroup(
            usageGroup,
            in: container,
            placement: HeaderSegmentPlacement(segmentX: usageSegX, top: containerHeight - 6))
        self.placeHeaderSegmentGroup(
            resetGroup,
            in: container,
            placement: HeaderSegmentPlacement(
                segmentX: resetSegX,
                top: staggered ? containerHeight - 6 - singleRowHeight : containerHeight - 6))
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        item.identifier = Self.overviewHeaderControlsItemID
        return item
    }

    private func makeHeaderSegmentGroup(
        axis: OverviewDisplayAxis,
        menu: NSMenu) -> (label: NSTextField, control: OverviewDisplaySegmentedControl)
    {
        let label = NSTextField(labelWithString: axis.label)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.sizeToFit()
        let control = OverviewDisplaySegmentedControl(
            labels: axis.segmentTitles,
            trackingMode: .selectOne,
            target: self,
            action: #selector(self.overviewDisplayChoiceChanged(_:)))
        control.axis = axis
        control.trackedMenu = menu
        control.controlSize = .small
        control.font = NSFont.systemFont(ofSize: 11)
        control.selectedSegment = axis == .usage
            ? (self.settings.usageBarsShowUsed ? 0 : 1)
            : (self.settings.resetTimesShowAbsolute ? 1 : 0)
        for index in axis.segmentTitles.indices {
            control.setToolTip(axis.segmentToolTips[index], forSegment: index)
        }
        control.setAccessibilityLabel(axis.label)
        control.sizeToFit()
        return (label, control)
    }

    private func placeHeaderSegmentGroup(
        _ group: (label: NSTextField, control: OverviewDisplaySegmentedControl),
        in container: NSView,
        placement: HeaderSegmentPlacement)
    {
        let labelHeight = HeaderSegmentPlacement.labelHeight
        let rowGap = HeaderSegmentPlacement.rowGap
        let segH = group.control.frame.height
        group.control.frame = NSRect(
            x: placement.segmentX,
            y: placement.top - labelHeight - rowGap - segH,
            width: group.control.frame.width,
            height: segH)
        group.control.autoresizingMask = [.minXMargin]
        group.label.frame = NSRect(
            x: placement.segmentX,
            y: placement.top - labelHeight,
            width: max(group.label.frame.width, group.control.frame.width),
            height: labelHeight)
        group.label.autoresizingMask = [.minXMargin]
        container.addSubview(group.control)
        container.addSubview(group.label)
    }

    func applyOverviewDisplayChoice(axis: OverviewDisplayAxis, selectedSegment: Int, menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        guard self.openMenus[key] === menu, (0...1).contains(selectedSegment) else { return }
        switch axis {
        case .usage:
            let showUsed = selectedSegment == 0
            guard self.settings.usageBarsShowUsed != showUsed else { return }
            self.settings.usageBarsFillOption = showUsed ? .used : .remaining
        case .resetTime:
            let showAbsolute = selectedSegment == 1
            guard self.settings.resetTimesShowAbsolute != showAbsolute else { return }
            self.settings.resetTimesOption = showAbsolute ? .clock : .countdown
        }
        self.refreshProviderSelectionDependentUI(deferRendering: true)
        if menu !== self.mergedMenu {
            self.advanceMenuInteraction(for: menu)
        }
        self.overviewDisplayState.viewportRequests.removeValue(forKey: key)
        if let generation = self.menuSession.menuInteractionGeneration(for: key),
           let scroll = Self.attachedMenuScrollView(in: menu), let document = scroll.documentView
        {
            self.overviewDisplayState.viewportRequests[key] = OverviewDisplayViewportRequest(
                generation: generation,
                distanceFromTop: OverviewDisplayViewportRequest.distance(
                    offset: scroll.contentView.bounds.origin.y,
                    documentHeight: document.frame.height,
                    clipHeight: scroll.contentView.bounds.height,
                    flipped: document.isFlipped))
        }
        self.requestProviderSwitcherMenuRebuild(menu, provider: nil)
    }

    func restoreOverviewDisplayViewportAfterLayout(in menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        guard let request = self.overviewDisplayState.viewportRequests[key] else { return }
        ProviderSwitcherTrackingRunLoopScheduler.schedule { [weak self, weak menu] in
            guard let self, let menu,
                  self.openMenus[key] === menu,
                  self.overviewDisplayState.viewportRequests[key]?.id == request.id
            else { return }
            self.overviewDisplayState.viewportRequests.removeValue(forKey: key)
            guard self.menuSession.isCurrentMenuInteraction(request.generation, for: key),
                  let scroll = Self.attachedMenuScrollView(in: menu), let document = scroll.documentView
            else { return }
            document.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            let offset = request.offset(
                documentHeight: document.frame.height, clipHeight: clip.bounds.height, flipped: document.isFlipped)
            self.performMenuMutationWithoutAnimation {
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: offset))
                scroll.reflectScrolledClipView(clip)
            }
        }
    }
}
