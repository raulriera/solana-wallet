import SwiftUI

/// A recovery entry that swaps a secure field for one that shows its text, with a button that switches them.
struct RevealableField<Revealed: View, Hidden: View>: View {
    @Environment(\.palette) private var palette
    @Binding private var isRevealed: Bool
    @FocusState.Binding private var focusedField: RecoveryEntryModel.Field?
    private let field: RecoveryEntryModel.Field
    private let revealedField: RecoveryEntryModel.Field
    private let label: LocalizedStringKey
    private let showTitle: LocalizedStringKey
    private let hideTitle: LocalizedStringKey
    private let revealed: Revealed
    private let hidden: Hidden

    /// Creates an entry from its two fields.
    /// - Parameters:
    ///   - isRevealed: Whether the entry shows its text.
    ///   - focusedField: The form's focused field.
    ///   - field: The focus identity of the field currently shown.
    ///   - revealedField: The focus identity of the field that shows the text.
    ///   - label: The name VoiceOver reads for either field.
    ///   - showTitle: The reveal button's name while the text is hidden.
    ///   - hideTitle: The reveal button's name while the text is shown.
    ///   - revealed: The field that shows the text.
    ///   - hidden: The secure field.
    init(isRevealed: Binding<Bool>, focusedField: FocusState<RecoveryEntryModel.Field?>.Binding,
         field: RecoveryEntryModel.Field, revealedField: RecoveryEntryModel.Field, label: LocalizedStringKey,
         showTitle: LocalizedStringKey, hideTitle: LocalizedStringKey,
         @ViewBuilder revealed: () -> Revealed, @ViewBuilder hidden: () -> Hidden) {
        _isRevealed = isRevealed
        _focusedField = focusedField
        self.field = field
        self.revealedField = revealedField
        self.label = label
        self.showTitle = showTitle
        self.hideTitle = hideTitle
        self.revealed = revealed()
        self.hidden = hidden()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Overlapping the fields keeps the text in place while one fades into the other.
            ZStack(alignment: .leading) {
                Group {
                    if isRevealed {
                        revealed
                    } else {
                        hidden
                    }
                }
                .accessibilityLabel(label)
                // Only the text takes the window's text color; the reveal button keeps the tint and its disabled look.
                .foregroundStyle(palette.primaryText)
                .focused($focusedField, equals: field)
                .transition(.opacity)
            }

            RevealButton(isRevealed: isRevealed, showTitle: showTitle, hideTitle: hideTitle, action: toggle)
        }
    }

    /// Switches native controls, keeping focus only when revealing.
    ///
    /// A hidden field that regains focus replaces its text on the next keystroke, so hiding ends editing.
    private func toggle() {
        let wasEditing = focusedField == field
        withAnimation {
            isRevealed.toggle()
            if wasEditing { focusedField = isRevealed ? revealedField : nil }
        }
    }
}
