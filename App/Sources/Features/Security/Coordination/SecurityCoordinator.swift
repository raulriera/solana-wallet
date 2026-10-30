import Foundation
import Observation

/// Runs one window's Security & Privacy navigation and its recovery and reset steps.
@MainActor
@Observable
final class SecurityCoordinator {
    var path: [SecurityRoute] = [] {
        didSet {
            if !path.contains(.recoveryBackup) { backup = nil }
        }
    }
    /// The recovery that the backup screen shows, or `nil` when the screen is closed.
    private(set) var backup: RecoveryDisplay?
    var error: SecurityError?
    /// The identifier of the waiting step, or `nil` when none waits.
    private(set) var attempt: UUID?
    @ObservationIgnored private var request: Request?
    private let services: SecurityServices

    var pasteboard: any RecoveryCopying { services.pasteboard }

    /// A step that waits for authentication or storage.
    private enum Request {
        case showRecovery(Account)
        case confirmOwner
        case reset
    }

    /// Creates a coordinator.
    ///
    /// - Parameter services: The security services.
    init(services: SecurityServices) {
        self.services = services
    }

    /// Reads an account's recovery, then opens its backup.
    ///
    /// - Parameter account: The account whose recovery to show.
    func showRecovery(for account: Account) {
        begin(.showRecovery(account))
    }

    /// Opens the reset explanation, confirming the device owner first for a standard reset.
    ///
    /// - Parameter mode: The reason for the reset.
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

    /// Resets the app.
    func reset() {
        begin(.reset)
    }

    /// Cancels the waiting step and closes every pushed screen.
    func close() {
        attempt = nil
        request = nil
        error = nil
        path = []
    }

    /// Runs the waiting step.
    ///
    /// - Parameter attempt: The identifier of the step to run.
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
        } catch {
            guard self.attempt == attempt else { return }
            self.error = switch request {
            case .showRecovery: .recoveryUnreadable
            case .confirmOwner: .ownerNotConfirmed
            case .reset: .resetIncomplete
            }
        }
    }

    /// Starts a step unless another step waits.
    ///
    /// - Parameter request: The step to run.
    private func begin(_ request: Request) {
        guard attempt == nil else { return }
        error = nil
        self.request = request
        attempt = UUID()
    }
}
