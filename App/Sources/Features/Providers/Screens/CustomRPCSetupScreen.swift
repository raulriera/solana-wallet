import SwiftUI

/// Collects a custom RPC URL; the owning scene checks it, then adds it and chooses it for every window.
struct CustomRPCSetupScreen: View {
    @Environment(\.palette) private var palette
    @State private var input = ProviderInput()
    @State private var contentInset = LayoutMetrics.contentMargin
    @FocusState private var isURLFocused: Bool
    /// Checks the submitted URL, reports why it was refused, and saves it.
    let submission: any ProviderSubmitting<CustomRPCError>

    var body: some View {
        Form {
            Section {
                ProviderEntry(input: input, isFocused: $isURLFocused) { text in
                    TextField("RPC URL", text: text)
                        .accessibilityLabel("RPC URL")
                        .keyboardType(.URL)
                        .textContentType(.URL)
                }
                .disabled(submission.isPending)

                if let rejection = submission.rejection {
                    Label(rejection.message, systemImage: "exclamationmark.circle.fill")
                        .labelStyle(.warning)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            } header: {
                Text("URL")
                    .foregroundStyle(palette.secondaryText)
            } footer: {
                Text("Use your RPC's HTTPS URL. It must support live updates at the same URL. The URL stays on this device and is sent only to that RPC.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .writingToolsBehavior(.disabled)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Add RPC", action: submitURL)
                .buttonStyle(.primary(isPending: submission.isPending))
                .disabled(!input.hasText || submission.isPending)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Add Custom RPC")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Dismisses the keyboard so the result stays visible, then hands the URL to the scene.
    private func submitURL() {
        isURLFocused = false
        submission.submit(input.text)
    }
}

#Preview("Empty") {
    NavigationStack {
        CustomRPCSetupScreen(submission: PreviewURLSubmission(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

#Preview("No live updates") {
    NavigationStack {
        CustomRPCSetupScreen(submission: PreviewURLSubmission(rejection: .noLiveUpdates))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).accent)
}

/// Keeps previews local, showing a fixed rejection without checking or saving a URL.
private struct PreviewURLSubmission: ProviderSubmitting {
    let rejection: CustomRPCError?
    var isPending: Bool { false }

    /// Accepts preview interaction without checking or retaining the URL.
    /// - Parameter entry: The preview's URL.
    func submit(_ entry: String) {}
}
