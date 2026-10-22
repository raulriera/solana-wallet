import SwiftUI

/// Runs a deposit's steps while its sheet is open, signals how it settled, and presents failures.
private struct DepositLifecycle: ViewModifier {
    @Bindable var deposit: DepositModel

    func body(content: Content) -> some View {
        let attempt = deposit.attempt
        content
            .task(id: attempt) { await deposit.run(attempt) }
            .sensoryFeedback(trigger: deposit.outcome) { _, outcome in
                switch outcome {
                case .succeeded?: .success
                case .failed?, .dropped?: .error
                case .unconfirmed?, nil: nil
                }
            }
            .errorAlert($deposit.error)
    }
}

extension DepositSheet {
    /// Runs the deposit's steps only while the sheet is open.
    /// - Returns: The sheet with managed steps, outcome feedback, and failure presentation.
    func depositLifecycle() -> some View {
        modifier(DepositLifecycle(deposit: deposit))
    }
}
