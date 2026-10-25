import Portfolio
import SwiftUI

/// Shows how much SOL a move takes from one of the account's balances to the other and what it costs, before the
/// person approves it from the top bar.
///
/// While the person reads it, the move is simulated again before its review expires.
struct BalanceMoveReviewScreen: View {
    @Environment(\.palette) private var palette
    let move: BalanceMoveModel
    let review: BalanceMoveModel.Review

    var body: some View {
        Form {
            Section {
                ReviewAmount(amount: move.payment.amount)
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
                LabeledContent("Network Fee") {
                    TokenBalance(amount: Amount(lamports: review.networkFee), symbol: move.payment.token.symbol)
                }
                if let registrationFee = review.registrationFee {
                    LabeledContent("Registration") {
                        TokenBalance(amount: Amount(lamports: registrationFee), symbol: move.payment.token.symbol)
                    }
                }
                if let privacyFee = review.privacyFee {
                    LabeledContent("Privacy Fee") {
                        TokenBalance(amount: Amount(lamports: privacyFee), symbol: move.payment.token.symbol)
                    }
                }
            } footer: {
                if review.registrationFee != nil {
                    Text("A one-time fee registers this account for private balances.",
                         comment: "Footer under the registration fee of an account's first deposit into its private balance.")
                        .foregroundStyle(palette.secondaryText)
                } else if review.privacyFee != nil {
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
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        // The symbol matches the task's row on SOL's details.
        .confirmationAction(move.direction.title, systemImage: move.direction == .toPrivate ? "eye.slash" : "eye",
                            isEnabled: move.canApprove, isPending: move.isWorking, action: move.approve)
        // A review expires after about a minute, so it's simulated again while it shows.
        .task {
            while (try? await Task.sleep(for: .seconds(30))) != nil {
                await move.refreshReview()
            }
        }
    }
}
