import Foundation
import Observation

/// Owns an account's renames: each saves the account's new name and explains a failure.
@MainActor
@Observable
final class AccountRenameModel {
    /// Why the last rename couldn't be saved; the account keeps its saved name.
    var error: AccountsError?
    /// The rename, while it waits for the screen's task or runs.
    private(set) var attempt: UUID?
    /// Whether the latest rename was saved; the Account screen closes once it is.
    private(set) var isRenamed = false
    /// The waiting rename, until the screen's task takes it.
    @ObservationIgnored private var request: Request?

    /// A new name for an account.
    private struct Request {
        let id: Account.ID
        let name: String
    }

    /// Whether a new name is being saved.
    var isRenaming: Bool { attempt != nil }

    /// Gives an account a new name; the screen's task saves it, and taps while it runs are ignored.
    /// - Parameters:
    ///   - id: The account's identity.
    ///   - name: The new name; an empty one gives the account back its numbered name.
    func rename(_ id: Account.ID, to name: String) {
        guard attempt == nil else { return }
        error = nil
        isRenamed = false
        request = Request(id: id, name: name)
        attempt = UUID()
    }

    /// Saves the requested name once in the screen's SwiftUI-managed task; the saved name reaches every window through
    /// the store.
    ///
    /// Leaving doesn't stop the save, so its failure is explained even then.
    /// - Parameters:
    ///   - attempt: The identifier the screen's task captured.
    ///   - store: The saved accounts that every window shares.
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
