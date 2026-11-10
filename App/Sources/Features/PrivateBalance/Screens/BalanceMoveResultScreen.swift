import SwiftUI

/// Shows how a sent balance move settled, with its explorer link, a retry for a dropped move, and a way to close it.
struct BalanceMoveResultScreen: TransactionResultContent {
    @Environment(\.palette) private var palette
    @Environment(\.dismissParentContainer) private var dismissParentContainer
    @AccessibilityFocusState private var isFocused: Bool
    let review: TransactionReviewModel<BalanceMoveProposal>
    let outcome: TransactionOutcome

    var body: some View {
        let card = card
        Form {
            Section {
                TitleCardContent(title: card.title, message: card.message, systemImage: card.systemImage)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($isFocused)
            }

            Section {
                if let submission = review.submission {
                    if outcome == .dropped {
                        Button("Try Again", action: review.tryAgain)
                    }
                    Link("View in Explorer", destination: submission.explorerURL)
                }
                if let dismissParentContainer {
                    Button("Done") { dismissParentContainer() }
                }
            }
            .foregroundStyle(palette.primary)
            .lineLimit(1)
        }
        .navigationTitle(Text(review.proposal.direction.title))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's title, message, and symbol.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let move = review.proposal
        let amount = move.amount.quantity
        let token = move.amount.token
        switch (move.direction, outcome) {
        case (.toPrivate, .succeeded):
            return ("SOL Is Private",
                    LocalizedStringResource("\(amount, format: .quantity(of: token)) is pending. It becomes available when the network reports it, usually within a minute.",
                                            comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
                    "eye.slash.circle.fill")
        case (.toPublic, .succeeded):
            let message: LocalizedStringResource = if review.review?.pendingChange != nil {
                LocalizedStringResource("\(amount, format: .quantity(of: token)) is in your public balance. The rest of your private balance becomes available within a minute.",
                                        comment: "Message after private SOL moved to the public balance, when the rest of the private balance is pending. The variable is the amount with its symbol, such as 0.5 SOL.")
            } else {
                LocalizedStringResource("\(amount, format: .quantity(of: token)) is in your public balance.",
                                        comment: "Message after private SOL moved to the public balance. The variable is the amount with its symbol, such as 0.5 SOL.")
            }
            return ("SOL Is Public", message, "eye.circle.fill")
        case (.toPrivate, .failed):
            return ("Transaction Failed",
                    "The network rejected this transaction. Its network fee was paid. Nothing was added to your private balance.",
                    "exclamationmark.triangle.fill")
        case (.toPublic, .failed):
            return ("Transaction Failed",
                    "The network rejected this transaction. Its network fee was paid. Nothing left your private balance.",
                    "exclamationmark.triangle.fill")
        case (.toPrivate, .dropped):
            return ("Not Sent", "Nothing left your public balance.", "xmark.circle.fill")
        case (.toPublic, .dropped):
            return ("Not Sent", "Nothing left your private balance.", "xmark.circle.fill")
        }
    }
}
