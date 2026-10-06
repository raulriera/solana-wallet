import Foundation
import Testing
import Transactions
@testable import widgets

/// Isolated account persistence that checks recovery ordering and scripted failures.
actor OnboardingAccountStore: AccountStoring {
    private let recovery: OnboardingRecoveryStore
    private let firstFailure: (any Error)?
    private let commitBeforeFailure: Bool
    private let conflict: Bool
    private let gate: Suspension?
    private(set) var records: [widgets.Account] = []
    private(set) var additions: [widgets.Account] = []

    /// Configures one test's public persistence boundary.
    /// - Parameters:
    ///   - recovery: The recovery store whose commit must precede each addition.
    ///   - firstFailure: The first addition's scripted error.
    ///   - commitBeforeFailure: Whether that addition commits before reporting failure.
    ///   - conflict: Whether a duplicate record has a different recovery identity.
    ///   - gate: An optional cancellable suspension after the metadata commit.
    init(recovery: OnboardingRecoveryStore, firstFailure: (any Error)? = nil,
         commitBeforeFailure: Bool = false, conflict: Bool = false, gate: Suspension? = nil) {
        self.recovery = recovery
        self.firstFailure = firstFailure
        self.commitBeforeFailure = commitBeforeFailure
        self.conflict = conflict
        self.gate = gate
    }

    /// Loads this test's committed public records.
    /// - Returns: Accounts in commit order.
    func load() async throws -> [widgets.Account] { records }

    /// Verifies recovery ordering before recording the requested metadata.
    /// - Parameter account: The prepared account to save.
    /// - Returns: The committed public records.
    /// - Throws: The scripted failure or a duplicate-account error.
    func add(_ account: widgets.Account) async throws -> [widgets.Account] {
        try #require(await recovery.contains(account.recoveryID))
        additions.append(account)
        guard !records.contains(where: { $0.id == account.id }) else { throw AccountStore.Failure.duplicateAccount }
        let failure = additions.count == 1 ? firstFailure : nil
        if failure == nil || commitBeforeFailure {
            records.append(Account(id: account.id, recoveryID: conflict ? UUID() : account.recoveryID,
                                   address: account.address, path: account.path))
        }
        if let gate { await gate.suspend() }
        if let failure { throw failure }
        return records
    }

    /// Reports any deletion, because onboarding never removes saved accounts.
    func removeAll() async throws {
        Issue.record("Onboarding must not delete account metadata.")
    }
}
