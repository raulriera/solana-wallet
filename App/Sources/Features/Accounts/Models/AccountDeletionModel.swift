import Foundation
import Observation

/// A model that deletes an account.
@MainActor
@Observable
final class AccountDeletionModel {
    var error: AccountsError?
    /// The waiting or running deletion, or `nil` when there is none.
    private(set) var attempt: UUID?
    /// The identifier of the account to delete.
    @ObservationIgnored private var request: Account.ID?

    /// Starts deleting an account.
    ///
    /// - Parameter id: The account's identifier.
    func delete(_ id: Account.ID) {
        guard attempt == nil else { return }
        error = nil
        request = id
        attempt = UUID()
    }

    /// Deletes the requested account and its transaction records.
    ///
    /// - Parameters:
    ///   - attempt: The deletion to run.
    ///   - store: The store that saves the accounts.
    ///   - transactions: The store that records transactions.
    func run(_ attempt: UUID?, store: AccountStore, transactions: TransactionStore) async {
        guard let attempt, self.attempt == attempt, let id = request.take() else { return }
        defer { self.attempt = nil }
        do {
            try await store.remove(id)
        } catch {
            self.error = .notDeleted
            return
        }
        try? await transactions.erase(account: id)
    }
}
