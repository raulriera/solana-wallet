import Observation
import RPC
import SwiftUI
@testable import widgets

@MainActor
@Observable
final class ReceivedKeypadPayment {
    var payment = KeypadPayment.loading
}

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
