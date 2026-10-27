import Portfolio
import SwiftUI

/// Shows a review's network fee in SOL, or a placeholder until the first simulation reads it.
struct NetworkFeeRow: View {
    /// The network fee, with any service tip, in lamports, or `nil` before the first simulation.
    let fee: UInt64?

    var body: some View {
        LabeledContent("Network Fee") {
            TokenBalance(amount: Amount(lamports: fee ?? Self.placeholderFee), symbol: "SOL")
                // Until the first simulation, a placeholder keeps the row's place instead of a spinner, and VoiceOver
                // doesn't read its made-up value.
                .redacted(reason: fee == nil ? .placeholder : [])
                .accessibilityHidden(fee == nil)
        }
    }

    /// A typical network fee, which the placeholder shows until the first simulation, in lamports.
    private static let placeholderFee: UInt64 = 5_000
}
