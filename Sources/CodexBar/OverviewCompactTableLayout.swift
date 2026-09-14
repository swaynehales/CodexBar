import Foundation

struct OverviewCompactTableLayout: Equatable {
    let width: CGFloat
    let percentageWidth: CGFloat
    let resetWidth: CGFloat
    let wrapClock: Bool

    static func resolve(
        availableWidth: CGFloat,
        percentageWidth: CGFloat = 42,
        clockWidth: CGFloat,
        clockLineWidth: CGFloat) -> Self
    {
        let desiredReset = ceil(clockWidth) + 8
        let baseWidth: CGFloat = 296 // 2 * 12 padding + 3 * 4 gaps + 260 (leading + bar)
        let desiredTotal = baseWidth + percentageWidth + desiredReset
        let width = min(desiredTotal, max(0, availableWidth))
        let constrained = width < desiredTotal
        // Reserve enough space for the leading/percentage columns and gaps.
        let resetBudget = max(0, width - 148 - percentageWidth)
        let resetWidth = min(
            resetBudget,
            constrained ? max(42, ceil(clockLineWidth) + 8) : desiredReset)
        return Self(
            width: width,
            percentageWidth: percentageWidth,
            resetWidth: resetWidth,
            wrapClock: constrained)
    }

    func barWidth(leading: CGFloat) -> CGFloat {
        max(0, self.width - 36 - leading - self.percentageWidth - self.resetWidth)
    }
}
