import Foundation
import Observation

/// A model that renames an account.
@MainActor
@Observable
final class AccountRenameModel {
    var error: AccountsError?
    /// The waiting or running rename, or `nil` when there is none.
    private(set) var attempt: UUID?
    private(set) var isRenamed = false
    @ObservationIgnored private var request: Request?

    /// A new name for an account.
    private struct Request {
        let id: Account.ID
        let name: String
    }

    var isRenaming: Bool { attempt != nil }

    /// Starts renaming an account.
    ///
    /// - Parameters:
    ///   - id: The account's identifier.
    ///   - name: The new name, or an empty string for the account's numbered name.
    func rename(_ id: Account.ID, to name: String) {
        guard attempt == nil else { return }
        error = nil
        isRenamed = false
        request = Request(id: id, name: name)
        attempt = UUID()
    }

    /// Saves the requested name.
    ///
    /// - Parameters:
    ///   - attempt: The rename to run.
    ///   - store: The store that saves the accounts.
    func run(_ attempt: UUID?, store: AccountStore) async {
        guard let attempt, self.attempt == attempt, let request = request.take() else { return }
        defer { self.attempt = nil }
        do {
            try await store.rename(request.id, to: request.name)
            isRenamed = true
        } catch {
            self.error = .notRenamed
        }
    }
}
