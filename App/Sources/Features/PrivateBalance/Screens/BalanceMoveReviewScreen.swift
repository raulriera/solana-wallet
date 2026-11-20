import SwiftUI
import Transactions

/// Shows a balance move's amount, recipient, balances, and fees for approval.
struct BalanceMoveReviewScreen: TransactionReviewContent {
    @Environment(\.palette) private var palette
    let review: TransactionReviewModel<BalanceMoveProposal>

    var body: some View {
        let move = review.proposal
        let costs = review.review
        Form {
            Section {
                ReviewAmount(sent: move.sent, asset: move.asset)
            }
            .listRowBackground(Color.clear)

            if case .toRecipient(let recipient, let warnings) = move.direction {
                RecipientReviewSection(recipient: recipient, warnings: warnings)
            }

            Section {
                switch move.direction {
                case .toPrivate:
                    LabeledContent("From") { Text("Public Balance") }
                    LabeledContent("To") { Text("Private Balance") }
                case .toPublic:
                    LabeledContent("From") { Text("Private Balance") }
                    LabeledContent("To") { Text("Public Balance") }
                case .toRecipient:
                    LabeledContent("From") { Text("Private Balance") }
                }
                CostRow(title: "Network Fee", lamports: costs?.networkFee)
                if let registrationFee = costs?.registrationFee {
                    CostRow(title: "Registration", lamports: registrationFee)
                }
                if let privacyFee = costs?.privacyFee {
                    CostRow(title: "Privacy Fee", lamports: privacyFee)
                }
                if let accountDeposit = costs?.accountDeposit {
                    CostRow(title: "Account Deposit", lamports: accountDeposit)
                }
            } footer: {
                if costs?.registrationFee != nil {
                    Text("A one-time fee registers this account for private balances.",
                         comment: "Footer under the registration fee of an account's first deposit into its private balance.")
                        .foregroundStyle(palette.secondaryText)
                } else if costs?.privacyFee != nil, costs?.accountDeposit != nil {
                    Text("The network fee pays Solana to process this transaction. The privacy fee goes to the private balance pool, which uses it to record what was spent so it can't be spent twice. A one-time deposit opens this account's \(move.asset.displaySymbol) account, and it goes to that account. This app takes no fee.",
                         comment: "Footer under the fees of moving a private token to the public balance, when the pool charges a privacy fee and the account has no account for the token yet. The variable is the token's symbol, such as USDC.")
                        .foregroundStyle(palette.secondaryText)
                } else if costs?.accountDeposit != nil {
                    Text("A one-time deposit opens this account's \(move.asset.displaySymbol) account. It goes to that account, not to this app.",
                         comment: "Footer under the deposit that opens the account's token account when moving a private token to the public balance. The variable is the token's symbol, such as USDC.")
                        .foregroundStyle(palette.secondaryText)
                } else if costs?.privacyFee != nil {
                    Text("The network fee pays Solana to process this transaction. The privacy fee goes to the private balance pool, which uses it to record what was spent so it can't be spent twice. This app takes no fee.",
                         comment: "Footer under the fees of moving a private token to the public balance or sending it to another person, when the private balance pool charges a privacy fee.")
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Section {
                Button(action: review.approve) {
                    PendingLabel(title: move.title, isPending: review.attempt != nil || review.isSending)
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
