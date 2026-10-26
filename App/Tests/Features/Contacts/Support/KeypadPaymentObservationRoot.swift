import Observation
import SwiftUI
@testable import widgets

/// Receives what a window's keypad pays with, as the contacts tab's state does.
@MainActor
@Observable
final class ReceivedKeypadPayment {
    /// What the keypad pays with.
    var payment = KeypadPayment.loading
}

/// Follows a portfolio's tokens with a balance, as the contacts tab does.
struct KeypadPaymentObservationRoot: View {
    let portfolio: any PortfolioCoordinating
    let received: ReceivedKeypadPayment

    var body: some View {
        @Bindable var received = received
        Color.clear
            .keypadPayment(from: portfolio, into: $received.payment)
    }
}
