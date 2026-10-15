#if DEBUG
import SwiftUI

/// Owns a payment of sample tokens, presents its keypad as the detail of the section's split view, and opens its
/// review, until contacts and sending are wired.
struct PaymentScene: View {
    @State private var payment = PaymentModel(tokens: PaymentToken.samples, currencyCode: "USD")
    @State private var isReviewing = false
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
            PaymentAmountScreen(payment: payment, isReviewing: $isReviewing)
                // Collapsed, the empty sidebar has no way back to the keypad, so it isn't offered.
                .navigationBarBackButtonHidden()
        }
        .navigationSplitViewStyle(.tabSection)
        .sheet(isPresented: $isReviewing) {
            PaymentReviewSheet(payment: payment)
        }
    }
}
#endif
