import Observation
import RPC
import SwiftUI
@testable import widgets

/// Receives what a window's keypad pays with, as the contacts tab's state does.
@MainActor
@Observable
final class ReceivedKeypadPayment {
    /// What the keypad pays with.
    var payment = KeypadPayment.loading
}

/// Follows an account's tokens with a balance in the shared portfolios, as the contacts tab does.
struct KeypadPaymentObservationRoot: View {
    let portfolios: PortfolioStore
    let account: widgets.Account
    let network: Network
    let received: ReceivedKeypadPayment

    var body: some View {
        @Bindable var received = received
        Color.clear
            .keypadPayment(for: account, on: network, into: $received.payment)
            .environment(portfolios)
    }
}
