import CodexBarCore
import Foundation

/// Compact Overview table row model (option B, spec rev 2 §5). Pure transform over the
/// existing menu-card model plus its snapshot — no AppKit, no menu state.
struct CompactTableRow: Identifiable {
    enum Presentation {
        case bar
        case value
    }

    let id: String
    let provider: UsageProvider
    let providerDisplayName: String
    var showProvider: Bool
    let model: String
    let period: TablePeriod
    let periodLabel: String
    let presentation: Presentation
    let percent: Double
    let valueText: String?
    let statusText: String?
    let usedText: String
    let resetsInText: String
    let resetsAt: Date?
    let tint: ProviderColor
    let metric: UsageMenuCardView.Model.Metric?
}

enum OverviewCompactTableModel {
    /// Builds one provider's table rows. Bar rows come from card metrics; value rows from
    /// status text, the balance parser, and reset-only renewal windows. Diagnostic windows
    /// (offline counts, synthetic placeholders) are dropped, never rendered as quota.
    static func rows(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        snapshot: UsageSnapshot?,
        now: Date = Date()) -> [CompactTableRow]
    {
        var rows: [CompactTableRow] = []
        let tint = ProviderAccentPalette.color(for: provider)
        for metric in model.metrics {
            if metric.id == "mistral-balance" {
                rows.append(Self.valueRow(
                    provider: provider,
                    model: model,
                    id: "\(provider.rawValue):mistral-balance",
                    modelText: "",
                    period: .credits,
                    valueText: metric.statusText,
                    metric: metric,
                    tint: tint,
                    now: now))
                continue
            }
            if metric.id == "renewal" {
                rows.append(Self.valueRow(
                    provider: provider,
                    model: model,
                    id: "\(provider.rawValue):renewal",
                    modelText: "",
                    period: .credits,
                    valueText: metric.resetText ?? metric.title,
                    metric: metric,
                    tint: tint,
                    now: now))
                continue
            }
            if metric.id == "antigravity-offline-conversations" {
                continue
            }
            if metric.id == "primary", snapshot?.primary?.isSyntheticPlaceholder == true {
                continue
            }
            if metric.statusText != nil {
                let classification = Self.classification(provider: provider, metricID: metric.id, snapshot: snapshot)
                rows.append(Self.valueRow(
                    provider: provider,
                    model: model,
                    id: "\(provider.rawValue):\(metric.id)",
                    modelText: classification.modelQualifier ?? "",
                    period: classification.period,
                    valueText: metric.statusText,
                    metric: metric,
                    tint: tint,
                    now: now))
                continue
            }
            let classification = Self.classification(provider: provider, metricID: metric.id, snapshot: snapshot)
            rows.append(CompactTableRow(
                id: "\(provider.rawValue):\(metric.id)",
                provider: provider,
                providerDisplayName: model.providerName,
                showProvider: false,
                model: classification.modelQualifier ?? "All",
                period: classification.period,
                periodLabel: Self.periodLabel(classification.period),
                presentation: .bar,
                percent: metric.percent,
                valueText: nil,
                statusText: nil,
                usedText: UsageFormatter.percentString(metric.percent),
                resetsInText: Self.resetsInText(resetsAt: metric.resetsAt, now: now),
                resetsAt: metric.resetsAt,
                tint: tint,
                metric: metric))
        }
        if let loginMethod = snapshot?.loginMethod(for: provider),
           let balance = CompactTableBalanceParser.balanceValue(loginMethod: loginMethod, provider: provider)
        {
            rows.append(CompactTableRow(
                id: "\(provider.rawValue):balance",
                provider: provider,
                providerDisplayName: model.providerName,
                showProvider: false,
                model: "",
                period: .credits,
                periodLabel: Self.periodLabel(.credits),
                presentation: .value,
                percent: 0,
                valueText: model.planText ?? balance,
                statusText: nil,
                usedText: "",
                resetsInText: "—",
                resetsAt: nil,
                tint: tint,
                metric: nil))
        }
        if let first = rows.indices.first {
            rows[first].showProvider = true
        }
        return rows
    }

    private static func classification(
        provider: UsageProvider,
        metricID: String,
        snapshot: UsageSnapshot?) -> CompactTableClassification
    {
        switch metricID {
        case "primary":
            return CompactTablePeriodMapper.laneClassification(provider: provider, slot: .primary)
        case "secondary":
            return CompactTablePeriodMapper.laneClassification(provider: provider, slot: .secondary)
        case "tertiary":
            return CompactTablePeriodMapper.laneClassification(provider: provider, slot: .tertiary)
        case "monthly":
            return CompactTablePeriodMapper.laneClassification(provider: provider, slot: .monthly)
        case "code-review":
            return CompactTableClassification(modelQualifier: nil, period: .weekly)
        default:
            guard let window = snapshot?.extraRateWindows?.first(where: { $0.id == metricID }) else {
                return CompactTableClassification(modelQualifier: nil, period: .other)
            }
            return CompactTablePeriodMapper.extraClassification(provider: provider, window: window)
        }
    }

    private static func valueRow(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        id: String,
        modelText: String,
        period: TablePeriod,
        valueText: String?,
        metric: UsageMenuCardView.Model.Metric?,
        tint: ProviderColor,
        now: Date) -> CompactTableRow
    {
        CompactTableRow(
            id: id,
            provider: provider,
            providerDisplayName: model.providerName,
            showProvider: false,
            model: modelText,
            period: period,
            periodLabel: self.periodLabel(period),
            presentation: .value,
            percent: 0,
            valueText: valueText,
            statusText: metric?.statusText,
            usedText: "",
            resetsInText: self.resetsInText(resetsAt: metric?.resetsAt, now: now),
            resetsAt: metric?.resetsAt,
            tint: tint,
            metric: metric)
    }

    private static func resetsInText(resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "—" }
        let countdown = UsageFormatter.resetCountdownDescription(from: resetsAt, now: now)
        if countdown.hasPrefix("in ") {
            return String(countdown.dropFirst(3))
        }
        return countdown
    }

    private static func periodLabel(_ period: TablePeriod) -> String {
        switch period {
        case .session: L("compact_period_session")
        case .weekly: L("compact_period_weekly")
        case .monthly: L("compact_period_monthly")
        case .credits: L("compact_period_credits")
        case .other: L("compact_period_other")
        }
    }
}
