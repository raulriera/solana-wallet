import SwiftUI

/// A toolbar button that opens the recipient sheet for a new payment.
struct NewPaymentButton: View {
    /// The recipient sheet's model, or `nil` when the sheet is closed.
    @Binding var entry: RecipientEntryModel?

    var body: some View {
        Button("New Payment", systemImage: "plus") { entry = RecipientEntryModel() }
            .tint(.primary)
    }
}
