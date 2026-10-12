import SwiftUI

/// Asks for the final confirmation before the reset; every window then returns to onboarding.
struct ResetConfirmationScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    @State private var isConfirming = false
    let flow: SecurityFlow

    var body: some View {
        Form {
            Section {} footer: {
                Text("This can't be undone. Every wallet, recovery phrase, your RPC API key, and custom RPCs will be deleted from this device. Every window will return to Welcome.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .readableContentMargins(inset: $contentInset)
        .pinnedAction(inset: contentInset) {
            Button("Reset App", role: .destructive) { isConfirming = true }
                .buttonStyle(.destructive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .navigationTitle("Reset App")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset App?", isPresented: $isConfirming) {
            Button("Reset App", role: .destructive) { flow.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every wallet, recovery phrase, your RPC API key, and custom RPCs will be deleted from this device. Every window will return to Welcome.")
        }
    }
}
