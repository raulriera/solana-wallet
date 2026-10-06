import SwiftUI

/// Explains what stays on this device and opens the window's wallet backup after authentication.
struct SecurityScreen: View {
    @Environment(\.palette) private var palette
    @State private var request: UUID?
    @State private var display: RecoveryDisplay?
    @State private var isShowingFailure = false
    let account: Account
    let recovery: any RecoveryRevealing
    let pasteboard: any RecoveryCopying

    var body: some View {
        Form {
            Section {
                Button("Show Recovery Phrase") { request = UUID() }
                    .foregroundStyle(palette.accent)
            } header: {
                Text("Recovery Phrase")
            } footer: {
                Text("Your wallets and recovery phrase stay on this device. They are not in iCloud or in device backups.")
                    .foregroundStyle(palette.secondaryText)
            }
            .listRowBackground(palette.surface)
            .listRowSeparatorTint(palette.separator)
        }
        .navigationTitle("Security & Privacy")
        .foregroundStyle(palette.primaryText, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .task(id: request) { await showRecovery() }
        // The backup stays in memory only while its screen is open.
        .navigationDestination(isPresented: $display[isPresented: true]) {
            if let display {
                RecoveryBackupScreen(display: display, pasteboard: pasteboard)
            }
        }
        .alert("Couldn't Show Recovery Phrase", isPresented: $isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your recovery phrase couldn't be read. Try again.")
        }
    }

    /// Reads the wallet's recovery once per tap and opens the result; a dismissed prompt changes nothing.
    private func showRecovery() async {
        guard request != nil else { return }
        defer { request = nil }
        do {
            display = try await recovery.display(for: account)
        } catch is CancellationError {
            // The user dismissed authentication or left the screen.
        } catch {
            isShowingFailure = true
        }
    }
}
