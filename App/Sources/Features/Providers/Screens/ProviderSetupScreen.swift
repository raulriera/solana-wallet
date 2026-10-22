import SwiftUI

/// Collects an entry for an RPC provider, Helius's API key or a custom RPC URL; the owning scene checks and saves it.
struct ProviderSetupScreen<Submission: ProviderSubmitting>: View {
    @Environment(\.palette) private var palette
    @State private var input = ProviderEntryModel()
    @FocusState private var isFocused: Bool
    /// Why the screen asks for an entry, which sets its field and wording.
    let purpose: ProviderEntryPurpose
    /// Checks the submitted entry and reports why the provider rejected it.
    let submission: Submission

    var body: some View {
        Form {
            // Settings shows title cards only on its root screens, so the pushed entry screens get none.
            if purpose == .connect {
                Section {
                    TitleCardContent(
                        title: "Connect to Helius",
                        message: "This wallet connects directly to Solana through Helius. Enter your Helius API key to load your balances.",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                }
                .listRowBackground(palette.surface)
            }

            Section {
                ProviderEntry(input: input, isFocused: $isFocused) { text in
                    if purpose == .customRPC {
                        TextField("RPC URL", text: text)
                            .accessibilityLabel("RPC URL")
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .writingToolsBehavior(.disabled)
                    } else {
                        SecureField("RPC API key", text: text)
                            .accessibilityLabel("RPC API key")
                    }
                }
                .disabled(submission.isPending)

                if let rejection = submission.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } header: {
                Text(purpose.header)
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(purpose.footer)
                        .foregroundStyle(palette.secondaryText)
                    if purpose != .customRPC {
                        Link("Get an API key from Helius", destination: URL(string: "https://dashboard.helius.dev")!)
                    }
                }
                .font(.footnote)
            }
            .listRowBackground(palette.surface)
        }
        .animation(.default, value: submission.rejection)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .confirmationAction(purpose.action, isEnabled: input.hasText, isPending: submission.isPending,
                            action: submitEntry)
        .background(palette.background)
        .navigationTitle(Text(purpose.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard so the result stays visible, then hands the entry to the scene.
    private func submitEntry() {
        isFocused = false
        submission.submit(input.text)
    }
}

#Preview("Empty") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Rejected key") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewSubmission(rejection: ProviderConnectionError.invalidKey))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Add") {
    NavigationStack {
        ProviderSetupScreen(purpose: .add, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Change") {
    NavigationStack {
        ProviderSetupScreen(purpose: .change, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Add Custom RPC") {
    NavigationStack {
        ProviderSetupScreen(purpose: .customRPC, submission: PreviewSubmission<CustomRPCError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("No live updates") {
    NavigationStack {
        ProviderSetupScreen(purpose: .customRPC, submission: PreviewSubmission(rejection: CustomRPCError.noLiveUpdates))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

/// Keeps previews local, showing a fixed rejection without checking or saving an entry.
private struct PreviewSubmission<EntryError: ProviderEntryError>: ProviderSubmitting {
    let rejection: EntryError?
    var isPending: Bool { false }

    /// Accepts preview interaction without checking or retaining the entry.
    /// - Parameter entry: The preview's entry.
    func submit(_ entry: String) {}
}
