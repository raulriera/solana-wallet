import SwiftUI

/// Shows a sent payment's outcome, with a link to its explorer page, a way to retry a dropped payment, and, once the
/// payment settles or its check stops, a way to start a new payment.
struct PaymentResultScreen: TransactionResultContent {
    @Environment(\.newPayment) private var newPayment
    @AccessibilityFocusState private var isFocused: Bool
    let review: TransactionReviewModel<PaymentProposal>
    let outcome: TransactionOutcome

    var body: some View {
        let card = card
        Form {
            Section {
                TitleCardContent(title: card.title, message: card.message, systemImage: card.systemImage)
                    .symbolEffect(.breathe, isActive: review.isSending)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($isFocused)
            }

            Section {
                if outcome.status == .dropped {
                    Button("Try Again", action: review.tryAgain)
                }
                Link("View in Explorer", destination: outcome.explorerURL)
                if let newPayment, !review.isSending {
                    Button("New Payment") { newPayment() }
                }
            }
            .lineLimit(1)
        }
        .navigationTitle(Text(verbatim: review.proposal.recipient.title))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    private var card: TransactionResultCard {
        let payment = review.proposal
        return switch outcome.status {
        case .pending:
            .pending(review.confirmationError)
        case .succeeded:
            TransactionResultCard(
                title: "Sent",
                message: LocalizedStringResource("You sent \(payment.sent, format: .amount(of: payment.asset)) to \(payment.recipient.title).",
                                                 comment: "Message after a payment landed. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address."),
                systemImage: "checkmark.circle.fill")
        case .failed:
            .failed(
                title: "Payment Failed",
                message: "The network rejected this payment. Its network fee was paid. Nothing else left your wallet.")
        case .dropped:
            .dropped(message: "Nothing left your wallet.")
        }
    }
}
