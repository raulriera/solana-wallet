import Foundation
import RPC
import Transactions
import Vault

/// The app's typed entry point for preparing, signing, submitting, and confirming V1 transactions.
nonisolated struct TransactionCoordinator: TransactionCoordinating {
    private let preparer: any TransactionPreparing
    private let signer: any TransactionSigning
    private let submitter: any TransactionSubmitting
    private let confirmer: any TransactionConfirming

    /// Creates the wallet workflow with a shared provider and protected recovery store.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisites, simulation, submission, and confirmation.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    init(rpc: any RPC, store: any RecoveryStoring) {
        self.init(preparer: Preparer(rpc: rpc), signer: Signer(rpc: rpc, store: store),
                  submitter: Submitter(rpc: rpc), confirmer: Confirmer(rpc: rpc))
    }

    /// Creates a workflow with independently supplied transaction services.
    ///
    /// - Parameters:
    ///   - preparer: The service that produces unsigned review data.
    ///   - signer: The service that validates and signs an approved preparation.
    ///   - submitter: The service that sends a reviewed, fully signed transaction.
    ///   - confirmer: The service that observes execution without broadcasting.
    init(preparer: any TransactionPreparing, signer: any TransactionSigning,
         submitter: any TransactionSubmitting, confirmer: any TransactionConfirming) {
        self.preparer = preparer
        self.signer = signer
        self.submitter = submitter
        self.confirmer = confirmer
    }

    /// Prepares an unsigned SOL transaction for user review.
    ///
    /// - Parameters:
    ///   - transfer: The sender, recipient, and amount in lamports.
    ///   - configuration: The explicit priority fee and execution resource limits.
    /// - Returns: The exact message, fee, expiry, and simulation observations.
    /// - Throws: A preparation error or `CancellationError` if cancelled.
    func prepare(_ transfer: Transfer, configuration: Configuration) async throws -> Preparation {
        try await preparer.prepare(transfer, configuration: configuration)
    }

    /// Prepares an imported V1 transaction for the selected required signer.
    ///
    /// - Parameters:
    ///   - transaction: The typed transaction supplied by the import boundary.
    ///   - signer: The selected account whose signature slot must be empty.
    /// - Returns: Exact transaction inspection, fee, and simulation observations.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ transaction: Transaction, for signer: Address) async throws -> Preparation {
        try await preparer.prepare(transaction, for: signer)
    }

    /// Authenticates wallet access and signs the exact preparation approved by the user.
    ///
    /// The caller obtains explicit approval before invoking this operation.
    /// Signing doesn't broadcast the transaction or substitute new review data.
    ///
    /// - Parameters:
    ///   - preparation: The unchanged preparation whose details the user approved.
    ///   - walletID: The identifier of the selected wallet's protected recovery.
    ///   - reason: The localized explanation for biometric authentication.
    /// - Returns: The reviewed preparation and verified signed transaction.
    /// - Throws: A validation, authentication, signing, or cancellation error.
    func sign(_ preparation: Preparation, for walletID: UUID, reason: String) async throws -> SignedTransaction {
        try await signer.sign(preparation, for: walletID, reason: reason)
    }

    /// Submits a signed result without requiring the caller to serialize or configure RPC.
    ///
    /// - Parameter signed: The approved result of signing, with every required signature present.
    /// - Returns: The accepted signature and network; execution confirmation is separate.
    /// - Throws: A validation, RPC, or cancellation error. Dispatch failures can leave receipt unknown.
    func submit(_ signed: SignedTransaction) async throws -> Submission {
        try await submitter.submit(signed)
    }

    /// Observes execution without exposing polling or RPC configuration to the caller.
    ///
    /// - Parameter submission: The accepted signature and its original network.
    /// - Returns: A confirmed or finalized execution outcome, including on-chain failures.
    /// - Throws: A network, RPC, response, timeout, or cancellation error.
    func confirm(_ submission: Submission) async throws -> Confirmation {
        try await confirmer.confirm(submission)
    }
}
