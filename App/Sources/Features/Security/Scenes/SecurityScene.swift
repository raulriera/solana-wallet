import SwiftUI

/// Owns Security & Privacy's navigation container; the flow decides what's pushed.
struct SecurityScene: View {
    @Bindable var flow: SecurityFlow
    let account: Account

    var body: some View {
        NavigationStack(path: $flow.path) {
            SecurityScreen(flow: flow, account: account)
                .navigationDestination(for: SecurityRoute.self) { route in
                    switch route {
                    case .recoveryBackup:
                        if let backup = flow.backup {
                            RecoveryBackupScreen(display: backup, flow: flow)
                        }
                    case .resetApp(let mode):
                        ResetAppScreen(mode: mode, account: account, flow: flow)
                    case .resetConfirmation:
                        ResetConfirmationScreen(flow: flow)
                    }
                }
        }
    }
}
