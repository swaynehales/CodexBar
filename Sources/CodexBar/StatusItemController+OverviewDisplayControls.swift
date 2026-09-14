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
        case .usage: [L("compact_header_used"), L("compact_header_free")]
        case .resetTime: [L("compact_header_wait"), L("compact_header_when")]
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

    /// Header control row: an independent top toolbar. The usage pair fills the entire
    /// left half and the reset pair fills the entire right half (same outer edges and
    /// midpoint, equal segments within each pair, no captions). A plain disabled item
    /// (the proven host). Control widths never feed data budgets.
    func makeOverviewHeaderControlsItem(menu: NSMenu, width: CGFloat) -> NSMenuItem {
        let usage = self.makeHeaderSegmentControl(axis: .usage, menu: menu)
        let reset = self.makeHeaderSegmentControl(axis: .resetTime, menu: menu)
        let controlHeight = max(usage.frame.height, reset.frame.height)
        let frames = OverviewHeaderToolbarLayout.frames(width: width, controlHeight: controlHeight)
        usage.frame = frames.usage
        reset.frame = frames.reset
        for segment in 0..<2 {
            usage.setWidth(frames.segmentWidth, forSegment: segment)
            reset.setWidth(frames.segmentWidth, forSegment: segment)
        }
        let horizontalPadding = CompactTableMetrics.horizontalPadding
        let contentWidth = max(0, width - 2 * horizontalPadding)
        var containerHeight = frames.rowHeight
        let statusLabel = self.compactGlobalRefreshStatus.map { status -> NSTextField in
            let label = NSTextField(wrappingLabelWithString: status.label())
            label.font = NSFont.systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }
        let statusHeight: CGFloat = statusLabel.map {
            ceil($0.cell?.cellSize(forBounds: NSRect(
                x: 0, y: 0, width: contentWidth, height: .greatestFiniteMagnitude)).height ?? 20) + 8
        } ?? 0
        if statusLabel != nil {
            containerHeight += statusHeight + 2
        }
        // Controls stay top-anchored: when the status block is present the row floats
        // above it instead of overlapping it.
        let rowLift: CGFloat = statusLabel != nil ? statusHeight + 2 : 0
        usage.frame = usage.frame.offsetBy(dx: 0, dy: rowLift)
        reset.frame = reset.frame.offsetBy(dx: 0, dy: rowLift)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: containerHeight))
        container.autoresizingMask = [.width]
        container.addSubview(usage)
        container.addSubview(reset)
        if let statusLabel {
            statusLabel.frame = NSRect(x: horizontalPadding, y: 2, width: contentWidth, height: statusHeight)
            statusLabel.autoresizingMask = [.width]
            container.addSubview(statusLabel)
        }
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        item.identifier = Self.overviewHeaderControlsItemID
        return item
    }

    private func makeHeaderSegmentControl(
        axis: OverviewDisplayAxis,
        menu: NSMenu) -> OverviewDisplaySegmentedControl
    {
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
        return control
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
