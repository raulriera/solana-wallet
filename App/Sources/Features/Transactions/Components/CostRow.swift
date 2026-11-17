import SwiftUI
import Transactions

/// Shows one of a review's costs in SOL, or a placeholder while it's unknown.
struct CostRow: View {
    let title: LocalizedStringResource
    /// The cost in lamports, or `nil` while it's unknown.
    let lamports: UInt64?

    var body: some View {
        LabeledContent {
            TokenBalance(balance: TokenAmount(lamports: lamports ?? Self.placeholderLamports), asset: .nativeSOL)
                .redacted(reason: lamports == nil ? .placeholder : [])
                .accessibilityHidden(lamports == nil)
        } label: {
            Text(title)
        }
    }

    /// The cost that the placeholder shows, in lamports.
    private static let placeholderLamports: UInt64 = 5_000
}
