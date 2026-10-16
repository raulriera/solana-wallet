import SwiftUI

/// Asks for the final confirmation before the reset; every window then returns to onboarding.
struct ResetConfirmationScreen: View {
    @Environment(\.palette) private var palette
    @State private var isConfirming = false
    let coordinator: SecurityCoordinator

    var body: some View {
        Form {
            Section {
                Button("Reset App", systemImage: "trash", role: .destructive) { isConfirming = true }
                    .labelStyle(.warning)
            } footer: {
                Text("This can't be undone. Every wallet, recovery phrase, your RPC API key, and custom RPCs will be deleted from this device. Every window will return to Welcome.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
        .navigationTitle("Reset App")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset App?", isPresented: $isConfirming) {
            Button("Reset App", role: .destructive) { coordinator.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every wallet, recovery phrase, your RPC API key, and custom RPCs will be deleted from this device. Every window will return to Welcome.")
        }
    }
}
