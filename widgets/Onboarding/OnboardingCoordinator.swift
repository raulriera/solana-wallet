import Foundation
import Observation
import Transactions
import Vault
import Wallet

/// Coordinates one window's recovery draft without making network requests.
@MainActor
@Observable
final class OnboardingCoordinator: OnboardingCoordinating {
    private(set) var recovery: Recovery?
    private(set) var account: Account?
    private(set) var isWorking = false

    private let wallet: any WalletProviding
    private let recoveryStore: any RecoveryStoring
    private let accountStore: any AccountStoring
    @ObservationIgnored private var preparedAccount: Account?
    @ObservationIgnored private var recoverySaved = false

    /// Creates independent presentation state around shared, interchangeable services.
    /// - Parameters:
    ///   - wallet: Local phrase generation and address derivation.
    ///   - recovery: Protected recovery persistence.
    ///   - accounts: Public account metadata persistence.
    init(wallet: any WalletProviding, recovery: any RecoveryStoring, accounts: any AccountStoring) {
        self.wallet = wallet
        recoveryStore = recovery
        accountStore = accounts
    }

    /// Prepares a new twelve-word recovery with no BIP-39 passphrase.
    /// - Throws: A preparation, cancellation, or invalid-state error.
    func create() async throws {
        try await prepare { Recovery(phrase: try wallet.recoveryPhrase(wordCount: .twelve), passphrase: "") }
    }

    /// Prepares validated imported recovery, preserving the original passphrase exactly.
    /// - Parameters:
    ///   - phrase: The supplied recovery words.
    ///   - passphrase: The original BIP-39 passphrase.
    /// - Throws: A phrase-validation, preparation, cancellation, or invalid-state error.
    func importRecovery(_ phrase: String, passphrase: String) async throws {
        try await prepare { Recovery(phrase: try RecoveryPhrase(phrase), passphrase: passphrase) }
    }

    /// Commits protected recovery before making its public account available.
    /// - Returns: The saved account, including when cancellation follows its commit.
    /// - Throws: A secret-free storage error, cancellation, or an invalid-state error.
    func complete() async throws -> Account {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        if let account { return account }
        guard let recovery, let preparedAccount else { throw OnboardingCoordinatorError.draftRequired }
        try Task.checkCancellation()
        isWorking = true
        defer { isWorking = false }

        if !recoverySaved {
            try await saveRecovery(recovery, for: preparedAccount.recoveryID)
            recoverySaved = true
        }
        try Task.checkCancellation()
        try await saveAccount(preparedAccount)

        // The metadata commit is the completion boundary; late cancellation cannot undo it.
        account = preparedAccount
        self.preparedAccount = nil
        self.recovery = nil
        return preparedAccount
    }

    /// Drops this window's in-memory state without deleting either store's records.
    /// - Throws: ``OnboardingCoordinatorError/operationInProgress`` until the caller's active task finishes.
    func discard() throws {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        recovery = nil
        preparedAccount = nil
        recoverySaved = false
        account = nil
    }

    /// Prepares one draft and publishes it only after cancellable derivation succeeds.
    /// - Parameter makeRecovery: Local generation or validation of recovery material.
    /// - Throws: A phrase-validation error, cancellation, or a secret-free workflow error.
    private func prepare(_ makeRecovery: () throws -> Recovery) async throws {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        guard recovery == nil, account == nil else { throw OnboardingCoordinatorError.draftAlreadyPrepared }
        try Task.checkCancellation()
        isWorking = true
        defer { isWorking = false }
        do {
            let recovery = try makeRecovery()
            let address = try await wallet.address(for: recovery.phrase, passphrase: recovery.passphrase, path: .solana)
            try Task.checkCancellation()
            preparedAccount = Account(id: UUID(), recoveryID: UUID(), address: try Address(address), index: 0)
            self.recovery = recovery
        } catch let error as RecoveryPhrase.ValidationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnboardingCoordinatorError.preparationFailed
        }
    }

    /// Verifies a duplicate save before accepting an earlier, ambiguously completed write.
    /// - Parameters:
    ///   - recovery: The exact recovery retained by this draft.
    ///   - id: The stable recovery identity retained across retries.
    /// - Throws: Cancellation or a secret-free storage or identity error.
    private func saveRecovery(_ recovery: Recovery, for id: UUID) async throws {
        do {
            do {
                try await recoveryStore.save(recovery, for: id)
            } catch KeychainStore.Failure.duplicateWallet {
                let stored = try await recoveryStore.recovery(for: id,
                    reason: String(localized: "Verify recovery before completing wallet setup"))
                guard stored.phrase.words == recovery.phrase.words, stored.passphrase == recovery.passphrase else {
                    throw OnboardingCoordinatorError.recoveryMismatch
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch OnboardingCoordinatorError.recoveryMismatch {
            throw OnboardingCoordinatorError.recoveryMismatch
        } catch {
            throw OnboardingCoordinatorError.recoveryStorageFailed
        }
    }

    /// Accepts a retry only when the existing record exactly matches this prepared account.
    /// - Parameter account: The stable public identity retained by the draft.
    /// - Throws: Cancellation or a secret-free account-storage error.
    private func saveAccount(_ account: Account) async throws {
        do {
            do {
                _ = try await accountStore.add(account)
            } catch AccountStore.Failure.duplicateAccount {
                let stored = try await accountStore.load()
                guard stored.contains(where: {
                    $0.id == account.id && $0.recoveryID == account.recoveryID
                        && $0.address == account.address && $0.index == account.index
                }) else { throw OnboardingCoordinatorError.accountStorageFailed }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnboardingCoordinatorError.accountStorageFailed
        }
    }
}
