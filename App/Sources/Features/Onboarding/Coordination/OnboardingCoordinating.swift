import Observation
import Vault

/// One window's preparation and explicit completion of its first account.
@MainActor
protocol OnboardingCoordinating: AnyObject, Observable {
    /// Recovery available for explicit backup while a draft awaits completion.
    var recovery: Recovery? { get }
    /// The account published only after both persistence steps succeed.
    var account: Account? { get }
    /// Whether preparation or completion is in progress.
    var isWorking: Bool { get }

    /// Prepares a new twelve-word recovery and its first address without saving either.
    /// - Throws: A preparation, cancellation, or invalid-state error.
    func create() async throws

    /// Validates recovery and selects the first SOL-funded account, or the default after an empty scan.
    ///
    /// Discovery must succeed before a draft is prepared. Nothing is saved during preparation.
    /// - Parameters:
    ///   - phrase: The recovery words supplied by the user.
    ///   - passphrase: The original BIP-39 passphrase, preserving case and whitespace.
    /// - Throws: A phrase-validation, rate-limit, preparation, cancellation, or invalid-state error.
    func importRecovery(_ phrase: String, passphrase: String) async throws

    /// Saves the prepared recovery and public account after explicit approval.
    ///
    /// The window stays in onboarding until ``finish()``. Failed saves retain the draft and
    /// identifiers for an explicit retry. Cancellation doesn't undo a committed write.
    /// Repeated completion returns the same account.
    /// - Returns: The persisted first account.
    /// - Throws: A storage, cancellation, or invalid-state error without recovery text.
    func complete() async throws -> Account

    /// Ends onboarding by opening the saved account in the owning window.
    /// - Throws: ``OnboardingCoordinatorError/accountRequired`` before completion.
    func finish() throws

    /// Releases this window's draft after any caller-owned task has finished.
    ///
    /// Already persisted recovery and account records are never deleted, and a saved account
    /// stays available to ``finish()``. Releasing references doesn't guarantee that Swift
    /// erases their memory.
    /// - Throws: An invalid-state error if work is still in progress.
    func discard() throws
}
