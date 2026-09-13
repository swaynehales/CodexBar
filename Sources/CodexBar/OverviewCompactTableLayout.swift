import Foundation

struct OverviewCompactTableLayout: Equatable {
    let width: CGFloat
    let resetWidth: CGFloat
    let wrapClock: Bool
    let stacksControls: Bool

    static func resolve(
        availableWidth: CGFloat,
        clockWidth: CGFloat,
        clockLineWidth: CGFloat,
        controlWidths: [CGFloat]) -> Self
    {
        let desiredReset = max(130, ceil(clockWidth) + 8)
        let width = min(338 + desiredReset, max(0, availableWidth))
        let constrained = width < 338 + desiredReset
        // Reserve enough space for the existing leading/percentage columns and gaps.
        let resetBudget = max(0, width - 190)
        let resetWidth = min(
            resetBudget,
            constrained ? max(42, ceil(clockLineWidth) + 8) : desiredReset)
        let controlSpace = max(0, width - 24)
        let required = controlWidths.reduce(0, +) + CGFloat(max(0, controlWidths.count - 1)) * 12
        return Self(
            width: width,
            resetWidth: resetWidth,
            wrapClock: constrained,
            stacksControls: required > controlSpace)
    }

    func barWidth(leading: CGFloat) -> CGFloat {
        max(0, self.width - 36 - leading - 42 - self.resetWidth)
    }
}
