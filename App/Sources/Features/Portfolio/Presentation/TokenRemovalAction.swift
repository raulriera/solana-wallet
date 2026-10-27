import Portfolio
import SwiftUI

/// Removes a confirmed token from the wallet's list, from any view in the portfolio, the way SwiftUI's `dismiss` acts
/// for the view that reads it.
struct TokenRemovalAction {
    /// The portfolio's token removals, which run with ``PortfolioSplitView/tokenRemovalLifecycle()``.
    let removal: TokenRemovalModel

    /// Removes a token the person confirmed; native SOL always stays.
    /// - Parameter token: The token to remove.
    func callAsFunction(_ token: Holding.Identity) {
        removal.remove(token)
    }
}
