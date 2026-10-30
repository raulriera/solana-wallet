import Portfolio
import SwiftUI

/// Shows a review's network fee in SOL, or a placeholder while it's unknown.
struct NetworkFeeRow: View {
    /// The network fee with any service tip, in lamports, or `nil` if unknown.
    let fee: UInt64?

    var body: some View {
        LabeledContent("Network Fee") {
            TokenBalance(amount: Amount(lamports: fee ?? Self.placeholderFee), symbol: "SOL")
                .redacted(reason: fee == nil ? .placeholder : [])
                .accessibilityHidden(fee == nil)
        }
    }

    /// The fee that the placeholder shows, in lamports.
    private static let placeholderFee: UInt64 = 5_000
}
