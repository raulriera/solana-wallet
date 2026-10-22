import Portfolio
import SwiftUI

/// Shows how much SOL a deposit moves from the public balance into the private balance and what it costs, before the
/// person approves it from the top bar.
///
/// While the person reads it, the deposit is simulated again before its review expires.
struct DepositReviewScreen: View {
    @Environment(\.palette) private var palette
    let deposit: DepositModel
    let review: DepositModel.Review

    var body: some View {
        Form {
            Section {
                ReviewAmount(payment: deposit.payment)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("From") {
                    Text("Public Balance")
                }
                LabeledContent("To") {
                    Text("Private Balance")
                }
                LabeledContent("Network Fee") {
                    TokenBalance(amount: Self.sol(review.networkFee), symbol: deposit.payment.token.symbol)
                }
                if let registrationFee = review.registrationFee {
                    LabeledContent("Registration") {
                        TokenBalance(amount: Self.sol(registrationFee), symbol: deposit.payment.token.symbol)
                    }
                }
            } footer: {
                if review.registrationFee != nil {
                    Text("A one-time fee registers this account for private balances.",
                         comment: "Footer under the registration fee of an account's first deposit into its private balance.")
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
        // The symbol matches Add to Private Balance on SOL's details.
        .confirmationAction("Add to Private Balance", systemImage: "eye.slash", isEnabled: deposit.canApprove,
                            isPending: deposit.isWorking, action: deposit.approve)
        // A review expires after about a minute, so it's simulated again while it shows.
        .task {
            while (try? await Task.sleep(for: .seconds(30))) != nil {
                await deposit.refreshReview()
            }
        }
    }

    /// Shows lamports as SOL.
    /// - Parameter lamports: The lamports.
    /// - Returns: The amount in SOL's nine decimals.
    private static func sol(_ lamports: UInt64) -> Amount {
        Amount(units: lamports, decimals: 9)
    }
}
