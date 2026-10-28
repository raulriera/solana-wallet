import SwiftUI
import Transactions

/// Pays one recipient on the keypad in its own navigation container, with their details a push away and the
/// payment's review growing out of the Send button.
///
/// The latest review goes to the owner of the amount, which keeps it after its sheet closes. Without a token to pay with,
/// the keypad's place explains that there's nothing to send; the details stay a push away.
struct RecipientPaymentStack<Details: View>: View {
    let recipient: PaymentRecipient
    /// The payment being typed, or `nil` when the account has no token with a balance; it stays when the person picks
    /// another recipient.
    let payment: PaymentModel?
    /// The person's own history, which the review's checks compare the recipient with.
    let context: RecipientContext
    /// The window's account, network, and transactions, which send the payment.
    let sender: PaymentSender
    /// The recipient's details, which the keypad's Details button pushes.
    let details: Details
    /// The latest payment's review, which the owner of the amount keeps after it closes.
    @Binding var review: TransactionReviewModel<PaymentProposal>?
    /// The review that shows, or `nil` while none does.
    @State private var presentedReview: TransactionReviewModel<PaymentProposal>?
    /// Why a payment couldn't start.
    @State private var sendError: SendError?
    @State private var showsDetails = false
    /// Matches the Send button with the review, which grows out of it.
    @Namespace private var reviewTransition

    /// Creates the keypad for a recipient.
    /// - Parameters:
    ///   - recipient: Who the payment goes to.
    ///   - payment: The payment being typed, or `nil` when the account has no token with a balance.
    ///   - context: The person's own history, which the review's checks compare the recipient with.
    ///   - sender: The window's account, network, and transactions, which send the payment.
    ///   - review: The latest payment's review, which the owner of the amount keeps after it closes.
    ///   - details: The recipient's details, which the keypad's Details button pushes.
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
                        SendButton(payment: payment,
                                   send: SendPaymentAction(sender: sender, payment: payment, recipient: recipient,
                                                           context: context, review: $review,
                                                           presented: $presentedReview, error: $sendError))
                            .matchedTransitionSource(id: ObjectIdentifier(payment), in: reviewTransition)
                    }
                    .sheet(item: $presentedReview) { review in
                        TransactionReviewSheet<PaymentReviewScreen, PaymentResultScreen>(review: review)
                            .transactionReviewLifecycle()
                            // The review grows out of the Send button, and shrinks back into it when canceled.
                            .navigationTransition(.zoom(sourceID: ObjectIdentifier(payment), in: reviewTransition))
                    }
                    .errorAlert($sendError)
                } else {
                    UnavailableScreen(title: "Nothing to Send",
                                      message: "This account has no tokens with a balance on this network.",
                                      systemImage: "wallet.bifold") {}
                        // Titled like the keypad, so the recipient stays named.
                        .navigationTitle(Text(verbatim: recipient.title))
                        .navigationSubtitle(Text(verbatim: recipient.subtitle))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                    Button("Details", systemImage: "info.circle") { showsDetails = true }
                        .tint(.primary)
                }
            }
            .navigationDestination(isPresented: $showsDetails) { details }
        }
    }
}
