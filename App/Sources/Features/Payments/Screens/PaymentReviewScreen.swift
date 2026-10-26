import Portfolio
import SwiftUI
import Transactions

/// Shows how much the payment sends, in which token, to whom, and what it costs, with anything to check about the
/// recipient, before the person sends it from the top bar.
///
/// While the person reads it, the review's lifecycle simulates the payment again before the review expires.
struct PaymentReviewScreen: TransactionReviewContent {
    @Environment(\.palette) private var palette
    let review: TransactionReviewModel<PaymentProposal>

    var body: some View {
        let payment = review.proposal
        let costs = review.review
        Form {
            Section {
                ReviewAmount(amount: payment.amount)
            }
            .listRowBackground(Color.clear)

            Section {
                // The whole address, so people can check every character before sending.
                FullAddress(text: payment.recipient.address.value)
                ForEach(payment.warnings, id: \.self) { warning in
                    RecipientWarningLabel(warning: warning)
                }
            } header: {
                // A named recipient is named in the header, so named and unnamed addresses share one layout.
                if let name = payment.recipient.name {
                    Text("To \(name)",
                         comment: "Header above the address a payment goes to. The variable is the recipient's name.")
                } else {
                    Text("To")
                }
            }
            .listRowBackground(palette.surface)

            Section {
                LabeledContent("Pay With") {
                    Text(payment.amount.token.symbol)
                }
                LabeledContent("Network Fee") {
                    TokenBalance(amount: Amount(lamports: costs?.networkFee ?? Self.placeholderFee), symbol: "SOL")
                        // Until the first simulation, a placeholder keeps the row's place instead of a spinner, and
                        // VoiceOver doesn't read its made-up value.
                        .redacted(reason: costs == nil ? .placeholder : [])
                        .accessibilityHidden(costs == nil)
                }
                if let accountDeposit = costs?.accountDeposit {
                    LabeledContent("Account Deposit") {
                        TokenBalance(amount: Amount(lamports: accountDeposit), symbol: "SOL")
                    }
                }
            } footer: {
                if costs?.accountDeposit != nil {
                    // A cost that the person didn't expect says where it goes, so it doesn't read as a scam.
                    Text("A one-time deposit opens \(payment.recipient.title)'s \(payment.amount.token.symbol) account. It goes to that account, not to this app.",
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
        .animation(.default, value: costs)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationAction("Send", isEnabled: review.canApprove, isPending: review.isSending,
                            action: review.approve)
    }

    /// A typical network fee, which the placeholder shows until the first simulation, in lamports.
    private static let placeholderFee: UInt64 = 5_000
}
