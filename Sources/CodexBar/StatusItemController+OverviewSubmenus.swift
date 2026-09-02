import AppKit
import CodexBarCore

extension StatusItemController {
    func makeOverviewRowSubmenu(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> NSMenu?
    {
        if provider == .openai,
           self.settings.costSummaryShowsSubmenu(for: provider),
           let submenu = self.makeOpenAIAPIUsageSubmenu(provider: provider, width: width)
        {
            return submenu
        }
        // Mistral's top usage pane has no rate-limit bars of its own, so its Overview row prioritizes
        // cost history when the display style permits it. Other `tokenCostRequiresProviderSnapshot`
        // providers (e.g. opencodego) show real rate-limit bars and fall through to the generic check.
        if provider == .mistral,
           self.settings.costSummaryShowsSubmenu(for: provider),
           let submenu = self.makeCostHistorySubmenu(provider: provider, width: width)
        {
            return submenu
        }
        if self.settings.costSummaryShowsSubmenu(for: provider),
           model.tokenUsage != nil,
           let submenu = self.makeCostHistorySubmenu(provider: provider, width: width)
        {
            return submenu
        }
        if let submenu = self.makeUsageHistorySubmenu(provider: provider, width: width) {
            return submenu
        }
        return self.makeStorageBreakdownSubmenu(provider: provider, width: width)
    }

    @objc func selectOverviewProvider(_ sender: NSMenuItem) {
        guard let represented = sender.representedObject as? String else { return }
        // Grid rows host multiple cards per item; keyboard activation on a grid row falls
        // back to the first provider in the batch (the top-left card in reading order).
        if represented == Self.overviewGridRowIdentifier {
            guard let menu = sender.menu,
                  let firstProvider = self.store.enabledFirstPartyProvidersForDisplay().first
            else { return }
            self.selectOverviewProvider(firstProvider, menu: menu)
            return
        }
        guard represented.hasPrefix(Self.overviewRowIdentifierPrefix) else { return }
        let rawProvider = represented.dropFirst(Self.overviewRowIdentifierPrefix.count)
        guard let provider = UsageProvider(rawValue: String(rawProvider)),
              let menu = sender.menu
        else {
            return
        }

        self.selectOverviewProvider(provider, menu: menu)
    }

    func selectOverviewProvider(_ provider: UsageProvider, menu: NSMenu) {
        if !self.settings.mergedMenuLastSelectedWasOverview, self.selectedMenuProvider == provider.instanceID {
            return
        }
        self.preservingMergedSwitcherContentCachesDuringInvalidation {
            self.settings.mergedMenuLastSelectedWasOverview = false
            self.lastMergedSwitcherSelection = .provider(provider.instanceID)
            self.selectedMenuProvider = provider.instanceID
            self.lastMenuProvider = provider.instanceID
            self.refreshProviderSelectionDependentUI(deferRendering: true)
        }
        // Custom-view clicks stay open and rebuild next turn. Standard menu-item activation can close;
        // menuWillOpen then renders the saved provider without doing structural work inside the action.
        self.requestProviderSwitcherMenuRebuild(menu, provider: provider)
    }
}
