import Foundation
import Observation

/// Owns Settings > Accounts' deletions: each deletes an account the person confirmed and explains a failure.
@MainActor
@Observable
final class AccountDeletionModel {
    /// Why the last deletion couldn't be saved; the account stays in the list.
    var error: AccountsError?
    /// The confirmed deletion, while it waits for the list's task or runs.
    private(set) var attempt: UUID?
    /// The account to delete, until the list's task takes it.
    @ObservationIgnored private var request: Account.ID?

    /// Accepts a confirmed deletion; the list's task deletes the account once it's on screen again.
    /// - Parameter id: The account's identity.
    func delete(_ id: Account.ID) {
        guard attempt == nil else { return }
        error = nil
        request = id
        attempt = UUID()
    }

    /// Deletes the requested account once in the list's SwiftUI-managed task, then its transaction records; the
    /// deletion reaches every window through the stores.
    ///
    /// The save can't stop partway, so a failure is explained even when the task is cancelled.
    /// - Parameters:
    ///   - attempt: The identifier the list's task captured.
    ///   - store: The saved accounts that every window shares.
    ///   - transactions: The transactions that every window sends, watches, and records.
    func run(_ attempt: UUID?, store: AccountStore, transactions: TransactionStore) async {
        guard let attempt, self.attempt == attempt, let id = request.take() else { return }
        defer { self.attempt = nil }
        do {
            try await store.remove(id)
        } catch {
            self.error = .notDeleted
            return
        }
        // The account is gone, so records that can't be deleted are never shown, and Reset App deletes them.
        try? await transactions.erase(account: id)
    }
}
