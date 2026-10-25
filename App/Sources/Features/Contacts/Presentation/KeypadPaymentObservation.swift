import SwiftUI

/// Follows the tokens that the window's account can pay with in its portfolio, so only this modifier reads each
/// portfolio update.
///
/// The payment changes in place as balances and prices change, so its owner updates only when the keypad starts,
/// or when there's nothing left to pay with.
private struct KeypadPaymentObservation: ViewModifier {
    let portfolio: any PortfolioCoordinating
    /// What the keypad pays with.
    @Binding var payment: KeypadPayment

    func body(content: Content) -> some View {
        content
            .onChange(of: portfolio.payableTokens(), initial: true) { _, tokens in
                follow(tokens)
            }
    }

    /// Keeps the payment's tokens with the account's balances and prices, keeping the amount as typed while its token
    /// and currency remain.
    /// - Parameter tokens: The account's tokens with a balance and their prices' currency, or `nil` before its
    ///   portfolio has anything to show.
    private func follow(_ tokens: PayableTokens?) {
        guard let tokens else {
            payment = .loading
            return
        }
        guard !tokens.tokens.isEmpty else {
            payment = .nothingToSend
            return
        }
        guard let model = payment.model else {
            payment = .ready(PaymentModel(tokens: tokens.tokens, currencyCode: tokens.currencyCode))
            return
        }
        // Balances and values that change animate in place.
        withAnimation { model.update(tokens.tokens, currencyCode: tokens.currencyCode) }
    }
}

extension View {
    /// Follows the tokens that the window's account can pay with as its balances, prices, and currency change.
    /// - Parameters:
    ///   - portfolio: The window's portfolio, on the window's network.
    ///   - payment: What the keypad pays with, which starts a payment once the portfolio lists a token with a
    ///     balance and keeps it up to date.
    /// - Returns: A view that keeps `payment` up to date.
    func keypadPayment(from portfolio: any PortfolioCoordinating, into payment: Binding<KeypadPayment>) -> some View {
        modifier(KeypadPaymentObservation(portfolio: portfolio, payment: payment))
    }
}
