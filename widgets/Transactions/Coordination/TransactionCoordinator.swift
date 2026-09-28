import Foundation
import RPC
import Transactions
import Vault

/// The app's typed entry point for preparing, signing, submitting, and confirming V1 transactions.
nonisolated struct TransactionCoordinator: TransactionCoordinating {
    /// The mutually exclusive submission strategy selected in app settings.
    enum Strategy: Sendable, CaseIterable, Equatable {
        /// Submits through all configured ordinary RPCs without a Sender service tip.
        case none
        /// Submits only through Sender's lower-cost delivery route.
        case standard
        /// Submits only through Sender's broader delivery routes, with a higher tip.
        case premium

        /// Selects submission clients for one strategy and network.
        ///
        /// - Parameters:
        ///   - network: The network used for preparation and confirmation.
        ///   - rpcs: The ordinary RPC candidates used when Sender is disabled.
        /// - Returns: Same-network ordinary RPCs or one Sender client.
        /// - Throws: ``Submitter/Failure/noProviders`` if the strategy has no route on this network.
        func clients(for network: Network, from rpcs: [any RPC]) throws -> [any RPC] {
            let candidates: [any RPC] = switch self {
            case .none: rpcs.filter { $0.submissionRequirements == nil }
            case .standard: [Sender(tier: .standard)]
            case .premium: [Sender(tier: .premium)]
            }
            let clients = candidates.filter { $0.network == network }
            guard !clients.isEmpty else { throw Submitter.Failure.noProviders }
            return clients
        }
    }

    private let preparer: any TransactionPreparing
    private let signer: any TransactionSigning
    private let submitter: any TransactionSubmitting
    private let confirmer: any TransactionConfirming

    /// Creates the wallet workflow with a shared provider and protected recovery store.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisites, simulation, and confirmation. Public mainnet is the default.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    ///   - rpcs: Ordinary RPC candidates for `.none`, or `nil` to use `rpc` alone.
    ///   - strategy: The submission strategy. The default disables Sender.
    /// - Throws: ``Submitter/Failure/noProviders`` if no selected route serves the read client's network.
    init(rpc: any RPC = Solana(), store: any RecoveryStoring, rpcs: [any RPC]? = nil,
         strategy: Strategy = .none) throws {
        let clients = try strategy.clients(for: rpc.network, from: rpcs ?? [rpc])
        self.init(preparer: Preparer(rpc: rpc, rpcs: clients), signer: Signer(rpc: rpc, store: store),
                  submitter: Submitter(rpc: rpc, rpcs: clients), confirmer: Confirmer(rpc: rpc))
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
    /// - Returns: A plain receipt after the concurrent attempts finish; confirmation is separate.
    /// - Throws: A validation, aggregate delivery, or cancellation error. Delivery can remain unknown.
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
