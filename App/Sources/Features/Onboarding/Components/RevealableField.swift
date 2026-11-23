import SwiftUI

/// A recovery field that switches between a secure field and one that shows its text.
struct RevealableField<Revealed: View, Hidden: View>: View {
    @Binding private var isRevealed: Bool
    @FocusState.Binding private var focusedField: RecoveryEntryModel.Field?
    private let field: RecoveryEntryModel.Field
    private let revealedField: RecoveryEntryModel.Field
    private let label: LocalizedStringKey
    private let showTitle: LocalizedStringKey
    private let hideTitle: LocalizedStringKey
    private let revealed: Revealed
    private let hidden: Hidden

    /// Creates a field from its revealed and hidden versions.
    ///
    /// - Parameters:
    ///   - isRevealed: Whether the field shows its text.
    ///   - focusedField: The form's focused field.
    ///   - field: The focus identity of the visible field.
    ///   - revealedField: The focus identity of the field that shows the text.
    ///   - label: The accessibility label of both fields.
    ///   - showTitle: The reveal button's title while the text is hidden.
    ///   - hideTitle: The reveal button's title while the text is shown.
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
            ZStack(alignment: .leading) {
                Group {
                    if isRevealed {
                        revealed
                    } else {
                        hidden
                    }
                }
                .accessibilityLabel(label)
                .focused($focusedField, equals: field)
                .transition(.opacity)
            }

            RevealButton(isRevealed: isRevealed, showTitle: showTitle, hideTitle: hideTitle, action: toggle)
        }
    }

    /// Shows or hides the text, keeping focus only when it shows the text.
    private func toggle() {
        let wasEditing = focusedField == field
        withAnimation {
            isRevealed.toggle()
            if wasEditing { focusedField = isRevealed ? revealedField : nil }
        }
    }
}
