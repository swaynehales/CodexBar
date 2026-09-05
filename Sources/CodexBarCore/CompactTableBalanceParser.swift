import Foundation

/// Shared balance-value parser for the credit-balance providers (option B, spec rev 2 §5b).
///
/// OpenRouter, Mimo, and Poe embed the remaining balance in the loginMethod string as a
/// `balance:` fragment. Both the menu's Balance row and the compact table's Credits value
/// row read through this parser so the two surfaces cannot drift.
public enum CompactTableBalanceParser {
    /// Provider-specific by design: only these providers report balances via the loginMethod
    /// string contract; every other provider's loginMethod is plan/identity text.
    private static let balanceProviders: Set<UsageProvider> = [.openrouter, .mimo, .poe]

    public static func supportsBalance(provider: UsageProvider) -> Bool {
        self.balanceProviders.contains(provider)
    }

    /// Extracts the balance value (e.g. "$4.96") from a loginMethod string, or nil when the
    /// provider carries no balance or the fragment is absent. An empty post-strip value falls
    /// back to the full text, matching the menu's historical behavior.
    public static func balanceValue(loginMethod: String?, provider: UsageProvider) -> String? {
        guard self.supportsBalance(provider: provider) else { return nil }
        guard let text = loginMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.localizedCaseInsensitiveContains("balance:")
        else { return nil }
        let stripped = text
            .replacingOccurrences(of: #"(?i)^\s*balance:\s*"#, with: "", options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? text : stripped
    }
}
