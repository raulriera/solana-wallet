import Observation
import Vault

/// A workflow that prepares and saves one window's first account.
@MainActor
protocol OnboardingCoordinating: AnyObject, Observable {
    /// The draft's recovery, or `nil` without a draft.
    var recovery: Recovery? { get }
    /// The saved account, or `nil` until ``complete()`` succeeds.
    var account: Account? { get }
    /// The saved account, or `nil` until ``finish()`` succeeds.
    var finishedAccount: Account? { get }
    /// Whether a preparation or save is running.
    var isWorking: Bool { get }

    /// Prepares a new twelve-word recovery and its first account without saving them.
    ///
    /// - Throws: A preparation, cancellation, or invalid-state error.
    func create() async throws

    /// Validates recovery words and selects their first account with SOL without saving them.
    ///
    /// - Parameters:
    ///   - phrase: The recovery words.
    ///   - passphrase: The BIP-39 passphrase, including case and whitespace.
    /// - Throws: A phrase validation, rate limit, preparation, cancellation, or invalid-state error.
    func importRecovery(_ phrase: String, passphrase: String) async throws

    /// Saves the prepared recovery and account.
    ///
    /// - Returns: The saved account.
    /// - Throws: A storage, cancellation, or invalid-state error.
    func complete() async throws -> Account

    /// Ends onboarding with the saved account.
    ///
    /// - Throws: ``OnboardingCoordinatorError/accountRequired`` before completion.
    func finish() throws

    /// Releases the window's unsaved draft.
    ///
    /// - Throws: An invalid-state error while work is running.
    func discard() throws
}

extension OnboardingCoordinating {
    /// Releases the window's unsaved draft.
    ///
    /// - Returns: ``OnboardingError/stillFinishing`` while work holds the draft, or `nil` once it's released.
    func releaseDraft() -> OnboardingError? {
        do {
            try discard()
            return nil
        } catch {
            return .stillFinishing
        }
    }
}
