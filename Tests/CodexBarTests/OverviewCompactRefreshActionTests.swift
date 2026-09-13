import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
private final class CompactRefreshGate {
    var continuation: CheckedContinuation<Void, Never>?
    var isOpen = false
    func wait() async {
        if self.isOpen {
            return
        }
        await withCheckedContinuation { self.continuation = $0 }
    }

    func resume() {
        self.isOpen = true
        self.continuation?.resume()
        self.continuation = nil
    }
}

@MainActor
@Suite(.serialized)
struct OverviewCompactRefreshActionTests {
    @Test
    func `global manual refresh records completion while provider refresh leaves it unchanged`() async throws {
        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        let controller = self.makeController(settings: settings)
        defer { controller.prepareForAppShutdown() }
        let gate = CompactRefreshGate()
        controller._test_manualRefreshOperation = { await gate.wait() }
        #expect(controller.compactGlobalRefreshStatus == nil)
        controller.refreshNow()
        let task = try #require(controller.manualRefreshTasks[.global])
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(controller.compactGlobalRefreshStatus == nil)
        gate.resume()
        await task.value
        let record = try #require(controller.compactGlobalRefreshStatus)
        #expect(record.hadFailures) // Enabled providers have no snapshots in this isolated store.
        controller._test_manualRefreshOperation = {}
        let menu = controller.makeMenu(for: .codex)
        controller.refreshMenuProviderNow(in: menu)
        let providerTask = try #require(controller.manualRefreshTasks[.provider(.codex)])
        await providerTask.value
        #expect(controller.compactGlobalRefreshStatus == record)
        controller.refreshNow()
        let canceled = try #require(controller.manualRefreshTasks[.global])
        canceled.cancel()
        await canceled.value
        #expect(controller.compactGlobalRefreshStatus == record)
    }

    @Test
    func `refresh status distinguishes retained data from a successful unavailable quota response`() throws {
        let controller = self.makeController(settings: self.makeSettings())
        defer { controller.prepareForAppShutdown() }
        let store = controller.store
        let provider = UsageProvider.claude.instanceID
        store.snapshots[provider] = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let cached = store.snapshots[provider]
        store.errors[provider] = nil
        store.lastFetchAttempts[provider] = [ProviderFetchAttempt(
            strategyID: "test.oauth", kind: .oauth, wasAvailable: true, errorDescription: "Rate limited")]
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [provider])
        #expect(try #require(controller.compactGlobalRefreshStatus).hadFailures)

        store.snapshots[provider] = nil
        store.knownLimitsAvailabilityByProvider[provider] = .unavailable
        store.lastFetchAttempts[provider] = [ProviderFetchAttempt(
            strategyID: "test.cli",
            kind: .cli,
            wasAvailable: true,
            errorDescription: ClaudeStatusProbe.subscriptionQuotaUnavailableDescription)]
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [provider])
        #expect(try !#require(controller.compactGlobalRefreshStatus).hadFailures)

        // A later timeout can retain the unavailable state; it is still a failed refresh.
        store.lastFetchAttempts[provider] = [ProviderFetchAttempt(
            strategyID: "test.cli", kind: .cli, wasAvailable: true, errorDescription: "Timed out")]
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [provider])
        #expect(try #require(controller.compactGlobalRefreshStatus).hadFailures)

        store.knownLimitsAvailabilityByProvider[provider] = nil
        store.snapshots[provider] = cached
        store.lastFetchAttempts[provider]?.append(ProviderFetchAttempt(
            strategyID: "test.fallback", kind: .web, wasAvailable: true, errorDescription: nil))
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [provider])
        #expect(try !#require(controller.compactGlobalRefreshStatus).hadFailures)

        store.lastFetchAttempts[provider] = [ProviderFetchAttempt(
            strategyID: "test.unavailable", kind: .cli, wasAvailable: false, errorDescription: nil)]
        controller.recordCompactGlobalRefreshCompletion(scope: .global, completed: true, providers: [provider])
        #expect(try #require(controller.compactGlobalRefreshStatus).hadFailures)
    }

    private func makeSettings() -> SettingsStore {
        testSettingsStore(suiteName: "OverviewCompactRefreshActionTests")
    }

    private func makeController(settings: SettingsStore) -> StatusItemController {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent(".codex").path]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        return StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
    }
}
