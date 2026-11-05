import SwiftUI

/// A form that collects a provider entry, shows why it was rejected, and submits it from the top toolbar.
struct ProviderEntryForm<Submission: ProviderSubmitting, Intro: View, Help: View>: View {
    @Environment(\.palette) private var palette
    @State private var input = ProviderEntryModel()
    @FocusState private var isFocused: Bool
    let title: LocalizedStringResource
    let label: LocalizedStringResource
    let kind: ProviderEntry.Kind
    let header: LocalizedStringResource
    let footer: LocalizedStringResource
    /// The title of the action that checks and saves the entry.
    let action: LocalizedStringResource
    let submission: Submission
    /// The sections above the entry.
    @ViewBuilder let intro: Intro
    /// The views below the entry's footer.
    @ViewBuilder let help: Help

    var body: some View {
        Form {
            intro

            Section {
                ProviderEntry(text: $input.text, isFocused: $isFocused, label: label, kind: kind)
                    .disabled(submission.isPending)

                if let rejection = submission.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } header: {
                Text(header)
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(footer)
                        .foregroundStyle(palette.secondaryText)
                    help
                }
                .font(.footnote)
            }
        }
        .animation(.default, value: submission.rejection)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .confirmationAction(action, isEnabled: input.hasText, isPending: submission.isPending, action: submitEntry)
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard and submits the entry.
    private func submitEntry() {
        isFocused = false
        submission.submit(input.text)
    }
}
