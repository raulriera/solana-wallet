import SwiftUI

/// Presents a move's review over its keypad, as tall as its content, and replaces it with the result once the move
/// is sent.
///
/// Cancel returns to the keypad with the amount as typed. Once the move is approved, Cancel closes the keypad too, since
/// the move can't be reviewed again: the shared transactions keep sending and watching it. The result can't be swiped
/// away, and Close closes the keypad too.
struct BalanceMoveReviewSheet: View {
    @Bindable var move: BalanceMoveModel
    /// Closes the keypad's sheet, and this one with it.
    let close: DismissAction
    /// The outcome that shows, which follows the move's in an animated change.
    @State private var shownOutcome: BalanceMoveModel.Outcome?
    /// The review that shows, which stays while the sheet closes after the move drops it.
    @State private var shownReview: BalanceMoveModel.Review?

    var body: some View {
        NavigationStack {
            Group {
                // The review and its result hold little, so the sheet is as tall as each; each measures itself, so
                // the sheet resizes when the result replaces the review.
                if let outcome = shownOutcome {
                    BalanceMoveResultScreen(move: move, outcome: outcome)
                        .contentHeightDetent()
                        .closeAction { close() }
                } else if let review = shownReview {
                    BalanceMoveReviewScreen(move: move, review: review)
                        .contentHeightDetent()
                        .cancellationAction(move.isSending || move.submission != nil ? { close() } : nil)
                }
            }
            // The result blurs in over the review. The sheet jumps to the result's height: a sheet doesn't animate a
            // change of its detent.
            .transition(.blurReplace)
        }
        .limitedTextSize()
        // `animation(_:value:)` doesn't animate this swap, as a probe showed, so the change itself is animated.
        .onChange(of: move.outcome, initial: true) { _, outcome in
            withAnimation { shownOutcome = outcome }
        }
        // Canceling drops the review before the sheet leaves; without its content, the closing sheet would lose its
        // height and go blank.
        .onChange(of: move.review, initial: true) { _, review in
            if let review { shownReview = review }
        }
        // Swiping returns only to the keypad, which an approved move no longer has; Cancel closes both instead.
        .interactiveDismissDisabled(move.isWorking || move.submission != nil)
        // Alerts show from the topmost presentation, so errors while the review shows appear here.
        .errorAlert($move.error)
    }
}
