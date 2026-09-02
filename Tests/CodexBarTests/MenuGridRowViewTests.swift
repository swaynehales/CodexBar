import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuGridRowViewTests {
    private static func makePayload(id: String, onClick: (() -> Void)? = nil) -> MenuCardRowPayload {
        MenuCardRowPayload(
            content: AnyView(Text("card-\(id)").font(.headline)),
            showsSubmenuIndicator: false,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 0,
            allowsMenuHighlight: false,
            containsInteractiveControls: false,
            usesGPUSelection: false,
            onClick: onClick)
    }

    @Test
    func `grid row reports card row height at full width`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        #expect(height > 8)
        row.applyMeasuredSize(width: width, height: height)
        #expect(abs(row.frame.height - height) < 1)
    }

    @Test
    func `grid row lays out three cards horizontally`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        row.applyMeasuredSize(width: width, height: height)

        #expect(row.cardViewsForTesting.count == 3)
        let expectedCardWidth = (width - 2 * 8) / 3
        for card in row.cardViewsForTesting {
            #expect(abs(card.frame.width - expectedCardWidth) < 1)
        }
        #expect(abs(row.cardViewsForTesting[0].frame.minX - (width - row.cardViewsForTesting[2].frame.maxX)) < 1)
        #expect(abs(row.cardViewsForTesting[0].frame.minY - row.cardViewsForTesting[1].frame.minY) < 0.5)
    }

    @Test
    func `grid row two cards stay centered`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b")],
            gap: 8,
            refreshMonitor: nil)
        let width: CGFloat = 950
        let height = row.measuredHeight(width: width)
        row.applyMeasuredSize(width: width, height: height)

        // Fixed 3-column slot: a 2-card row renders cards at the same width as a full row.
        let expectedCardWidth = (width - 2 * 8) / 3
        for card in row.cardViewsForTesting {
            #expect(abs(card.frame.width - expectedCardWidth) < 1)
        }
        let leading = row.cardViewsForTesting[0].frame.minX
        #expect(abs(leading - (width - row.cardViewsForTesting[1].frame.maxX)) < 1)
        // Centered group: leading equals the leftover half-margin, not a column origin.
        let centeredLeading = (width - 2 * expectedCardWidth - 8) / 2
        #expect(abs(leading - centeredLeading) < 1)
    }

    @Test
    func `grid row forwards highlight to every card`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)

        row.setHighlighted(true)
        for card in row.cardViewsForTesting {
            #expect(card._test_isHighlighted)
        }
        row.setHighlighted(false)
        for card in row.cardViewsForTesting {
            #expect(!card._test_isHighlighted)
        }
        #expect(row.allowsMenuHighlight)
    }

    @Test
    func `grid row replants payloads without detaching cards`() {
        let row = MenuGridRowView(
            cards: [Self.makePayload(id: "a"), Self.makePayload(id: "b"), Self.makePayload(id: "c")],
            gap: 8,
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)
        let original = row.cardViewsForTesting.map(ObjectIdentifier.init)

        row.replant(
            cards: [Self.makePayload(id: "d"), Self.makePayload(id: "e"), Self.makePayload(id: "f")],
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)

        #expect(row.cardViewsForTesting.map(ObjectIdentifier.init) == original)
    }

    @Test
    func `grid row preserves per-card click targets`() {
        var clicked = 0
        let row = MenuGridRowView(
            cards: [
                Self.makePayload(id: "a", onClick: { clicked += 1 }),
                Self.makePayload(id: "b", onClick: nil),
            ],
            gap: 8,
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 950, height: 120)

        #expect(row.cardViewsForTesting[0]._test_onClick != nil)
        #expect(row.cardViewsForTesting[1]._test_onClick == nil)
        row.cardViewsForTesting[0]._test_onClick?()
        #expect(clicked == 1)
    }
}
