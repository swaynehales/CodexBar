import Foundation

/// Period buckets for the compact Overview table (option B, design spec rev 2).
///
/// Lives in Core so both the app menu and the CLI/tests share one mapping. Cases mirror the
/// mock's periods plus `.other` for daily/misc windows that fit no bucket and `.credits` for
/// balance/renewal value rows.
public enum TablePeriod: String, Codable, Sendable {
    case session
    case weekly
    case monthly
    case credits
    case other
}

/// Lane slots understood by the lane map. `primary`/`secondary`/`tertiary` are the
/// `UsageSnapshot` lanes; `monthly` covers Codex-style projections that surface a monthly lane
/// outside `tertiary`. Menu-card-only ids (`code-review`, `mistral-balance`) are classified in
/// the app-layer transform, not here — they never reach Core as lanes.
public enum CompactTableLaneSlot: Sendable {
    case primary
    case secondary
    case tertiary
    case monthly
}

/// MODEL/PERIOD classification for one table row. `modelQualifier == nil` renders as "All".
/// The fallback chain never invents a scoped model name.
public struct CompactTableClassification: Equatable, Sendable {
    public let modelQualifier: String?
    public let period: TablePeriod

    public init(modelQualifier: String?, period: TablePeriod) {
        self.modelQualifier = modelQualifier
        self.period = period
    }
}

public enum CompactTablePeriodMapper {
    /// Sentinel-first `windowMinutes` mapping. The monthly sentinel is tested BEFORE the
    /// weekly threshold: several providers report monthlies as
    /// `ProviderPaceCapability.monthlyWindowSentinelMinutes` (43200) under non-monthly
    /// titles (Kimi "Total usage", Amp "Other usage"/"Orb usage"), so a `>= 10080 ⇒ weekly`
    /// rule alone mislabels them. Unrecognized durations fall to `.other` rather than a
    /// guessed bucket; `nil` is `.other` (the caller supplies lane context when known).
    public static func period(windowMinutes: Int?) -> TablePeriod {
        guard let windowMinutes else { return .other }
        if windowMinutes == ProviderPaceCapability.monthlyWindowSentinelMinutes {
            return .monthly
        }
        if windowMinutes <= 360 {
            return .session
        }
        if windowMinutes == 1440 {
            return .session
        }
        if windowMinutes == 7 * 24 * 60 {
            return .weekly
        }
        if windowMinutes >= 7 * 24 * 60 {
            return .weekly
        }
        return .other
    }

    /// Lane-slot map keyed by (provider, slot). Tertiary meaning is provider-specific —
    /// there is no safe global default — so every provider with a real tertiary lane is
    /// enumerated. Providers absent here have no tertiary lane in practice (nil ⇒ no row).
    public static func laneClassification(
        provider: UsageProvider,
        slot: CompactTableLaneSlot) -> CompactTableClassification
    {
        // Provider-specific by design: quota-lane semantics (session vs weekly vs monthly
        // slots, scoped model weeklies) differ per provider API and cannot be derived globally.
        switch (provider, slot) {
        case (.kimi, .primary):
            // Kimi's primary lane is its weekly coding window; the 5-hour rate
            // limit lives in secondary (see the case below).
            CompactTableClassification(modelQualifier: nil, period: .weekly)
        case (.kimi, .secondary):
            // Kimi's secondary slot is its 5-hour rate limit, unlike every other
            // provider's weekly secondary. Must stay pinned here, not inferred later.
            CompactTableClassification(modelQualifier: nil, period: .session)
        case (.claude, .tertiary):
            // Displayed label is always "Sonnet" even for Opus-sourced data.
            CompactTableClassification(modelQualifier: "Sonnet", period: .weekly)
        case (.factory, .tertiary):
            CompactTableClassification(modelQualifier: nil, period: .monthly)
        case (.commandcode, .tertiary):
            CompactTableClassification(modelQualifier: nil, period: .monthly)
        case (.opencodego, .tertiary):
            CompactTableClassification(modelQualifier: nil, period: .monthly)
        case (_, .primary):
            CompactTableClassification(modelQualifier: nil, period: .session)
        case (_, .secondary):
            CompactTableClassification(modelQualifier: nil, period: .weekly)
        case (_, .tertiary):
            CompactTableClassification(modelQualifier: nil, period: .weekly)
        case (_, .monthly):
            CompactTableClassification(modelQualifier: nil, period: .monthly)
        }
    }

    /// Extra-window classification: explicit fields win, then provider-gated id rules, then
    /// the `windowMinutes` mapping. Each id rule requires the provider AND the id — prefixes
    /// are never matched cross-provider, so a plugin window shaped like
    /// `claude-weekly-scoped-*` falls through to MODEL=All. MODEL is derived from the id
    /// slug or the explicit field, never from the (localized) title.
    public static func extraClassification(
        provider: UsageProvider,
        window: NamedRateWindow) -> CompactTableClassification
    {
        if let periodKind = window.periodKind {
            return CompactTableClassification(modelQualifier: window.modelQualifier, period: periodKind)
        }
        // Provider-specific by design: extra-window ids are provider-owned wire contracts
        // (scoped weeklies, core pools, spark lanes); each rule is gated on provider AND id.
        if provider == .claude, window.id.hasPrefix("claude-weekly-scoped-") {
            let slug = String(window.id.dropFirst("claude-weekly-scoped-".count))
            let qualifier = slug
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return CompactTableClassification(
                modelQualifier: qualifier.isEmpty ? nil : qualifier,
                period: .weekly)
        }
        if provider == .claude, window.id == "claude-routines" {
            return CompactTableClassification(modelQualifier: nil, period: .weekly)
        }
        if provider == .factory {
            switch window.id {
            case "factory-core-5h":
                return CompactTableClassification(modelQualifier: "Core", period: .session)
            case "factory-core-7d":
                return CompactTableClassification(modelQualifier: "Core", period: .weekly)
            case "factory-core-monthly":
                return CompactTableClassification(modelQualifier: "Core", period: .monthly)
            default:
                break
            }
        }
        if provider == .codex, window.id == CodexAdditionalRateLimitMapper.sparkWindowID {
            return CompactTableClassification(
                modelQualifier: "Spark",
                period: self.period(windowMinutes: window.window.windowMinutes))
        }
        if provider == .codex, window.id == CodexAdditionalRateLimitMapper.sparkWeeklyWindowID {
            return CompactTableClassification(
                modelQualifier: "Spark",
                period: self.period(windowMinutes: window.window.windowMinutes))
        }
        if provider == .kimi, window.id == "kimi-monthly" {
            return CompactTableClassification(modelQualifier: nil, period: .monthly)
        }
        if provider == .kimi, window.id == "kimi-code-7d" {
            return CompactTableClassification(modelQualifier: "Code", period: .weekly)
        }
        // Provider-specific by design: balance/credit-pool extras carry provider-owned
        // ids with no shared Core representation.
        if provider == .amp, window.id == "amp-free" {
            return CompactTableClassification(
                modelQualifier: "Free",
                period: self.period(windowMinutes: window.window.windowMinutes))
        }
        if provider == .mistral, window.id == "mistral-monthly-plan" {
            return CompactTableClassification(modelQualifier: nil, period: .monthly)
        }
        if window.id == "renewal" {
            // Reset-only renewal windows render as value-style rows in the renewal bucket.
            return CompactTableClassification(modelQualifier: window.modelQualifier, period: .credits)
        }
        return CompactTableClassification(
            modelQualifier: window.modelQualifier,
            period: self.period(windowMinutes: window.window.windowMinutes))
    }

    /// Windows the table must not render as quota rows. Id-based (not blanket): a blanket
    /// `usageKnown == false` drop would delete legitimate reset-only pools, and the
    /// placeholder flag is provider-agnostic.
    public static func hidesExtraWindow(id: String, isSyntheticPlaceholder: Bool) -> Bool {
        if isSyntheticPlaceholder {
            return true
        }
        // Diagnostic offline-conversation count, not quota
        // (AntigravityProviderDescriptor offline window).
        if id == "antigravity-offline-conversations" {
            return true
        }
        return false
    }
}
