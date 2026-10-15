import Foundation
import Observation
import RPC
import Transactions
import Vault
import Wallet

/// Coordinates one window's recovery draft, import discovery, and ordered persistence.
@MainActor
@Observable
final class OnboardingCoordinator: OnboardingCoordinating {
    private(set) var recovery: Recovery?
    private(set) var account: Account?
    private(set) var isWorking = false

    private let wallet: any WalletProviding
    private let discovery: any AccountDiscovering
    private let recoveryStore: any RecoveryStoring
    private let accountStore: any AccountStoring
    private let router: any WindowRouting
    @ObservationIgnored private var preparedAccount: Account?
    @ObservationIgnored private var recoverySaved = false

    /// Creates independent presentation state around shared, interchangeable services.
    /// - Parameters:
    ///   - discovery: One bounded SOL-only scan on the configured network for imports.
    ///   - wallet: Local phrase generation and address derivation.
    ///   - recovery: Protected recovery persistence.
    ///   - accounts: Public account metadata persistence.
    ///   - router: The owning window's root navigation.
    init(discovery: any AccountDiscovering, wallet: any WalletProviding,
         recovery: any RecoveryStoring, accounts: any AccountStoring,
         router: any WindowRouting) {
        self.wallet = wallet
        self.discovery = discovery
        recoveryStore = recovery
        accountStore = accounts
        self.router = router
    }

    /// Prepares a new twelve-word recovery with no BIP-39 passphrase.
    /// - Throws: A preparation, cancellation, or invalid-state error.
    func create() async throws {
        try await prepare({ Recovery(phrase: try wallet.recoveryPhrase(wordCount: .twelve), passphrase: "") },
                          selecting: firstAccount)
    }

    /// Selects the first SOL-funded account, or the default account after a successful empty scan.
    /// - Parameters:
    ///   - phrase: The supplied recovery words.
    ///   - passphrase: The original BIP-39 passphrase, preserving case and whitespace.
    /// - Throws: A phrase-validation, rate-limit, preparation, cancellation, or invalid-state error.
    func importRecovery(_ phrase: String, passphrase: String) async throws {
        try await prepare({ Recovery(phrase: try RecoveryPhrase(phrase), passphrase: passphrase) },
                          selecting: discoveredAccount)
    }

    /// Commits protected recovery and public metadata; ``finish()`` opens the account afterwards.
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

    /// Routes this window to the saved account once onboarding's last step succeeds.
    /// - Throws: ``OnboardingCoordinatorError/accountRequired`` before completion.
    func finish() throws {
        guard let account else { throw OnboardingCoordinatorError.accountRequired }
        router.route(to: .wallet(account))
    }

    /// Drops this window's unsaved draft without deleting either store's records.
    ///
    /// A saved account remains, so a step that ends after completion can't undo it.
    /// - Throws: ``OnboardingCoordinatorError/operationInProgress`` until the caller's active task finishes.
    func discard() throws {
        guard !isWorking else { throw OnboardingCoordinatorError.operationInProgress }
        recovery = nil
        preparedAccount = nil
        recoverySaved = false
    }

    /// Prepares one draft and publishes it only after cancellable account selection succeeds.
    /// - Parameters:
    ///   - makeRecovery: Local generation or validation of recovery material.
    ///   - selectAccount: Local default derivation or imported-account discovery.
    /// - Throws: A phrase-validation error, cancellation, or a secret-free workflow error.
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
            preparedAccount = Account(id: UUID(), recoveryID: UUID(), address: try Address(selected.address), path: selected.path)
            self.recovery = recovery
        } catch let error as RecoveryPhrase.ValidationError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as RPCError where error.isRateLimited {
            throw OnboardingCoordinatorError.discoveryRateLimited
        } catch {
            // Arbitrary dependency errors may contain recovery text; only known safe errors escape.
            throw OnboardingCoordinatorError.preparationFailed
        }
    }

    /// Derives the default first account locally without observing balances.
    /// - Parameter recovery: The transient validated recovery and verbatim original passphrase.
    /// - Returns: The default address paired with its exact path.
    /// - Throws: A derivation or cancellation error.
    private func firstAccount(_ recovery: Recovery) async throws -> DerivedAccount {
        let accounts = try await wallet.accounts(for: recovery.phrase, passphrase: recovery.passphrase, paths: [.solana])
        guard let account = accounts.first else { throw OnboardingCoordinatorError.preparationFailed }
        return account
    }

    /// Checks the existing twenty-address scan once; failures never become empty success.
    /// - Parameter recovery: The transient validated recovery, never sent to RPC.
    /// - Returns: The first positive-SOL result in scan order or the default account after an empty scan.
    /// - Throws: A discovery, derivation, or cancellation error, without an automatic retry.
    private func discoveredAccount(_ recovery: Recovery) async throws -> DerivedAccount {
        let result = try await discovery.discover(for: recovery.phrase, passphrase: recovery.passphrase)
        try Task.checkCancellation()
        if let account = result.accounts.first { return account }
        return try await firstAccount(recovery)
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
            } catch KeychainStoreError.duplicateWallet {
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
            // Vault's typed failures retain useful context without recovery or underlying error text.
            throw error
        } catch {
            // Unknown storage errors cross a secret-handling boundary and must lose their payload.
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
            } catch AccountStoreError.duplicateAccount {
                let stored = try await accountStore.load()
                guard stored.contains(where: {
                    $0.id == account.id && $0.recoveryID == account.recoveryID
                        && $0.address == account.address && $0.path == account.path
                }) else { throw OnboardingCoordinatorError.accountStorageFailed }
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as AccountStoreError {
            // These closed, payload-free cases are safe to preserve for the caller.
            throw error
        } catch {
            // Injected stores may attach secret-bearing context to otherwise ordinary errors.
            throw OnboardingCoordinatorError.accountStorageFailed
        }
    }
}
