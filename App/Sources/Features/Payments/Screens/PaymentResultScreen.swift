import SwiftUI

/// Shows how a sent payment settled, with a link to its explorer page, a way to retry a dropped payment, and a way to
/// start a new payment.
struct PaymentResultScreen: TransactionResultContent {
    @Environment(\.palette) private var palette
    @Environment(\.newPayment) private var newPayment
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

            Section {
                if let submission = review.submission {
                    if outcome == .dropped {
                        Button("Try Again", action: review.tryAgain)
                    }
                    Link("View in Explorer", destination: submission.explorerURL)
                }
                if let newPayment {
                    Button("New Payment") { newPayment() }
                }
            }
            .foregroundStyle(palette.primary)
            .lineLimit(1)
        }
        .navigationTitle(Text(verbatim: review.proposal.recipient.title))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let payment = review.proposal
        return switch outcome {
        case .succeeded:
            ("Sent",
             LocalizedStringResource("You sent \(payment.sent, format: .amount(of: payment.asset)) to \(payment.recipient.title).",
                                     comment: "Message after a payment landed. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address."),
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
