import Testing
@testable import CodexBarCore

struct CompactTableBalanceParserTests {
    @Test
    func `balance providers parse the fragment value`() {
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "balance: $4.96", provider: .openrouter) == "$4.96")
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "Balance: $2.15", provider: .mimo) == "$2.15")
        #expect(CompactTableBalanceParser.balanceValue(
            loginMethod: "  balance:   100 credits  ",
            provider: .poe) == "100 credits")
    }

    @Test
    func `empty post-strip value falls back to the full text`() {
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "balance: ", provider: .openrouter) ==
            "balance:")
    }

    @Test
    func `non-balance text and unsupported providers yield nil`() {
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "Pro 5x", provider: .openrouter) == nil)
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "balance: $4.96", provider: .codex) == nil)
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "balance: $4.96", provider: .claude) == nil)
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: nil, provider: .openrouter) == nil)
        #expect(CompactTableBalanceParser.balanceValue(loginMethod: "   ", provider: .openrouter) == nil)
    }

    @Test
    func `only the three balance providers opt in`() {
        #expect(CompactTableBalanceParser.supportsBalance(provider: .openrouter) == true)
        #expect(CompactTableBalanceParser.supportsBalance(provider: .mimo) == true)
        #expect(CompactTableBalanceParser.supportsBalance(provider: .poe) == true)
        #expect(CompactTableBalanceParser.supportsBalance(provider: .codex) == false)
        #expect(CompactTableBalanceParser.supportsBalance(provider: .factory) == false)
    }
}
