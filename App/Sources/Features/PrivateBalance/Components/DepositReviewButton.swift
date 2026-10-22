import SwiftUI

/// Reviews the typed amount once it can be added, also with Return on a hardware keyboard; it shows a spinner and
/// stays disabled while the deposit is prepared.
///
/// It reads the deposit itself, so key presses update only this button.
struct DepositReviewButton: View {
    let deposit: DepositModel

    var body: some View {
        Button(action: deposit.prepareReview) {
            // The title keeps its place under the spinner, so the button never changes size.
            Text("Review")
                .opacity(deposit.isWorking ? 0 : 1)
                .overlay {
                    if deposit.isWorking {
                        // The button is gray while it works, so the spinner is gray too, at the size of the text.
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.secondary)
                    }
                }
        }
        .buttonStyle(.glassPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(!deposit.payment.canSend || deposit.isWorking)
    }
}
