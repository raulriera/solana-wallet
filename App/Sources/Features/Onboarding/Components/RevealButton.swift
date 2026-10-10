import SwiftUI

/// Shows or hides a recovery field's text with an eye icon on the trailing side of the field.
struct RevealButton: View {
    @Environment(\.palette) private var palette
    /// Whether the field currently shows its text.
    let isRevealed: Bool
    /// The button's name while the text is hidden.
    let showTitle: LocalizedStringKey
    /// The button's name while the text is shown.
    let hideTitle: LocalizedStringKey
    /// Switches the field between hidden and shown.
    let action: () -> Void

    var body: some View {
        Button(isRevealed ? hideTitle : showTitle, systemImage: isRevealed ? "eye.slash" : "eye", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(palette.accent)
            .contentTransition(.symbolEffect(.replace))
    }
}
