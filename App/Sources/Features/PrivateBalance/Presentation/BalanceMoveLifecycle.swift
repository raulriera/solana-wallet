import SwiftUI

/// Runs a move's steps while its sheet is open, signals how it settled, and presents failures.
private struct BalanceMoveLifecycle: ViewModifier {
    @Bindable var move: BalanceMoveModel

    func body(content: Content) -> some View {
        let attempt = move.attempt
        content
            .task(id: attempt) { await move.run(attempt) }
            .sensoryFeedback(trigger: move.outcome) { _, outcome in
                switch outcome {
                case .succeeded?: .success
                case .failed?, .dropped?: .error
                case .unconfirmed?, nil: nil
                }
            }
            .errorAlert($move.error)
    }
}

extension BalanceMoveSheet {
    /// Runs the move's steps only while the sheet is open.
    /// - Returns: The sheet with managed steps, outcome feedback, and failure presentation.
    func balanceMoveLifecycle() -> some View {
        modifier(BalanceMoveLifecycle(move: move))
    }
}
