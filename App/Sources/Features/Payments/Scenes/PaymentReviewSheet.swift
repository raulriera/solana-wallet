import SwiftUI

/// Presents a payment's review in its own navigation container.
struct PaymentReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat?
    let payment: PaymentModel

    var body: some View {
        NavigationStack {
            PaymentReviewScreen(payment: payment)
                // The review holds little, so the sheet is as tall as its content, top bar included.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, height in
                    contentHeight = height
                }
                .cancellationAction()
                .confirmationAction("Send", isEnabled: payment.canSend) { dismiss() }
        }
        .presentationDetents(contentHeight.map { [.height($0)] } ?? [.medium])
    }
}
