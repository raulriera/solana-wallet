#if DEBUG
import SwiftUI

/// Owns a payment of sample tokens, presents its keypad as the detail of the section's split view, and opens its
/// review, until contacts and sending are wired.
struct PaymentScene: View {
    @State private var payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    @State private var isReviewing = false
    /// Matches the Send button with the review, which grows out of it.
    @Namespace private var review
    /// Compact layouts show the keypad, since the sidebar has no contacts yet.
    @State private var preferredColumn = NavigationSplitViewColumn.detail

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            // Contacts join the sidebar once they're built.
            List {}
                .listStyle(.sidebar)
                .navigationTitle("Contacts")
                .sidebarColumnWidth()
        } detail: {
            PaymentAmountScreen(payment: payment, title: "Send") {
                SendButton(payment: payment, isReviewing: $isReviewing)
                    .matchedTransitionSource(id: ObjectIdentifier(payment), in: review)
            }
            // Collapsed, the empty sidebar has no way back to the keypad, so it isn't offered.
            .navigationBarBackButtonHidden()
        }
        .navigationSplitViewStyle(.tabSection)
        .sheet(isPresented: $isReviewing) {
            PaymentReviewSheet(payment: payment)
                // The review grows out of the Send button, and shrinks back into it when canceled.
                .navigationTransition(.zoom(sourceID: ObjectIdentifier(payment), in: review))
        }
    }
}
#endif
