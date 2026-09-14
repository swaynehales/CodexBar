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
}

struct OverviewDisplayState {
    var layouts: [ObjectIdentifier: OverviewCompactTableLayout] = [:]
    var viewportRequests: [ObjectIdentifier: OverviewDisplayViewportRequest] = [:]
}

/// Live AppKit usage control for the By-provider header interaction experiment.
/// A borderless pullsDown NSPopUpButton on the NSControl target/action path — the same
/// control class as the proven grouping switcher. The SwiftUI Menu equivalent rendered
/// but never received clicks inside the open menu, with no callback failure behind it.
/// Scope is one header cell only; reset and By-period controls keep their current views.
final class OverviewUsagePopUpButton: NSPopUpButton {}

/// Maps popup indexes to usage segments. Index 0 is the pullsDown title slot and
/// re-affirms the current segment (a no-op through the existing settings guard);
/// indexes 1... map to segments 0....
final class OverviewUsagePopUpCoordinator: NSObject {
    var selectedSegment = 0
    var onSelect: ((Int) -> Void)?

    @objc func chose(_ sender: OverviewUsagePopUpButton) {
        let index = sender.indexOfSelectedItem
        self.onSelect?(index <= 0 ? self.selectedSegment : index - 1)
    }
}

/// SwiftUI host for the experiment control. Menu identity and preference behavior stay
/// in the existing onSelect closure (which captures the tracked menu weakly); this view
/// only owns the AppKit control and the index mapping.
struct OverviewUsagePopUpHeader: NSViewRepresentable {
    let showUsed: Bool
    let width: CGFloat
    var onSelect: ((Int) -> Void)?

    func makeCoordinator() -> OverviewUsagePopUpCoordinator {
        OverviewUsagePopUpCoordinator()
    }

    func makeNSView(context: Context) -> OverviewUsagePopUpButton {
        let button = StatusItemController.makeUsagePopUpButton(showUsed: self.showUsed)
        button.target = context.coordinator
        button.action = #selector(OverviewUsagePopUpCoordinator.chose(_:))
        context.coordinator.selectedSegment = self.showUsed ? 0 : 1
        context.coordinator.onSelect = self.onSelect
        return button
    }

    func updateNSView(_ button: OverviewUsagePopUpButton, context: Context) {
        StatusItemController.retitleUsagePopUpButton(button, showUsed: self.showUsed)
        context.coordinator.selectedSegment = self.showUsed ? 0 : 1
        context.coordinator.onSelect = self.onSelect
    }
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
    static func dropdownHeaderWidth(for axis: OverviewDisplayAxis) -> CGFloat {
        axis.choices.indices.map { idx in
            let view = OverviewCompactDropdownHeader(
                axis: axis,
                selectedIndex: idx,
                width: 0,
                isHighlighted: false)
            return ceil(NSHostingView(rootView: view).fittingSize.width)
        }.max() ?? 0
    }

    /// Builds the experiment popup without a target so both the SwiftUI host and the
    /// focused tests can bind dispatch themselves. Item 0 is the pullsDown title slot;
    /// items 1... carry the full descriptive names with the current selection checked.
    static func makeUsagePopUpButton(showUsed: Bool) -> OverviewUsagePopUpButton {
        let button = OverviewUsagePopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        button.alignment = .right
        button.removeAllItems()
        button.addItem(withTitle: "")
        button.addItems(withTitles: OverviewDisplayAxis.usage.choices)
        Self.retitleUsagePopUpButton(button, showUsed: showUsed)
        button.setAccessibilityLabel(OverviewDisplayAxis.usage.label)
        return button
    }

    static func retitleUsagePopUpButton(_ button: OverviewUsagePopUpButton, showUsed: Bool) {
        // EXPERIMENT (interaction proof only): the title slot shows the short proposal
        // copy while the menu keeps the full descriptive names. "Left" is an unapproved
        // proposal with no localization key; it intentionally stays a literal until copy
        // is approved, then gains a key in every complete locale. Do not copy this pattern.
        button.item(at: 0)?.title = showUsed ? L("compact_header_used") : "Left"
        button.selectItem(at: showUsed ? 1 : 2)
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
