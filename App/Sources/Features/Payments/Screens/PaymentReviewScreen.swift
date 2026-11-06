import Portfolio
import SwiftUI
import Transactions

/// Shows a payment's amount, token, recipient, warnings, and costs before the person sends it.
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
                FullAddress(text: payment.recipient.address.value)
                ForEach(payment.warnings, id: \.self) { warning in
                    RecipientWarningLabel(warning: warning)
                }
            } header: {
                if let name = payment.recipient.name {
                    Text("To \(name)",
                         comment: "Header above the address a payment goes to. The variable is the recipient's name.")
                } else {
                    Text("To")
                }
            }

            Section {
                LabeledContent("Pay With") {
                    Text(payment.amount.token.symbol)
                }
                NetworkFeeRow(fee: costs?.networkFee)
                if let accountDeposit = costs?.accountDeposit {
                    LabeledContent("Account Deposit") {
                        TokenBalance(amount: Amount(lamports: accountDeposit), symbol: "SOL")
                    }
                }
            } footer: {
                if costs?.accountDeposit != nil {
                    Text("A one-time deposit opens \(payment.recipient.title)'s \(payment.amount.token.symbol) account. It goes to that account, not to this app.",
                         comment: "Footer under the deposit that opens a recipient's token account. The variables are the recipient's name or short address and the token's symbol, such as USDC.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .monospacedDigit()
        .animation(.default, value: costs)
        .navigationTitle("Review")
        .toolbarTitleDisplayMode(.inline)
        .confirmationAction("Send", isEnabled: review.canApprove, isPending: review.isSending,
                            action: review.approve)
    }
}
