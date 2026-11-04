import SwiftUI

/// Shows how a sent payment settled, with a link to its explorer page and a way to retry a dropped payment.
struct PaymentResultScreen: TransactionResultContent {
    @Environment(\.palette) private var palette
    @AccessibilityFocusState private var isFocused: Bool
    let review: TransactionReviewModel<PaymentProposal>
    let outcome: TransactionOutcome

    var body: some View {
        let card = card
        Form {
            Section {
                TitleCardContent(title: card.title, message: card.message, systemImage: card.systemImage)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($isFocused)
            }

            if let submission = review.submission {
                Section {
                    if outcome == .dropped {
                        Button("Try Again", action: review.tryAgain)
                    }
                    Link("View in Explorer", destination: submission.explorerURL)
                }
                .foregroundStyle(palette.primary)
            }
        }
        .navigationTitle(Text(verbatim: review.proposal.recipient.title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let payment = review.proposal
        return switch outcome {
        case .succeeded:
            ("Sent",
             LocalizedStringResource("\(payment.recipient.title) received \(payment.amount.quantity, format: .quantity(of: payment.amount.token)).",
                                     comment: "Message after a payment landed. The variables are the recipient's name or short address and the amount with its symbol, such as 0.5 SOL."),
             "checkmark.circle.fill")
        case .failed:
            ("Payment Failed",
             "The network rejected this payment. Its network fee was paid. Nothing else left your wallet.",
             "exclamationmark.triangle.fill")
        case .dropped:
            ("Not Sent", "Nothing left your wallet.", "xmark.circle.fill")
        }
    }
}
