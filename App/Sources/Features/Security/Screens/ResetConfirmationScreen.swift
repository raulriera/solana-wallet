import SwiftUI

/// Asks for the final confirmation before a reset.
struct ResetConfirmationScreen: View {
    @Environment(\.palette) private var palette
    @State private var isConfirming = false
    let coordinator: SecurityCoordinator

    var body: some View {
        Form {
            Section {
                Button("Reset App", systemImage: "trash", role: .destructive) { isConfirming = true }
                    .labelStyle(.warning)
                    .confirmation("Reset App?", action: "Reset App", isPresented: $isConfirming,
                                  perform: coordinator.reset) {
                        Text("Every wallet, recovery phrase, your RPC API key, custom RPCs, and custom price servers will be deleted from this device. Every window will return to Welcome.")
                    }
            } footer: {
                Text("This can't be undone. Every wallet, recovery phrase, your RPC API key, custom RPCs, and custom price servers will be deleted from this device. Every window will return to Welcome.")
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .navigationTitle("Reset App")
        .toolbarTitleDisplayMode(.inline)
    }
}
