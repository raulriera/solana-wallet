import SwiftUI

/// Shows a sent balance move's outcome, with its explorer link, a retry for a dropped move, and, once the move settles
/// or its check stops, a way to close it.
struct BalanceMoveResultScreen: TransactionResultContent {
    @Environment(\.dismissParentContainer) private var dismissParentContainer
    @AccessibilityFocusState private var isFocused: Bool
    let review: TransactionReviewModel<BalanceMoveProposal>
    let outcome: TransactionOutcome

    var body: some View {
        let card = card
        Form {
            Section {
                TitleCardContent(title: card.title, message: card.message, systemImage: card.systemImage)
                    .symbolEffect(.breathe, isActive: review.isSending)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($isFocused)
            }

            Section {
                if outcome.status == .dropped {
                    Button("Try Again", action: review.tryAgain)
                }
                Link("View in Explorer", destination: outcome.explorerURL)
                if let dismissParentContainer, !review.isSending {
                    Button("Done") { dismissParentContainer() }
                }
            }
            .lineLimit(1)
        }
        .navigationTitle(Text(review.proposal.title))
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    private var card: TransactionResultCard {
        let move = review.proposal
        let sent = move.sent
        let asset = move.asset
        switch (move.direction, outcome.status) {
        case (_, .pending):
            return .pending(review.confirmationError)
        case (.toPrivate, .succeeded):
            let title = LocalizedStringResource(
                "\(asset.displaySymbol) Is Private",
                comment: "Title after a deposit into the private balance succeeded. The variable is the token's symbol, such as SOL or USDC."
            )
            return TransactionResultCard(
                title: title,
                message: LocalizedStringResource("\(sent, format: .amount(of: asset)) is pending. It becomes available when the network reports it, usually within a minute.",
                                                 comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
                systemImage: "checkmark.shield.fill")
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
            return TransactionResultCard(
                title: title,
                message: message,
                systemImage: "checkmark.circle.fill")
        case (.toRecipient(let recipient, _), .succeeded):
            let message: LocalizedStringResource = if review.review?.pendingChange != nil {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in \(recipient.title)'s private balance. The rest of your private balance becomes available within a minute.",
                                        comment: "Message after a private token was sent to another person's private balance, when the rest of the private balance is pending. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address.")
            } else {
                LocalizedStringResource("\(sent, format: .amount(of: asset)) is in \(recipient.title)'s private balance.",
                                        comment: "Message after a private token was sent to another person's private balance. The variables are the amount with its symbol, such as 0.5 SOL, and the recipient's name or short address.")
            }
            return TransactionResultCard(
                title: "Sent Privately",
                message: message,
                systemImage: "checkmark.shield.fill")
        case (_, .failed):
            return .failed(title: "Transaction Failed",
                           message: move.direction.source == .publicBalance
                               ? "The network rejected this transaction. Its network fee was paid. Nothing was added to your private balance."
                               : "The network rejected this transaction. Its network fee was paid. Nothing left your private balance.")
        case (_, .dropped):
            return .dropped(message: move.direction.source == .publicBalance
                                ? "Nothing left your public balance."
                                : "Nothing left your private balance.")
        }
    }
}
