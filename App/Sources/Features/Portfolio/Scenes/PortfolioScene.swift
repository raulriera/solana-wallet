import Foundation
import SwiftUI
import Transactions

/// Owns the selected wallet's portfolio presentation within the window's appearance environment.
///
/// A missing or rejected provider key replaces only this portfolio content.
struct PortfolioScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var providerSetup: ProviderSubmission?
    let account: Account
    let coordinator: any PortfolioCoordinating
    let connection: any ProviderConnecting
    let keyRevision: ProviderKeyRevision

    var body: some View {
        let session = Session(accountID: account.id, isActive: scenePhase == .active, keyRevision: keyRevision.value)
        let failure = coordinator.failure

        Group {
            if let failure, failure.requiresProviderSetup {
                ProviderUnavailableScreen(isKeyRejected: failure == .invalidKey, setUp: setUpProvider)
            } else {
                WalletReadyScreen()
            }
        }
        .animation(.default, value: failure?.requiresProviderSetup == true)
        .task(id: session) { await coordinator.observe(for: account.address.value, isActive: session.isActive) }
        .sheet(item: $providerSetup) { ProviderSetupSheet(submission: $0) }
    }

    /// Opens provider setup; a saved key closes it, and every window observes again with that key.
    private func setUpProvider() {
        providerSetup = ProviderSubmission(connection: connection, revision: keyRevision) { providerSetup = nil }
    }

    /// The observation's identity: a new wallet, scene activity, or a key saved in any window restarts it.
    private struct Session: Equatable {
        let accountID: UUID
        let isActive: Bool
        let keyRevision: Int
    }
}
