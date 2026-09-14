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
        clockLineWidth: CGFloat = 0) -> Self
    {
        let desiredReset = ceil(clockWidth) + 8
        let baseWidth: CGFloat = 290 // 2 * 12 padding + 3 * 4 gaps + 254 (84 leading + 170 bar)
        let desiredTotal = baseWidth + percentageWidth + desiredReset
        let width = min(desiredTotal, max(0, availableWidth))
        let constrained = width < desiredTotal
        // Reserve the shared 84pt leading column plus padding and gaps. The 42pt floor
        // keeps short content usable on constrained screens; it is not header-derived.
        let resetBudget = max(0, width - 120 - percentageWidth)
        let minResetWidth: CGFloat = 42
        let resetWidth = min(
            resetBudget,
            constrained ? max(minResetWidth, ceil(clockLineWidth) + 8) : desiredReset)
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
