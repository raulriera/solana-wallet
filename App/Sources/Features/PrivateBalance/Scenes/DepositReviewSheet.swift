import SwiftUI

/// Presents a deposit's review over its keypad, as tall as its content, and replaces it with the result once the
/// deposit is sent.
///
/// Cancel returns to the keypad with the amount as typed, except while the deposit is sent; the result can't be
/// swiped away, and Close closes the keypad too.
struct DepositReviewSheet: View {
    @Bindable var deposit: DepositModel
    /// Closes the keypad's sheet, and this one with it.
    let close: DismissAction
    /// The outcome that shows, which follows the deposit's in an animated change.
    @State private var shownOutcome: DepositModel.Outcome?
    /// The review that shows, which stays while the sheet closes after the deposit drops it.
    @State private var shownReview: DepositModel.Review?

    var body: some View {
        NavigationStack {
            Group {
                // The review and its result hold little, so the sheet is as tall as each; each measures itself, so
                // the sheet resizes when the result replaces the review.
                if let outcome = shownOutcome {
                    DepositResultScreen(deposit: deposit, outcome: outcome)
                        .contentHeightDetent()
                        .closeAction { close() }
                } else if let review = shownReview {
                    DepositReviewScreen(deposit: deposit, review: review)
                        .contentHeightDetent()
                        .cancellationAction()
                        .disabled(deposit.isSending)
                }
            }
            // The result blurs in over the review. The sheet jumps to the result's height: a sheet doesn't animate a
            // change of its detent.
            .transition(.blurReplace)
        }
        // `animation(_:value:)` doesn't animate this swap, as a probe showed, so the change itself is animated.
        .onChange(of: deposit.outcome, initial: true) { _, outcome in
            withAnimation { shownOutcome = outcome }
        }
        // Canceling drops the review before the sheet leaves; without its content, the closing sheet would lose its
        // height and go blank.
        .onChange(of: deposit.review, initial: true) { _, review in
            if let review { shownReview = review }
        }
        .interactiveDismissDisabled(deposit.isWorking || deposit.submission != nil)
        // Alerts show from the topmost presentation, so errors while the review shows appear here.
        .errorAlert($deposit.error)
    }
}
