import Foundation
import Observation
import Vault

/// Owns Settings > Accounts' additions: each adds the wallet's next account and explains a failure.
@MainActor
@Observable
final class AccountAdditionModel {
    /// Why the last addition failed; the list keeps what's saved.
    var error: AccountsError?
    /// The addition, while it waits for the screen's task or runs.
    private(set) var attempt: UUID?
    /// The account that the latest addition saved.
    private(set) var added: Account?
    /// The wallet that the waiting addition adds to, until the screen's task takes it; a failed addition keeps it to
    /// try again.
    @ObservationIgnored private var request: UUID?

    /// Whether an account is being added.
    var isAdding: Bool { attempt != nil }

    /// Adds a wallet's next account; the screen's task adds it, and taps while it runs are ignored.
    /// - Parameter recoveryID: The wallet's recovery identifier.
    func add(to recoveryID: UUID) {
        guard attempt == nil else { return }
        error = nil
        request = recoveryID
        attempt = UUID()
    }

    /// Adds the account that failed again; the screen's task runs the new attempt.
    func retry() {
        guard attempt == nil, request != nil else { return }
        attempt = UUID()
    }

    /// Adds the requested account once in the screen's SwiftUI-managed task; the saved account reaches every window
    /// through the store.
    ///
    /// The addition reads the wallet's recovery, which asks the person to authenticate. Cancelling authentication, or
    /// leaving before it, adds nothing and explains nothing.
    /// - Parameters:
    ///   - attempt: The identifier the screen's task captured.
    ///   - creation: Derives a new account from the wallet's recovery.
    ///   - store: The saved accounts that every window shares.
    func run(_ attempt: UUID?, creation: AccountCreation, store: AccountStore) async {
        guard let attempt, self.attempt == attempt, let recoveryID = request.take() else { return }
        defer { self.attempt = nil }
        do {
            let account = try await creation.account(at: store.nextPath(inWallet: recoveryID), inWallet: recoveryID)
            try await store.add(account)
            added = account
        } catch is CancellationError {
            // The person cancelled authentication, or the screen left before it.
        } catch KeychainStoreError.recoveryUnavailable {
            error = .recoveryUnavailable
        } catch {
            guard !Task.isCancelled else { return }
            // Trying again adds to the same wallet.
            request = recoveryID
            self.error = .notAdded
        }
    }
}
