import Observation
import SwiftUI
@testable import widgets

/// Receives the tokens that a window's account can pay with, as the contacts scene's state does.
@MainActor
@Observable
final class ReceivedPayableTokens {
    /// The latest tokens and their prices' currency, or `nil` before the portfolio has anything to show.
    var tokens: PayableTokens?
}

/// Follows a portfolio's tokens with a balance, as the contacts scene does.
struct PayableTokensObservationRoot: View {
    let portfolio: any PortfolioCoordinating
    let received: ReceivedPayableTokens

    var body: some View {
        @Bindable var received = received
        Color.clear
            .payableTokens(from: portfolio, into: $received.tokens)
    }
}
