import SwiftUI

/// Shows how a sent move settled, with a link to its page on Solana Explorer, which also shows its signature, and
/// offers what can follow: trying a dropped move again, or checking one whose watch stopped.
struct BalanceMoveResultScreen: View {
    @Environment(\.palette) private var palette
    @AccessibilityFocusState private var isFocused: Bool
    let move: BalanceMoveModel
    let outcome: BalanceMoveModel.Outcome

    var body: some View {
        let card = card
        Form {
            Section {
                TitleCardContent(title: card.title, message: card.message, systemImage: card.systemImage)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($isFocused)
            }
            .listRowBackground(palette.surface)

            Section {
                switch outcome {
                case .dropped:
                    Button("Try Again", action: move.tryAgain)
                case .unconfirmed:
                    Button(action: move.checkAgain) {
                        HStack {
                            Text("Check Again")
                            Spacer()
                            if move.isChecking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(move.isChecking)
                case .succeeded, .failed:
                    EmptyView()
                }
                if let submission = move.submission, outcome != .dropped {
                    Link("View in Explorer", destination: submission.explorerURL)
                }
            }
            .foregroundStyle(palette.accent)
            .listRowBackground(palette.surface)
        }
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle(Text(move.direction.title))
        .navigationBarTitleDisplayMode(.inline)
        // The result replaces the review in place, and checking again can change it, so VoiceOver moves to it.
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation, for the move's direction.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        let amount = move.payment.quantity
        let token = move.payment.token
        switch (move.direction, outcome) {
        case (.toPrivate, .succeeded):
            return ("SOL Is Private",
                    LocalizedStringResource("\(amount, format: .quantity(of: token)) is pending. It becomes available when the network reports it, usually within a minute.",
                                            comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
                    // The symbol matches the private-balance sign on SOL's card.
                    "eye.slash.circle.fill")
        case (.toPublic, .succeeded):
            // A spent note's change returns to the private balance, pending until the network reports it.
            let message: LocalizedStringResource = if case .balance(_, let pending)? = move.status, pending > 0 {
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
        case (_, .unconfirmed):
            return ("Couldn't Check Transaction",
                    "The transaction was sent, but the selected provider stopped answering. Check it again, or view it in Explorer.",
                    "exclamationmark.circle.fill")
        }
    }
}
