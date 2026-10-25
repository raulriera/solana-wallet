import SwiftUI

/// Runs a payment's steps while its review shows, signals how it settled, and presents failures.
private struct SendLifecycle: ViewModifier {
    @Bindable var send: SendModel

    func body(content: Content) -> some View {
        let attempt = send.attempt
        content
            .task(id: attempt) { await send.run(attempt) }
            .sensoryFeedback(trigger: send.outcome) { _, outcome in
                switch outcome {
                case .succeeded?: .success
                case .failed?, .dropped?: .error
                case nil: nil
                }
            }
            // Alerts show from the topmost presentation, so errors while the review shows appear over it.
            .errorAlert($send.error) { error in
                if error == .watchStopped {
                    Button("Check Again", action: send.retry)
                } else if error.canRetry {
                    Button("Try Again", action: send.retry)
                }
                Button(error.canRetry ? "Cancel" : "OK", role: .cancel) {}
            }
    }
}

extension PaymentReviewSheet {
    /// Runs the payment's steps only while its review shows.
    /// - Returns: The sheet with managed steps, outcome haptics, and failure presentation.
    func sendLifecycle() -> some View {
        modifier(SendLifecycle(send: send))
    }
}
