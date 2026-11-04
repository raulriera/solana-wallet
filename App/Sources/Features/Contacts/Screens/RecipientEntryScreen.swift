import Accessibility
import SwiftUI

/// Pastes an address and names it for a new payment or a contact.
struct RecipientEntryScreen: View {
    @Environment(\.palette) private var palette
    @Bindable var entry: RecipientEntryModel
    let lists: ContactLists

    var body: some View {
        let rejection = entry.rejection
        let warnings = entry.warnings
        Form {
            Section {
                HStack(spacing: 16) {
                    Group {
                        if entry.text.isEmpty {
                            Text("Address")
                                .foregroundStyle(palette.secondaryText)
                        } else {
                            FullAddress(text: entry.text)
                                .foregroundStyle(palette.text)
                                .accessibilityLabel(Text("Address"))
                                .accessibilityValue(Text(entry.text).speechSpellsOutCharacters())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PasteTextButton(paste: paste)
                }

                if let rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
                ForEach(warnings, id: \.self) { warning in
                    RecipientWarningLabel(warning: warning)
                        .transition(.opacity)
                }
            } footer: {
                Text("Copy an address, then paste it here.")
                    .foregroundStyle(palette.secondaryText)
            }

            Section {
                if entry.purpose == .payment, let saved = entry.saved {
                    LabeledContent("Saved As", value: saved.name)
                } else {
                    TextField(text: $entry.name) {
                        Text(entry.purpose.namePlaceholder)
                    }
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit(entry.confirm)
                }
            } footer: {
                if entry.purpose == .payment, entry.saved == nil {
                    Text("Add a name to save this address as a contact.")
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .animation(.default, value: rejection)
        .animation(.default, value: warnings)
        .confirmationAction(entry.purpose.confirmationTitle, isEnabled: entry.canConfirm, action: entry.confirm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text(entry.purpose.title))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: entry.rejectionCount)
        .onChange(of: entry.rejectionCount) {
            guard let rejection = entry.rejection else { return }
            AccessibilityNotification.Announcement(String(localized: rejection.message)).post()
        }
        .onChange(of: warnings) { previous, current in
            let added = current.filter { !previous.contains($0) }.map { String(localized: $0.message) }
            guard !added.isEmpty else { return }
            AccessibilityNotification.Announcement(added.joined(separator: " ")).post()
        }
    }

    /// Checks pasted text with animation.
    ///
    /// - Parameter text: The pasteboard's text.
    private func paste(_ text: String) {
        withAnimation { entry.paste(text, in: lists) }
    }
}
