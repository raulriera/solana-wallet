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
        .navigationTitle("Add to Private Balance")
        .navigationBarTitleDisplayMode(.inline)
        // The result replaces the review in place, and checking again can change it, so VoiceOver moves to it.
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        switch outcome {
        case .succeeded:
            ("Added to Private Balance",
             LocalizedStringResource("\(move.payment.quantity, format: .quantity(of: move.payment.token)) is pending. It becomes available when the network reports it, usually within a minute.",
                                     comment: "Message after a deposit into the private balance succeeded. The variable is the amount with its symbol, such as 0.5 SOL."),
             // The symbol matches the private-balance sign on SOL's card.
             "eye.slash.circle.fill")
        case .failed:
            ("Transaction Failed",
             "The network rejected this transaction. Its network fee was paid. Nothing was added to your private balance.",
             "exclamationmark.triangle.fill")
        case .dropped:
            ("Not Added", "Nothing left your public balance.", "xmark.circle.fill")
        case .unconfirmed:
            ("Couldn't Check Transaction",
             "The transaction was sent, but the selected provider stopped answering. Check it again, or view it in Explorer.",
             "exclamationmark.circle.fill")
        }
    }
}
