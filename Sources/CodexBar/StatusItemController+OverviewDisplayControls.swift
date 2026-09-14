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

final class OverviewDisplayPopUpButton: NSPopUpButton {
    var axis: OverviewDisplayAxis = .usage
    weak var trackedMenu: NSMenu?
}

struct OverviewDisplayState {
    var layouts: [ObjectIdentifier: OverviewCompactTableLayout] = [:]
    var viewportRequests: [ObjectIdentifier: OverviewDisplayViewportRequest] = [:]
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
    @objc func overviewDisplayChoiceChanged(_ sender: OverviewDisplayPopUpButton) {
        guard let menu = sender.trackedMenu else { return }
        self.applyOverviewDisplayChoice(axis: sender.axis, selectedSegment: sender.indexOfSelectedItem, menu: menu)
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

    func makeOverviewDisplayPopUpButton(axis: OverviewDisplayAxis, menu: NSMenu) -> OverviewDisplayPopUpButton {
        let control = OverviewDisplayPopUpButton(frame: .zero, pullsDown: false)
        control.axis = axis
        control.trackedMenu = menu
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        control.removeAllItems()
        for choice in axis.choices {
            control.addItem(withTitle: choice)
        }
        let selectedIndex = axis == .usage
            ? (self.settings.usageBarsShowUsed ? 0 : 1)
            : (self.settings.resetTimesShowAbsolute ? 1 : 0)
        control.selectItem(at: selectedIndex)
        control.target = self
        control.action = #selector(self.overviewDisplayChoiceChanged(_:))
        control.setAccessibilityLabel(axis.label)
        control.sizeToFit()
        return control
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
