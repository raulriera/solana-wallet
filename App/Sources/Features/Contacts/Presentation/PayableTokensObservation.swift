import SwiftUI

/// Follows the tokens that the window's account can pay with in its portfolio, so only this modifier reads each
/// portfolio update.
private struct PayableTokensObservation: ViewModifier {
    let portfolio: any PortfolioCoordinating
    /// The tokens with a balance and their prices' currency, or `nil` before the portfolio has anything to show.
    @Binding var tokens: PayableTokens?

    func body(content: Content) -> some View {
        content
            .onChange(of: portfolio.payableTokens(), initial: true) { _, latest in
                tokens = latest
            }
    }
}

extension View {
    /// Follows the tokens that the window's account can pay with as its balances, prices, and currency change.
    /// - Parameters:
    ///   - portfolio: The window's portfolio, on the window's network.
    ///   - tokens: Receives the tokens with a balance and their prices' currency, or `nil` before the portfolio has
    ///     anything to show.
    /// - Returns: A view that keeps `tokens` up to date.
    func payableTokens(from portfolio: any PortfolioCoordinating, into tokens: Binding<PayableTokens?>) -> some View {
        modifier(PayableTokensObservation(portfolio: portfolio, tokens: tokens))
    }
}
