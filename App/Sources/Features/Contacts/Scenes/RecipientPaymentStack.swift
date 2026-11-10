import SwiftUI
import Transactions

/// Shows the keypad that pays a recipient in its own navigation container.
struct RecipientPaymentStack<Details: View>: View {
    let recipient: PaymentRecipient
    /// The payment being typed, or `nil` when the account has no token with a balance.
    let payment: PaymentModel?
    let context: RecipientContext
    let sender: PaymentSender
    let details: Details
    /// The review of the last sent payment.
    @Binding var review: TransactionReviewModel<PaymentProposal>?
    /// The review that shows, or `nil` when none does.
    @State private var presentedReview: TransactionReviewModel<PaymentProposal>?
    @State private var sendError: SendError?
    @State private var showsDetails = false

    /// Creates the keypad for a recipient.
    ///
    /// - Parameters:
    ///   - recipient: The recipient of the payment.
    ///   - payment: The payment being typed, or `nil` when the account has no token with a balance.
    ///   - context: The context to check the recipient against.
    ///   - sender: The service that sends the payment.
    ///   - review: The review of the last sent payment.
    ///   - details: The recipient's details.
    init(recipient: PaymentRecipient, payment: PaymentModel?, context: RecipientContext, sender: PaymentSender,
         review: Binding<TransactionReviewModel<PaymentProposal>?>, @ViewBuilder details: () -> Details) {
        self.recipient = recipient
        self.payment = payment
        self.context = context
        self.sender = sender
        _review = review
        self.details = details()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let payment {
                    PaymentAmountScreen(payment: payment, recipient: recipient) {
                        let openReview = PaymentReviewAction(sender: sender, payment: payment, recipient: recipient,
                                                             context: context, review: $review,
                                                             presented: $presentedReview, error: $sendError)
                        Button("Review") { openReview() }
                            .buttonStyle(.secondary)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!payment.canSend)
                    }
                    .alert(error: $sendError)
                } else {
                    UnavailableScreen(title: "Nothing to Send",
                                      message: "This account has no tokens with a balance on this network.",
                                      systemImage: "wallet.bifold") {}
                        .navigationTitle(Text(verbatim: recipient.title))
                        .navigationSubtitle(Text(verbatim: recipient.subtitle))
                        .toolbarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Details", systemImage: "info.circle") { showsDetails = true }
                        .tint(.primary)
                }
            }
            .navigationDestination(isPresented: $showsDetails) { details }
            .navigationDestination(item: $presentedReview) { review in
                TransactionReviewScreen<PaymentReviewScreen, PaymentResultScreen>(review: review)
            }
        }
    }
}
