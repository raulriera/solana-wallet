import SwiftUI

/// Collects the RPC provider's API key; the owning scene checks and saves it.
struct ProviderSetupScreen: View {
    /// Why the screen asks for a key, which sets its wording.
    enum Purpose {
        /// A first key, which connects the provider.
        case connect
        /// A first key added from Helius's details, which leaves the provider in use as it is.
        case add
        /// A new key, which replaces the saved key once it's checked.
        case change
    }

    @Environment(\.palette) private var palette
    @State private var input = ProviderInput()
    @State private var contentInset = LayoutMetrics.contentMargin
    @FocusState private var isKeyFocused: Bool
    /// Why the screen asks for a key.
    let purpose: Purpose
    /// Checks the submitted key and reports why Helius refused it.
    let submission: any ProviderSubmitting<ProviderConnectionError>

    var body: some View {
        Form {
            // Settings shows title cards only on its root screens, so the pushed Add and Change screens get none.
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
                ProviderEntry(input: input, isFocused: $isKeyFocused) { text in
                    SecureField("RPC API key", text: text)
                        .accessibilityLabel("RPC API key")
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
                    Link("Get an API key from Helius", destination: URL(string: "https://dashboard.helius.dev")!)
                }
                .font(.footnote)
            }
            .listRowBackground(palette.surface)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button(purpose.action, action: submitKey)
                .buttonStyle(.primary(isPending: submission.isPending))
                .disabled(!input.hasText || submission.isPending)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle(Text(purpose.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard so the result stays visible, then hands the key to the scene.
    private func submitKey() {
        isKeyFocused = false
        submission.submit(input.text)
    }
}

extension ProviderSetupScreen.Purpose {
    /// The screen's title.
    var title: LocalizedStringResource {
        switch self {
        case .connect: "Connect to Helius"
        case .add: "Add API Key"
        case .change: "Change API Key"
        }
    }

    /// The key section's header.
    var header: LocalizedStringResource {
        switch self {
        case .connect, .add: "API Key"
        case .change: "New API Key"
        }
    }

    /// The key section's footer, which says where the key goes.
    var footer: LocalizedStringResource {
        switch self {
        case .connect: "Your key is stored only on this device and is sent only to Helius."
        case .add: "Your key is stored only on this device and is sent only to this provider."
        case .change:
            "The saved key stays until the new key is checked. Your key is stored only on this device and is sent only to this provider."
        }
    }

    /// The title of the action that checks and saves the key.
    var action: LocalizedStringResource {
        switch self {
        case .connect: "Continue"
        case .add, .change: "Save"
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewKeySubmission(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Rejected key") {
    NavigationStack {
        ProviderSetupScreen(purpose: .connect, submission: PreviewKeySubmission(rejection: .invalidKey))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Add") {
    NavigationStack {
        ProviderSetupScreen(purpose: .add, submission: PreviewKeySubmission(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("Change") {
    NavigationStack {
        ProviderSetupScreen(purpose: .change, submission: PreviewKeySubmission(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

/// Keeps previews local, showing a fixed rejection without checking or saving a key.
private struct PreviewKeySubmission: ProviderSubmitting {
    let rejection: ProviderConnectionError?
    var isPending: Bool { false }

    /// Accepts preview interaction without checking or retaining the key.
    /// - Parameter entry: The preview's key.
    func submit(_ entry: String) {}
}
