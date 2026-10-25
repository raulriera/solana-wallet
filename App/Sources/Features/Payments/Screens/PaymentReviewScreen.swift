import Portfolio
import SwiftUI
import Transactions

/// Shows how much the payment sends, in which token, to whom, and what it costs, with anything to check about the
/// recipient, before the person sends it from the top bar.
///
/// While the person reads it, the payment is simulated again before its review expires.
struct PaymentReviewScreen: View {
    @Environment(\.palette) private var palette
    let send: SendModel

    var body: some View {
        let review = send.review
        Form {
            Section {
                ReviewAmount(amount: send.amount)
            }
            .listRowBackground(Color.clear)

            Section {
                if let name = send.recipient.name {
                    Text(name)
                }
                // The whole address, so people can check every character before sending.
                FullAddress(text: send.recipient.address.value)
                ForEach(send.warnings, id: \.self) { warning in
                    RecipientWarningLabel(warning: warning)
                }
            } header: {
                Text("To")
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Pay With") {
                    Text(send.amount.token.symbol)
                }
                LabeledContent("Network Fee") {
                    TokenBalance(amount: Amount(lamports: review?.networkFee ?? Self.placeholderFee), symbol: "SOL")
                        // Until the first simulation, a placeholder keeps the row's place instead of a spinner, and
                        // VoiceOver doesn't read its made-up value.
                        .redacted(reason: review == nil ? .placeholder : [])
                        .accessibilityHidden(review == nil)
                }
                if let accountDeposit = review?.accountDeposit {
                    LabeledContent("Account Deposit") {
                        TokenBalance(amount: Amount(lamports: accountDeposit), symbol: "SOL")
                    }
                }
            } footer: {
                if review?.accountDeposit != nil {
                    // A cost that the person didn't expect says where it goes, so it doesn't read as a scam.
                    Text("A one-time deposit opens \(send.recipient.title)'s \(send.amount.token.symbol) account. It goes to that account, not to this app.",
                         comment: "Footer under the deposit that opens a recipient's token account. The variables are the recipient's name or short address and the token's symbol, such as USDC.")
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
        .animation(.default, value: review)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationAction("Send", isEnabled: send.canApprove, isPending: send.isSending, action: send.approve)
        // A blockhash lasts about 30 seconds, so the review is simulated again well before it expires.
        .task {
            while (try? await Task.sleep(for: .seconds(10))) != nil {
                await send.refreshReview()
            }
        }
    }

    /// A typical network fee, which the placeholder shows until the first simulation, in lamports.
    private static let placeholderFee: UInt64 = 5_000
}
