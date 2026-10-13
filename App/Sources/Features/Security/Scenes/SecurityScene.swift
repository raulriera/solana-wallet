import SwiftUI

/// Owns Security & Privacy's navigation container; the coordinator decides what's pushed.
struct SecurityScene: View {
    @Bindable var coordinator: SecurityCoordinator
    let account: Account

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            SecurityScreen(coordinator: coordinator, account: account)
                .navigationDestination(for: SecurityRoute.self) { route in
                    switch route {
                    case .recoveryBackup:
                        if let backup = coordinator.backup {
                            RecoveryBackupScreen(display: backup, coordinator: coordinator)
                        }
                    case .resetApp(let mode):
                        ResetAppScreen(mode: mode, account: account, coordinator: coordinator)
                    case .resetConfirmation:
                        ResetConfirmationScreen(coordinator: coordinator)
                    }
                }
        }
    }
}
