import Portfolio
import SwiftUI

/// Shows how much SOL a move takes from one of the account's balances to the other and what it costs, before the
/// person approves it from the top bar.
///
/// It shows at once, while the move is proved and simulated; the approval waits until the move can be approved. While
/// the person reads it, the review's lifecycle simulates the move again before the review expires.
struct BalanceMoveReviewScreen: TransactionReviewContent {
    @Environment(\.palette) private var palette
    let review: TransactionReviewModel<BalanceMoveProposal>

    var body: some View {
        let move = review.proposal
        let costs = review.review
        Form {
            Section {
                ReviewAmount(amount: move.amount)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("From") {
                    switch move.direction {
                    case .toPrivate: Text("Public Balance")
                    case .toPublic: Text("Private Balance")
                    }
                }
                LabeledContent("To") {
                    switch move.direction {
                    case .toPrivate: Text("Private Balance")
                    case .toPublic: Text("Public Balance")
                    }
                }
                NetworkFeeRow(fee: costs?.networkFee)
                if let registrationFee = costs?.registrationFee {
                    LabeledContent("Registration") {
                        TokenBalance(amount: Amount(lamports: registrationFee), symbol: "SOL")
                    }
                }
                if let privacyFee = costs?.privacyFee {
                    LabeledContent("Privacy Fee") {
                        TokenBalance(amount: Amount(lamports: privacyFee), symbol: "SOL")
                    }
                }
            } footer: {
                if costs?.registrationFee != nil {
                    Text("A one-time fee registers this account for private balances.",
                         comment: "Footer under the registration fee of an account's first deposit into its private balance.")
                        .foregroundStyle(palette.secondaryText)
                } else if costs?.privacyFee != nil {
                    // A fee that the person didn't expect says where it goes, so it doesn't read as a scam.
                    Text("The network fee pays Solana to process this transaction. The privacy fee goes to the private balance pool, which uses it to record spent SOL so it can't be spent twice. This app takes no fee.",
                         comment: "Footer under the fees of moving private SOL to the public balance, when the private balance pool charges a privacy fee.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .listRowBackground(palette.surface)
        }
        .monospacedDigit()
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        // Fees that change between simulations count to their new values.
        .animation(.default, value: costs)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        // The symbol matches the task's row on SOL's details. Proving takes a few seconds, so the approval shows that
        // the move is being prepared, as it does while it's sent.
        .confirmationAction(move.direction.title, systemImage: move.direction == .toPrivate ? "eye.slash" : "eye",
                            isEnabled: review.canApprove, isPending: review.attempt != nil || review.isSending,
                            action: review.approve)
    }
}
