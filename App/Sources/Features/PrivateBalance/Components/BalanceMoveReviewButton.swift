import SwiftUI

/// Reviews the typed amount once it can be added, also with Return on a hardware keyboard; it shows a spinner and
/// stays disabled while the move is prepared.
///
/// It reads the move itself, so key presses update only this button.
struct BalanceMoveReviewButton: View {
    @Environment(\.reviewMove) private var reviewMove
    /// The move whose progress and typed amount the button shows; ``BalanceMoveReviewAction`` starts its review.
    let move: BalanceMoveModel

    var body: some View {
        Button {
            reviewMove?()
        } label: {
            // The title keeps its place under the spinner, so the button never changes size.
            Text("Review")
                .opacity(move.isWorking ? 0 : 1)
                .overlay {
                    if move.isWorking {
                        // The button is gray while it works, so the spinner is gray too, at the size of the text.
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.secondary)
                    }
                }
        }
        .buttonStyle(.glassPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(!move.payment.canSend || move.isWorking)
    }
}
