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
        .navigationTitle(Text(review.proposal.title))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's title, message, and symbol.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let move = review.proposal
        let sent = move.sent
        let asset = move.asset
        switch (move.direction, outcome) {
        case (.toPrivate, .succeeded):
            let title = LocalizedStringResource(
                "\(asset.displaySymbol) Is Private",
                comment: "Title after a deposit into the private balance succeeded. The variable is the token's symbol, such as SOL or USDC."
            )
            return (title,
                    LocalizedStringResource("\(sent, format: .amount(of: asset)) is pending. It becomes available when the network reports it, usually within a minute.",
                                            comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
                    "checkmark.shield.fill")
        case (.toPublic, .succeeded):
            let message: LocalizedStringResource = if review.review?.pendingChange != nil {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in your public balance. The rest of your private balance becomes available within a minute.",
                                        comment: "Message after a private token moved to the public balance, when the rest of the private balance is pending. The variable is the amount with its symbol, such as 0.5 SOL.")
            } else {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in your public balance.",
                                        comment: "Message after a private token moved to the public balance. The variable is the amount with its symbol, such as 0.5 SOL.")
            }
            let title = LocalizedStringResource(
                "\(asset.displaySymbol) Is Public",
                comment: "Title after a private token moved to the public balance. The variable is the token's symbol, such as SOL or USDC."
            )
            return (title, message, "checkmark.circle.fill")
        case (.toRecipient(let recipient, _), .succeeded):
            let message: LocalizedStringResource = if review.review?.pendingChange != nil {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in \(recipient.title)'s private balance. The rest of your private balance becomes available within a minute.",
                                        comment: "Message after a private token was sent to another person's private balance, when the rest of the private balance is pending. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address.")
            } else {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in \(recipient.title)'s private balance.",
                                        comment: "Message after a private token was sent to another person's private balance. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address.")
            }
            return ("Sent Privately", message, "checkmark.shield.fill")
        case (_, .failed):
            return ("Transaction Failed",
                    move.direction.source == .publicBalance
                        ? "The network rejected this transaction. Its network fee was paid. Nothing was added to your private balance."
                        : "The network rejected this transaction. Its network fee was paid. Nothing left your private balance.",
                    "exclamationmark.triangle.fill")
        case (_, .dropped):
            return ("Not Sent",
                    move.direction.source == .publicBalance
                        ? "Nothing left your public balance."
                        : "Nothing left your private balance.",
                    "xmark.circle.fill")
        }
    }
}
