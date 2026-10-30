import RPC
import SwiftUI

/// A modifier that keeps the keypad's payment up to date with the tokens an account can pay with.
private struct KeypadPaymentObservation: ViewModifier {
    @Environment(PortfolioStore.self) private var portfolios
    let account: Account
    let network: Network
    @Binding var payment: KeypadPayment

    func body(content: Content) -> some View {
        let tokens = portfolios.portfolio(for: account, on: network).flatMap {
            PayableTokens(holdings: $0.holdings, error: $0.error)
        }
        content
            .onChange(of: tokens, initial: true) { _, tokens in
                follow(tokens)
            }
    }

    /// Updates the payment with the account's tokens and their prices' currency.
    ///
    /// - Parameter tokens: The tokens with a balance, or `nil` before the portfolio has anything to show.
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
        withAnimation { model.update(tokens.tokens, currencyCode: tokens.currencyCode) }
    }
}

extension View {
    /// Keeps a keypad payment up to date with the tokens an account can pay with.
    ///
    /// - Parameters:
    ///   - account: The account that pays.
    ///   - network: The network of the account's portfolio.
    ///   - payment: The keypad payment to update.
    /// - Returns: A view that keeps `payment` up to date.
    func keypadPayment(for account: Account, on network: Network, into payment: Binding<KeypadPayment>) -> some View {
        modifier(KeypadPaymentObservation(account: account, network: network, payment: payment))
    }
}
