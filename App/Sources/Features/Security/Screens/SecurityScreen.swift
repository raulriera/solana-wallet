import SwiftUI

/// Explains what stays on this device and offers the wallet's backup and the app reset.
struct SecurityScreen: View {
    @Environment(\.palette) private var palette
    let coordinator: SecurityCoordinator
    let account: Account

    var body: some View {
        Form {
            Section {
                TitleCardContent(
                    title: "Security & Privacy",
                    message: "Your wallets and recovery phrase stay on this device. They are not in iCloud or in device backups.",
                    systemImage: "hand.raised.fill"
                )
            }
            .listRowBackground(palette.surface)

            Section {
                Button("Show Recovery Phrase") { coordinator.showRecovery(for: account) }
                    .foregroundStyle(palette.accent)
            } header: {
                Text("Recovery Phrase")
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)

            Section {
                Button("Reset App", systemImage: "trash", role: .destructive) { coordinator.startReset(.standard) }
                    .labelStyle(.warning)
            } footer: {
                Text("Deletes every wallet, recovery phrase, theme, your RPC API key, and custom RPCs from this device.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
        }
        .navigationTitle("Security & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
    }
}
