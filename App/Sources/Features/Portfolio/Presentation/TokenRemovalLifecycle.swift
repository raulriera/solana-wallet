import RPC
import SwiftUI

/// Runs the portfolio's confirmed token removals, explains a failed save, and offers to try it again.
///
/// It attaches to the portfolio, which stays on screen when a removed token's details close.
private struct TokenRemovalLifecycle: ViewModifier {
    @Environment(PortfolioStore.self) private var portfolios
    @Bindable var removal: TokenRemovalModel
    let account: Account
    let network: Network

    /// Runs each confirmed removal and presents a failed save.
    /// - Parameter content: The portfolio's split view.
    /// - Returns: The split view with managed removals and error presentation.
    func body(content: Content) -> some View {
        let attempt = removal.attempt
        content
            .task(id: attempt) { await removal.run(attempt, in: portfolios, for: account, on: network) }
            .errorAlert($removal.error, retry: removal.retry)
    }
}

extension PortfolioSplitView {
    /// Runs the portfolio's token removals while it's on screen.
    /// - Returns: The split view with managed removals and error presentation.
    func tokenRemovalLifecycle() -> some View {
        modifier(TokenRemovalLifecycle(removal: removal, account: account, network: network))
    }
}
