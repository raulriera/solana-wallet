import Foundation
import Observation
import Vault

/// A model that adds a wallet's next account.
@MainActor
@Observable
final class AccountAdditionModel {
    var error: AccountsError?
    /// The waiting or running addition, or `nil` when there is none.
    private(set) var attempt: UUID?
    private(set) var added: Account?
    /// The recovery identifier of the wallet to add an account to.
    @ObservationIgnored private var request: UUID?

    var isAdding: Bool { attempt != nil }

    /// Starts adding a wallet's next account.
    ///
    /// - Parameter recoveryID: The wallet's recovery identifier.
    func add(to recoveryID: UUID) {
        guard attempt == nil else { return }
        error = nil
        request = recoveryID
        attempt = UUID()
    }

    /// Tries the failed addition again.
    func retry() {
        guard attempt == nil, request != nil else { return }
        attempt = UUID()
    }

    /// Adds the requested account.
    ///
    /// - Parameters:
    ///   - attempt: The addition to run.
    ///   - creation: The service that derives the account.
    ///   - store: The store that saves the account.
    func run(_ attempt: UUID?, creation: AccountCreation, store: AccountStore) async {
        guard let attempt, self.attempt == attempt, let recoveryID = request.take() else { return }
        defer { self.attempt = nil }
        do {
            let account = try await creation.account(at: store.nextPath, inWallet: recoveryID)
            try await store.add(account)
            added = account
        } catch is CancellationError {
        } catch KeychainStoreError.recoveryUnavailable {
            error = .recoveryUnavailable
        } catch {
            guard !Task.isCancelled else { return }
            request = recoveryID
            self.error = .notAdded
        }
    }
}
