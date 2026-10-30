import SwiftUI

/// A button that shows or hides a recovery field's text.
struct RevealButton: View {
    let isRevealed: Bool
    let showTitle: LocalizedStringKey
    let hideTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(isRevealed ? hideTitle : showTitle, systemImage: isRevealed ? "eye.slash" : "eye", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .contentTransition(.symbolEffect(.replace))
    }
}
