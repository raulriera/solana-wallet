import SwiftUI

/// Asks for the final confirmation before the reset; every window then returns to onboarding.
struct ResetConfirmationScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    @State private var isConfirming = false
    let flow: SecurityFlow

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Reset This Device?",
                    message: "This can't be undone. Every wallet, recovery phrase, and your RPC API key will be deleted from this device.",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Reset App", role: .destructive) { isConfirming = true }
                .buttonStyle(.destructive)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Reset App")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset App?", isPresented: $isConfirming) {
            Button("Reset App", role: .destructive) { flow.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every wallet, recovery phrase, and your RPC API key will be deleted from this device.")
        }
    }
}
