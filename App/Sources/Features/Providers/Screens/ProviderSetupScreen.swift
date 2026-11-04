import SwiftUI

/// Collects an entry for an RPC provider, such as Helius's API key or a custom RPC URL.
struct ProviderSetupScreen<Submission: ProviderSubmitting>: View {
    @Environment(\.palette) private var palette
    @State private var input = ProviderEntryModel()
    @FocusState private var isFocused: Bool
    let purpose: ProviderEntryPurpose
    let submission: Submission

    var body: some View {
        Form {
            if purpose == .connect {
                Section {
                    TitleCardContent(
                        title: "Connect to Helius",
                        message: "This wallet connects directly to Solana through Helius. Enter your Helius API key to load your balances.",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                }
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
                        // swift-format-ignore: NeverForceUnwrap
                        Link("Get an API key from Helius", destination: URL(string: "https://dashboard.helius.dev")!)
                    }
                }
                .font(.footnote)
            }
        }
        .animation(.default, value: submission.rejection)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .confirmationAction(purpose.action, isEnabled: input.hasText, isPending: submission.isPending,
                            action: submitEntry)
        .navigationTitle(Text(purpose.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard and submits the entry.
    private func submitEntry() {
        isFocused = false
        submission.submit(input.text)
    }
}

#Preview("Empty") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Rejected key") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewSubmission(rejection: ProviderConnectionError.invalidKey))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Add") {
    NavigationStack {
        ProviderSetupScreen(purpose: .add, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Change") {
    NavigationStack {
        ProviderSetupScreen(purpose: .change, submission: PreviewSubmission<ProviderConnectionError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Add Custom RPC") {
    NavigationStack {
        ProviderSetupScreen(purpose: .customRPC, submission: PreviewSubmission<CustomRPCError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("No live updates") {
    NavigationStack {
        ProviderSetupScreen(purpose: .customRPC, submission: PreviewSubmission(rejection: CustomRPCError.noLiveUpdates))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

/// A submission for previews that shows a fixed rejection.
private struct PreviewSubmission<EntryError: ProviderEntryError>: ProviderSubmitting {
    let rejection: EntryError?
    var isPending: Bool { false }

    func submit(_ entry: String) {}
}
