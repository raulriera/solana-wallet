import SwiftUI

/// Shows how a sent payment settled, with a link to its page on Solana Explorer, which also shows its signature, and
/// offers to try a dropped payment again.
struct PaymentResultScreen: View {
    @Environment(\.palette) private var palette
    @AccessibilityFocusState private var isFocused: Bool
    let send: SendModel
    let outcome: SendModel.Outcome

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
            if let submission = send.submission {
                Section {
                    if outcome == .dropped {
                        Button("Try Again", action: send.tryAgain)
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
        .navigationTitle(Text(verbatim: send.recipient.title))
        .navigationBarTitleDisplayMode(.inline)
        // The result replaces the review in place, so VoiceOver moves to it.
        .onChange(of: outcome, initial: true) { isFocused = true }
    }

    /// The result's symbol, title, and explanation.
    private var card: (title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        switch outcome {
        case .succeeded:
            ("Sent",
             LocalizedStringResource("\(send.recipient.title) received \(send.amount.quantity, format: .quantity(of: send.amount.token)).",
                                     comment: "Message after a payment landed. The variables are the recipient's name or short address and the amount with its symbol, such as 0.5 SOL."),
             "checkmark.circle.fill")
        case .failed:
            ("Payment Failed",
             "The network rejected this payment. Its network fee was paid. Nothing else left your wallet.",
             "exclamationmark.triangle.fill")
        case .dropped:
            ("Not Sent", "Nothing left your wallet.", "xmark.circle.fill")
        }
    }
}
