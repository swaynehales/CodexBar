import AppKit
import CodexBarCore

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
}

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
        self.overviewDisplayViewportRequests.removeValue(forKey: key)
        if let generation = self.menuSession.menuInteractionGeneration(for: key),
           let scroll = Self.attachedMenuScrollView(in: menu), let document = scroll.documentView
        {
            self.overviewDisplayViewportRequests[key] = OverviewDisplayViewportRequest(
                generation: generation,
                distanceFromTop: OverviewDisplayViewportRequest.distance(
                    offset: scroll.contentView.bounds.origin.y,
                    documentHeight: document.frame.height,
                    clipHeight: scroll.contentView.bounds.height,
                    flipped: document.isFlipped))
        }
        self.requestProviderSwitcherMenuRebuild(menu, provider: nil)
    }

    func makeOverviewDisplayControls(menu: NSMenu, width: CGFloat) -> NSView {
        let axes: [OverviewDisplayAxis] = [.usage]
        let groups = axes.map { axis -> NSStackView in
            let control = OverviewDisplaySegmentedControl(
                labels: axis.choices,
                trackingMode: .selectOne,
                target: self,
                action: #selector(self.overviewDisplayChoiceChanged(_:)))
            control.axis = axis
            control.trackedMenu = menu
            control.controlSize = .small
            control.font = .systemFont(ofSize: 11)
            control.segmentDistribution = .fillEqually
            control.selectedSegment = axis == .usage
                ? (self.settings.usageBarsShowUsed ? 0 : 1)
                : (self.settings.resetTimesShowAbsolute ? 1 : 0)
            control.setAccessibilityLabel(axis.label)
            control.sizeToFit()
            let label = NSTextField(labelWithString: axis.label)
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            let group = NSStackView(views: [label, control])
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
            return group
        }
        let content = NSStackView(views: groups)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: content.fittingSize.height + 12))
        content.frame = NSRect(x: 12, y: 6, width: width - 24, height: content.fittingSize.height)
        container.autoresizingMask = [.width]
        content.autoresizingMask = [.width]
        container.addSubview(content)
        return container
    }

    func restoreOverviewDisplayViewportAfterLayout(in menu: NSMenu) {
        let key = ObjectIdentifier(menu)
        guard let request = self.overviewDisplayViewportRequests[key] else { return }
        ProviderSwitcherTrackingRunLoopScheduler.schedule { [weak self, weak menu] in
            guard let self, let menu,
                  self.openMenus[key] === menu,
                  self.overviewDisplayViewportRequests[key]?.id == request.id
            else { return }
            self.overviewDisplayViewportRequests.removeValue(forKey: key)
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
