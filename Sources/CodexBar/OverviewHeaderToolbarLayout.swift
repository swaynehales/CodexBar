import Foundation

/// Pure geometry for the Overview header toolbar second row: the Used/Remains pair fills
/// the entire left half and the Countdown/Clock pair fills the entire right half, with the
/// same outer edges and midpoint and equal segments within each pair. No captions.
///
/// Kept free of AppKit so the offscreen preview harness compiles this file directly
/// alongside its renderer; production and preview share these numbers by construction.
enum OverviewHeaderToolbarLayout {
    static let sidePadding: CGFloat = 12
    static let pairGap: CGFloat = 0
    static let topInset: CGFloat = 6
    static let bottomInset: CGFloat = 6

    struct RowFrames {
        /// Usage pair frame, relative to the row origin.
        let usage: CGRect
        /// Reset pair frame, relative to the row origin.
        let reset: CGRect
        /// Fixed width applied to every segment of both pairs.
        let segmentWidth: CGFloat
        /// Full row height including insets (status block, if any, stacks below).
        let rowHeight: CGFloat
    }

    static func frames(width: CGFloat, controlHeight: CGFloat) -> RowFrames {
        let left = Self.sidePadding
        let right = max(left, width - Self.sidePadding)
        // Midpoint of the outer edges; halves are equal by construction.
        let mid = (left + right) / 2
        let usageWidth = max(0, mid - left - Self.pairGap / 2)
        let resetWidth = max(0, right - mid - Self.pairGap / 2)
        // One divider between the two segments of a pair; both halves share it.
        let segmentWidth = max(0, (min(usageWidth, resetWidth) - 1) / 2)
        let rowHeight = Self.topInset + controlHeight + Self.bottomInset
        return RowFrames(
            usage: CGRect(x: left, y: Self.bottomInset, width: usageWidth, height: controlHeight),
            reset: CGRect(x: right - resetWidth, y: Self.bottomInset, width: resetWidth, height: controlHeight),
            segmentWidth: segmentWidth,
            rowHeight: rowHeight)
    }
}
