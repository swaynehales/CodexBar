import Foundation
import Testing
@testable import CodexBarCore

struct CompactTableClassificationTests {
    private func window(minutes: Int?, used: Double = 10) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: nil, resetDescription: nil)
    }

    private func named(
        id: String,
        minutes: Int?,
        qualifier: String? = nil,
        kind: TablePeriod? = nil) -> NamedRateWindow
    {
        NamedRateWindow(
            id: id,
            title: "Display Title",
            window: self.window(minutes: minutes),
            modelQualifier: qualifier,
            periodKind: kind)
    }

    @Test
    func `monthly sentinel maps to monthly regardless of title`() {
        #expect(CompactTablePeriodMapper.period(windowMinutes: 30 * 24 * 60) == .monthly)
        #expect(CompactTablePeriodMapper.period(windowMinutes: 43200) == .monthly)
        // Kimi "Total usage" and Amp monthlies carry non-monthly titles with sentinel minutes.
        let kimi = self.named(id: "kimi-monthly", minutes: 43200)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .kimi, window: kimi).period == .monthly)
    }

    @Test
    func `short and daily windows map to session`() {
        #expect(CompactTablePeriodMapper.period(windowMinutes: 300) == .session)
        #expect(CompactTablePeriodMapper.period(windowMinutes: 360) == .session)
        #expect(CompactTablePeriodMapper.period(windowMinutes: 1440) == .session)
    }

    @Test
    func `weekly minutes map to weekly and unknown durations map to other`() {
        #expect(CompactTablePeriodMapper.period(windowMinutes: 7 * 24 * 60) == .weekly)
        #expect(CompactTablePeriodMapper.period(windowMinutes: 20160) == .weekly)
        #expect(CompactTablePeriodMapper.period(windowMinutes: 2880) == .other)
        #expect(CompactTablePeriodMapper.period(windowMinutes: nil) == .other)
    }

    @Test
    func `kimi secondary lane is a session lane unlike other providers`() {
        let kimiSecondary = CompactTablePeriodMapper.laneClassification(provider: .kimi, slot: .secondary)
        #expect(kimiSecondary == CompactTableClassification(modelQualifier: nil, period: .session))
        #expect(CompactTablePeriodMapper.laneClassification(provider: .kimi, slot: .primary).period == .weekly)
        #expect(CompactTablePeriodMapper.laneClassification(provider: .codex, slot: .secondary).period == .weekly)
    }

    @Test
    func `tertiary meaning follows the provider`() {
        #expect(CompactTablePeriodMapper.laneClassification(provider: .claude, slot: .tertiary) ==
            CompactTableClassification(modelQualifier: "Sonnet", period: .weekly))
        #expect(CompactTablePeriodMapper.laneClassification(provider: .factory, slot: .tertiary).period == .monthly)
        #expect(CompactTablePeriodMapper.laneClassification(provider: .commandcode, slot: .tertiary).period == .monthly)
        #expect(CompactTablePeriodMapper.laneClassification(provider: .opencodego, slot: .tertiary).period == .monthly)
    }

    @Test
    func `claude scoped weekly derives model from id slug`() {
        let scoped = self.named(id: "claude-weekly-scoped-fable", minutes: 7 * 24 * 60)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .claude, window: scoped) ==
            CompactTableClassification(modelQualifier: "Fable", period: .weekly))
        let routines = self.named(id: "claude-routines", minutes: 7 * 24 * 60)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .claude, window: routines).period == .weekly)
    }

    @Test
    func `provider-shaped ids from other providers fall through to all`() {
        // A plugin (or any non-Claude provider) emitting a Claude-shaped id must not
        // invent a scoped model name.
        let spoof = self.named(id: "claude-weekly-scoped-megapack", minutes: 7 * 24 * 60)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .warp, window: spoof) ==
            CompactTableClassification(modelQualifier: nil, period: .weekly))
        let factorySpoof = self.named(id: "factory-core-7d", minutes: 7 * 24 * 60)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .warp, window: factorySpoof)
            .modelQualifier == nil)
    }

    @Test
    func `factory core ids map verbatim including nil-minute monthly`() {
        let fiveHour = self.named(id: "factory-core-5h", minutes: 300)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .factory, window: fiveHour) ==
            CompactTableClassification(modelQualifier: "Core", period: .session))
        let sevenDay = self.named(id: "factory-core-7d", minutes: 7 * 24 * 60)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .factory, window: sevenDay) ==
            CompactTableClassification(modelQualifier: "Core", period: .weekly))
        let monthly = self.named(id: "factory-core-monthly", minutes: nil)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .factory, window: monthly) ==
            CompactTableClassification(modelQualifier: "Core", period: .monthly))
    }

    @Test
    func `named provider extras map to their documented buckets`() {
        #expect(CompactTablePeriodMapper.extraClassification(
            provider: .codex,
            window: self.named(id: "codex-spark", minutes: 300)) ==
            CompactTableClassification(modelQualifier: "Spark", period: .session))
        #expect(CompactTablePeriodMapper.extraClassification(
            provider: .kimi,
            window: self.named(id: "kimi-code-7d", minutes: 7 * 24 * 60)) ==
            CompactTableClassification(modelQualifier: "Code", period: .weekly))
        #expect(CompactTablePeriodMapper.extraClassification(
            provider: .mistral,
            window: self.named(id: "mistral-monthly-plan", minutes: 30 * 24 * 60)).period == .monthly)
        #expect(CompactTablePeriodMapper.extraClassification(
            provider: .opencodego,
            window: self.named(id: "renewal", minutes: nil)).period == .credits)
    }

    @Test
    func `explicit fields win over id rules`() {
        let explicit = self.named(id: "claude-weekly-scoped-fable", minutes: 300, qualifier: "Custom", kind: .monthly)
        #expect(CompactTablePeriodMapper.extraClassification(provider: .claude, window: explicit) ==
            CompactTableClassification(modelQualifier: "Custom", period: .monthly))
    }

    @Test
    func `offline diagnostics and synthetic placeholders are hidden`() {
        #expect(CompactTablePeriodMapper.hidesExtraWindow(
            id: "antigravity-offline-conversations",
            isSyntheticPlaceholder: false) == true)
        #expect(CompactTablePeriodMapper.hidesExtraWindow(id: "anything", isSyntheticPlaceholder: true) == true)
        #expect(CompactTablePeriodMapper.hidesExtraWindow(id: "renewal", isSyntheticPlaceholder: false) == false)
        #expect(CompactTablePeriodMapper.hidesExtraWindow(
            id: "factory-core-7d",
            isSyntheticPlaceholder: false) == false)
    }

    @Test
    func `new fields decode missing as nil and stay out of encoded payloads`() throws {
        let legacyJSON = Data("""
        {"id":"x","title":"X","window":{"usedPercent":10.0}}
        """.utf8)
        let decoded = try JSONDecoder().decode(NamedRateWindow.self, from: legacyJSON)
        #expect(decoded.modelQualifier == nil)
        #expect(decoded.periodKind == nil)
        #expect(decoded.usageKnown == true)

        let encoded = try JSONEncoder().encode(decoded)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("modelQualifier"))
        #expect(!text.contains("periodKind"))

        let filled = NamedRateWindow(
            id: "y",
            title: "Y",
            window: self.window(minutes: 300),
            modelQualifier: "Core",
            periodKind: .session)
        let roundTripped = try JSONDecoder().decode(NamedRateWindow.self, from: JSONEncoder().encode(filled))
        #expect(roundTripped == filled)
    }
}
