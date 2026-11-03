import Foundation
import Observation
import RPC
import Transactions
import Vault
import Wallet

/// Prepares and saves one window's first account.
@MainActor
@Observable
final class OnboardingCoordinator: OnboardingCoordinating {
    private(set) var recovery: Recovery?
    private(set) var account: Account?
    private(set) var finishedAccount: Account?
    private(set) var isWorking = false

    var savedWalletAccount: Account? {
        guard !isWorking, account == nil else { return nil }
        return accountStore.accounts.first
    }

    private let wallet: any WalletProviding
    private let discovery: any AccountDiscovering
    private let recoveryStore: any RecoveryStoring
    private let accountStore: AccountStore
    @ObservationIgnored private var preparedAccount: Account?
    @ObservationIgnored private var recoverySaved = false

    /// Creates a coordinator.
    ///
    /// - Parameters:
    ///   - discovery: The service that finds an imported wallet's accounts.
    ///   - wallet: The service that generates phrases and derives accounts.
    ///   - recovery: The protected recovery storage.
    ///   - accounts: The saved accounts.
    init(discovery: any AccountDiscovering, wallet: any WalletProviding,
         recovery: any RecoveryStoring, accounts: AccountStore) {
        self.wallet = wallet
        self.discovery = discovery
        recoveryStore = recovery
        accountStore = accounts
    }

    func create() async throws {
        try await prepare({ Recovery(phrase: try wallet.recoveryPhrase(wordCount: .twelve), passphrase: "") },
                          selecting: firstAccount)
    }

    func importRecovery(_ phrase: String, passphrase: String) async throws {
        try await prepare({ Recovery(phrase: try RecoveryPhrase(phrase), passphrase: passphrase) },
                          selecting: discoveredAccount)
    }

    func complete() async throws -> Account {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        if let account { return account }
        guard let recovery, let preparedAccount else { throw OnboardingCoordinatorError.draftRequired }
        try Task.checkCancellation()
        isWorking = true
        defer { isWorking = false }
        guard accountStore.accounts.isEmpty else { try await releaseForSavedWallet(preparedAccount.recoveryID) }

        if !recoverySaved {
            try await saveRecovery(recovery, for: preparedAccount.recoveryID)
            recoverySaved = true
        }
        try Task.checkCancellation()
        do {
            try await saveAccount(preparedAccount)
        } catch AccountStoreError.anotherWallet {
            try await releaseForSavedWallet(preparedAccount.recoveryID)
        }

        account = preparedAccount
        self.preparedAccount = nil
        self.recovery = nil
        return preparedAccount
    }

    func finish() throws {
        guard let account else { throw OnboardingCoordinatorError.accountRequired }
        finishedAccount = account
    }

    func discard() throws {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        recovery = nil
        preparedAccount = nil
        recoverySaved = false
    }

    /// Prepares a draft from a recovery and its selected account.
    ///
    /// - Parameters:
    ///   - makeRecovery: A closure that creates or validates the recovery.
    ///   - selectAccount: A closure that selects the recovery's account.
    /// - Throws: A phrase validation, cancellation, or onboarding error.
    private func prepare(_ makeRecovery: () throws -> Recovery,
                         selecting selectAccount: (Recovery) async throws -> DerivedAccount) async throws {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        guard recovery == nil, account == nil else { throw OnboardingCoordinatorError.draftAlreadyPrepared }
        try Task.checkCancellation()
        isWorking = true
        defer { isWorking = false }
        do {
            let recovery = try makeRecovery()
            let selected = try await selectAccount(recovery)
            try Task.checkCancellation()
            preparedAccount = try Account(selected, recoveryID: UUID())
            self.recovery = recovery
        } catch let error as RecoveryPhrase.ValidationError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as RPCError where error.isRateLimited {
            throw OnboardingCoordinatorError.discoveryRateLimited
        } catch {
            throw OnboardingCoordinatorError.preparationFailed
        }
    }

    /// Derives a recovery's default first account.
    ///
    /// - Parameter recovery: The recovery to derive from.
    /// - Returns: The default account and its path.
    /// - Throws: A derivation or cancellation error.
    private func firstAccount(_ recovery: Recovery) async throws -> DerivedAccount {
        let accounts = try await wallet.accounts(for: recovery.phrase, passphrase: recovery.passphrase, paths: [.solana])
        guard let account = accounts.first else { throw OnboardingCoordinatorError.preparationFailed }
        return account
    }

    /// Finds a recovery's first account with SOL, or derives its default account when none has SOL.
    ///
    /// - Parameter recovery: The recovery to scan.
    /// - Returns: The selected account.
    /// - Throws: A discovery, derivation, or cancellation error.
    private func discoveredAccount(_ recovery: Recovery) async throws -> DerivedAccount {
        let accounts = try await discovery.discover(for: recovery.phrase, passphrase: recovery.passphrase)
        try Task.checkCancellation()
        if let account = accounts.first { return account }
        return try await firstAccount(recovery)
    }

    /// Saves a recovery, accepting an identical copy that's already saved.
    ///
    /// - Parameters:
    ///   - recovery: The recovery to save.
    ///   - id: The recovery's identifier.
    /// - Throws: A cancellation, Keychain, or onboarding error.
    private func saveRecovery(_ recovery: Recovery, for id: UUID) async throws {
        do {
            do {
                try await recoveryStore.save(recovery, for: id)
            } catch KeychainStoreError.duplicateRecovery {
                let stored = try await recoveryStore.recovery(for: id,
                    reason: String(localized: "Verify recovery before completing wallet setup"))
                guard stored.phrase.words == recovery.phrase.words, stored.passphrase == recovery.passphrase else {
                    throw OnboardingCoordinatorError.recoveryMismatch
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch OnboardingCoordinatorError.recoveryMismatch {
            throw OnboardingCoordinatorError.recoveryMismatch
        } catch let error as KeychainStoreError {
            throw error
        } catch {
            throw OnboardingCoordinatorError.recoveryStorageFailed
        }
    }

    /// Deletes this draft's saved recovery and releases the draft because another window saved the wallet.
    ///
    /// - Parameter id: The draft's recovery identifier.
    /// - Throws: ``OnboardingCoordinatorError/walletAlreadySaved``, or a Keychain error when the recovery can't be
    ///   deleted.
    private func releaseForSavedWallet(_ id: UUID) async throws -> Never {
        if recoverySaved { try await recoveryStore.deleteRecovery(for: id) }
        recovery = nil
        preparedAccount = nil
        recoverySaved = false
        throw OnboardingCoordinatorError.walletAlreadySaved
    }

    /// Saves the prepared account.
    ///
    /// - Parameter account: The account to save.
    /// - Throws: An account storage or onboarding error.
    private func saveAccount(_ account: Account) async throws {
        do {
            try await accountStore.add(account)
        } catch let error as AccountStoreError {
            throw error
        } catch {
            throw OnboardingCoordinatorError.accountStorageFailed
        }
    }
}
