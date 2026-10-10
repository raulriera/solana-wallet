import Foundation
import Observation

/// Owns one Settings window's Security & Privacy navigation and runs its recovery and reset steps.
@MainActor
@Observable
final class SecurityFlow {
    /// The screens pushed above Security & Privacy; Back removes the last one.
    var path: [SecurityRoute] = [] {
        didSet {
            // A closed backup screen releases the words it showed.
            if !path.contains(.recoveryBackup) { backup = nil }
        }
    }
    /// What the backup screen shows while it's open.
    private(set) var backup: RecoveryDisplay?
    /// A secret-free error for the alert.
    var error: SecurityError?
    /// The step waiting for the scene's task, identified without secrets.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Request?
    private let services: SecurityServices

    /// Copies recovery words to this device only, for the backup screen.
    var pasteboard: any RecoveryCopying { services.pasteboard }

    /// A step that waits for authentication or storage.
    private enum Request {
        case showRecovery(Account)
        case confirmOwner
        case reset
    }

    /// Connects the flow to the window's security services.
    /// - Parameter services: Shows recovery, confirms the device owner, and resets the app.
    init(services: SecurityServices) {
        self.services = services
    }

    /// Reads the wallet's recovery, then opens its backup.
    /// - Parameter account: The window's wallet.
    func showRecovery(for account: Account) {
        begin(.showRecovery(account))
    }

    /// Opens the reset explanation, confirming the device owner first unless recovery is already gone.
    /// - Parameter mode: Why the user is resetting.
    func startReset(_ mode: ResetMode) {
        switch mode {
        case .standard: begin(.confirmOwner)
        case .recoveryUnavailable: path.append(.resetApp(.recoveryUnavailable))
        }
    }

    /// Opens the final reset confirmation.
    func confirmReset() {
        path.append(.resetConfirmation)
    }

    /// Resets the app; every window then returns to onboarding.
    func reset() {
        begin(.reset)
    }

    /// Ends the flow when its scene leaves, releasing any open backup.
    func close() {
        attempt = nil
        request = nil
        error = nil
        path = []
    }

    /// Runs the waiting step once in the scene's SwiftUI-managed task.
    /// - Parameter attempt: The identifier the scene's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            switch request {
            case .showRecovery(let account):
                let display = try await services.recovery.display(for: account)
                guard self.attempt == attempt else { return }
                backup = display
                path.append(.recoveryBackup)
            case .confirmOwner:
                try await services.owner.confirmOwner(reason: String(localized: "Reset the app"))
                guard self.attempt == attempt else { return }
                path.append(.resetApp(.standard))
            case .reset:
                try await services.reset.reset()
            }
        } catch is CancellationError {
            // The user dismissed authentication or the scene left.
        } catch {
            guard self.attempt == attempt else { return }
            self.error = switch request {
            case .showRecovery: .recoveryUnreadable
            case .confirmOwner: .ownerNotConfirmed
            case .reset: .resetIncomplete
            }
        }
    }

    /// Accepts one step at a time, ignoring taps while another step waits.
    /// - Parameter request: The step to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        self.request = request
        attempt = UUID()
    }
}
