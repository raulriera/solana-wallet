import SwiftUI
import Transactions

/// Shows a payment's amount, token, recipient, warnings, and costs before the person sends it.
struct PaymentReviewScreen: TransactionReviewContent {
    let review: TransactionReviewModel<PaymentProposal>

    var body: some View {
        let payment = review.proposal
        let costs = review.review
        Form {
            Section {
                ReviewAmount(sent: payment.sent, asset: payment.asset, value: payment.value,
                             currencyCode: payment.currencyCode)
            }
            .listRowBackground(Color.clear)

            RecipientReviewSection(recipient: payment.recipient, warnings: payment.warnings)

            Section {
                LabeledContent("Pay With") {
                    Text(payment.asset.displaySymbol)
                }
                if let transferFee = costs?.transferFee {
                    LabeledContent("Transfer Fee") {
                        TokenBalance(balance: transferFee, asset: payment.asset)
                    }
                }
                CostRow(title: "Network Fee", lamports: costs?.networkFee)
                if let accountDeposit = costs?.accountDeposit {
                    CostRow(title: "Account Deposit", lamports: accountDeposit)
                }
            } footer: {
                if costs?.accountDeposit != nil {
                    Text("A one-time deposit opens \(payment.recipient.title)'s \(payment.asset.displaySymbol) account. It goes to that account, not to this app.",
                         comment: "Footer under the deposit that opens a recipient's token account. The variables are the recipient's name or short address and the token's symbol, such as USDC.")
                }
            }

            Section {
                Button(action: review.approve) {
                    PendingLabel(title: "Send", isPending: review.isSending)
                }
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
