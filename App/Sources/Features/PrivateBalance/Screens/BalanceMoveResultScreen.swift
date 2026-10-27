import SwiftUI

/// Shows how a sent move settled, with a link to its page on Solana Explorer, which also shows its signature, and
/// offers to try a dropped move again.
struct BalanceMoveResultScreen: TransactionResultContent {
    @Environment(\.palette) private var palette
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
            .listRowBackground(palette.surface)

            // Every outcome links to its page on Solana Explorer, so the person can check it themselves.
            if let submission = review.submission {
                Section {
                    if outcome == .dropped {
                        Button("Try Again", action: review.tryAgain)
                    }
                    Link("View in Explorer", destination: submission.explorerURL)
                }
                .foregroundStyle(palette.accent)
                .listRowBackground(palette.surface)
            }
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(Text(review.proposal.direction.title))
        .navigationBarTitleDisplayMode(.inline)
        // The result replaces the review in place, so VoiceOver moves to it.
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation, for the move's direction.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let move = review.proposal
        let amount = move.amount.quantity
        let token = move.amount.token
        switch (move.direction, outcome) {
        case (.toPrivate, .succeeded):
            return ("SOL Is Private",
                    LocalizedStringResource("\(amount, format: .quantity(of: token)) is pending. It becomes available when the network reports it, usually within a minute.",
                                            comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
                    // The symbol matches the private-balance sign on SOL's card.
                    "eye.slash.circle.fill")
        case (.toPublic, .succeeded):
            // The spent notes' change returns to the private balance, pending until the network reports it.
            let message: LocalizedStringResource = if review.review?.pendingChange != nil {
                LocalizedStringResource("\(amount, format: .quantity(of: token)) is in your public balance. The rest of your private balance becomes available within a minute.",
                                        comment: "Message after private SOL moved to the public balance, when the rest of the private balance is pending. The variable is the amount with its symbol, such as 0.5 SOL.")
            } else {
                LocalizedStringResource("\(amount, format: .quantity(of: token)) is in your public balance.",
                                        comment: "Message after private SOL moved to the public balance. The variable is the amount with its symbol, such as 0.5 SOL.")
            }
            // The symbol matches Make SOL Public on SOL's details.
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
