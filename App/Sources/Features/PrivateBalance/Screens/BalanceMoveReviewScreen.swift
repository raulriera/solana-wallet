import Portfolio
import SwiftUI

/// Shows a balance move's amount, balances, and fees for approval.
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
                    Text("The network fee pays Solana to process this transaction. The privacy fee goes to the private balance pool, which uses it to record spent SOL so it can't be spent twice. This app takes no fee.",
                         comment: "Footer under the fees of moving private SOL to the public balance, when the private balance pool charges a privacy fee.")
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Section {
                Button(action: review.approve) {
                    PendingLabel(title: move.direction.title, isPending: review.attempt != nil || review.isSending)
                }
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .disabled(!review.canApprove)
            }
        }
        .monospacedDigit()
        .animation(.default, value: costs)
        .navigationTitle("Review")
        .toolbarTitleDisplayMode(.inline)
    }
}
