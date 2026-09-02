import AppKit
import CodexBarCore
import SwiftUI

/// A single Overview grid menu item: an AppKit container that lays out one to three
/// card containers horizontally. Cards keep their own `MenuRowContainerView` click,
/// highlight, and accessibility behavior; the row itself only positions them.
final class MenuGridRowView: NSView, MenuCardMeasuring, MenuCardHighlighting {
    static let gap: CGFloat = 8
    static let columns = 3

    private var cardViews: [MenuRowContainerView] = []
    private var gap: CGFloat = MenuGridRowView.gap
    private var columns: Int = MenuGridRowView.columns
    private var refreshMonitor: MenuCardRefreshMonitor?
    private var measuredSize: NSSize?

    init(
        cards: [MenuCardRowPayload],
        gap: CGFloat = MenuGridRowView.gap,
        columns: Int = MenuGridRowView.columns,
        refreshMonitor: MenuCardRefreshMonitor?)
    {
        self.refreshMonitor = refreshMonitor
        self.gap = gap
        self.columns = max(1, columns)
        super.init(frame: .zero)
        self.wantsLayer = true
        self.rebuild(cards: cards)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Card containers exposed for tests.
    var cardViewsForTesting: [MenuRowContainerView] {
        self.cardViews
    }

    override var allowsVibrancy: Bool {
        true
    }

    // MARK: MenuCardHighlighting

    /// The menu item is tracked as one row; highlight all cards together.
    func setHighlighted(_ highlighted: Bool) {
        for card in self.cardViews {
            card.setHighlighted(highlighted)
        }
    }

    // MARK: Sizing

    func measuredHeight(width: CGFloat) -> CGFloat {
        let cardWidth = Self.cardWidth(totalWidth: width, columns: self.columns, gap: self.gap)
        var maxHeight: CGFloat = 0
        for card in self.cardViews {
            maxHeight = max(maxHeight, card.measuredHeight(width: cardWidth))
        }
        return ceil(maxHeight)
    }

    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: max(1, ceil(height)))
        self.setFrameSize(size)
        self.measuredSize = size
        self.invalidateIntrinsicContentSize()
        self.needsLayout = true
        self.layoutCards()
    }

    func replant(cards: [MenuCardRowPayload], refreshMonitor: MenuCardRefreshMonitor?) {
        self.refreshMonitor = refreshMonitor
        if cards.count != self.cardViews.count {
            self.rebuild(cards: cards)
            return
        }
        for (index, payload) in cards.enumerated() {
            self.cardViews[index].replant(payload, refreshMonitor: refreshMonitor)
        }
    }

    override func layout() {
        super.layout()
        self.layoutCards()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != self.frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            self.needsLayout = true
        }
    }

    /// Every card keeps the fixed column slot width so leftover rows (1-2 cards)
    /// render at the same card size as a full row, centered horizontally.
    static func cardWidth(totalWidth: CGFloat, columns: Int, gap: CGFloat) -> CGFloat {
        let columnCount = max(1, columns)
        let usable = totalWidth - CGFloat(columnCount - 1) * gap
        return usable / CGFloat(columnCount)
    }

    private func rebuild(cards: [MenuCardRowPayload]) {
        self.cardViews.forEach { $0.removeFromSuperview() }
        self.cardViews = cards.map { payload in
            MenuRowContainerView(payload: payload, refreshMonitor: self.refreshMonitor)
        }
        self.cardViews.forEach { self.addSubview($0) }
        self.needsLayout = true
    }

    private func layoutCards() {
        guard !self.cardViews.isEmpty, self.bounds.width > 0, self.bounds.height > 0 else { return }
        let width = self.bounds.width
        let height = self.bounds.height
        let cardWidth = Self.cardWidth(totalWidth: width, columns: self.columns, gap: self.gap)
        let totalUsed = CGFloat(self.cardViews.count) * cardWidth + CGFloat(self.cardViews.count - 1) * self.gap
        let leadingInset = max(0, (width - totalUsed) / 2)
        for (index, card) in self.cardViews.enumerated() {
            let x = leadingInset + CGFloat(index) * (cardWidth + self.gap)
            // AppKit's default coordinate system is bottom-left origin; cards stretch the
            // full row height so their SwiftUI content aligns to the shared top edge.
            card.frame = NSRect(x: x, y: 0, width: cardWidth, height: height)
            card.autoresizingMask = [.width, .height]
        }
    }
}

// MARK: - Overview grid menu construction

extension StatusItemController {
    /// Grid mode: lay the Overview cards out in rows of `overviewGridColumns` cards each.
    /// Cards keep today's per-card layout; the menu is widened to `menuCardBaseWidth * columns`
    /// (see `menuCardWidth`). No per-card submenus in grid mode — detail charts stay available
    /// from each provider's own tab.
    func addOverviewGrid(
        rows: [(provider: UsageProvider, model: UsageMenuCardView.Model)],
        to menu: NSMenu,
        menuWidth: CGFloat,
        captureMenu: NSMenu?) -> Bool
    {
        let interactionMenu = captureMenu ?? menu
        var index = 0
        while index < rows.count {
            let batch = Array(rows[index..<min(index + Self.overviewGridColumns, rows.count)])
            var payloads: [MenuCardRowPayload] = []
            payloads.reserveCapacity(batch.count)
            for row in batch {
                let storageText = self.store.storageFootprintText(for: row.provider)
                let card = OverviewMenuCardRowView(
                    model: row.model,
                    storageText: storageText,
                    width: Self.gridCardWidth(menuWidth: menuWidth))
                payloads.append(MenuCardRowPayload(
                    content: AnyView(card),
                    showsSubmenuIndicator: false,
                    submenuIndicatorAlignment: .topTrailing,
                    submenuIndicatorTopPadding: 8,
                    // Mirrors makeMenuCardItem: onClick != nil → the card container participates
                    // in highlight tracking (forwarded from MenuGridRowView.setHighlighted).
                    allowsMenuHighlight: true,
                    containsInteractiveControls: row.model.subtitleStyle == .error || row.model.usesLiveSubtitle,
                    usesGPUSelection: true,
                    onClick: { [weak self, weak interactionMenu] in
                        guard let self, let interactionMenu else { return }
                        self.selectOverviewProvider(row.provider, menu: interactionMenu)
                    }))
            }
            let hosting = MenuGridRowView(cards: payloads, refreshMonitor: self.menuCardRefreshMonitor)
            let height = self.cachedMenuCardHeight(
                for: Self.overviewGridRowIdentifier,
                scope: "overviewGridRow-\(batch.count)",
                width: menuWidth,
                fingerprint: batch
                    .map { $0.model.heightFingerprint(section: "overviewGrid") }
                    .joined(separator: "|"))
            {
                self.menuCardHeight(for: hosting, width: menuWidth)
            }
            hosting.applyMeasuredSize(width: menuWidth, height: height)

            let item = MenuCardMenuItem()
            item.title = ""
            item.view = hosting
            item.isEnabled = true
            item.representedObject = Self.overviewGridRowIdentifier
            // No per-item submenu in grid mode. The action stays wired for keyboard
            // activation; selectOverviewProvider(_:) ignores non-overviewRow items.
            item.target = self
            item.action = #selector(self.selectOverviewProvider(_:))
            menu.addItem(item)
            index += Self.overviewGridColumns
        }
        return true
    }

    /// Every grid card occupies a fixed 3-column slot regardless of how many cards its row
    /// holds, matching `MenuGridRowView.layoutCards` exactly (partial rows stay centered).
    static func gridCardWidth(menuWidth: CGFloat) -> CGFloat {
        MenuGridRowView.cardWidth(
            totalWidth: menuWidth,
            columns: overviewGridColumns,
            gap: MenuGridRowView.gap)
    }
}
