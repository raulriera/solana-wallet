import Foundation
import RPC
import Transactions
import Vault

/// The app's typed entry point for simulating and approving arbitrary V1 transactions.
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
        /// - Throws: ``SubmitterError/noProviders`` if the strategy has no route on this network.
        func clients(for network: Network, from rpcs: [any RPC]) throws -> [any RPC] {
            let candidates: [any RPC] = switch self {
            case .none: rpcs.filter { $0.submissionRequirements == nil }
            case .standard: [Sender(tier: .standard)]
            case .premium: [Sender(tier: .premium)]
            }
            let clients = candidates.filter { $0.network == network }
            guard !clients.isEmpty else { throw SubmitterError.noProviders }
            return clients
        }
    }

    private let id = UUID()
    private let tokens: TokenTransfers
    private let configuration: Configuration?
    private let preparer: any TransactionPreparing
    private let signer: any TransactionSigning
    private let submitter: any TransactionSubmitting
    private let confirmer: any TransactionConfirming

    /// Creates the wallet workflow with a shared provider and protected recovery store.
    ///
    /// - Parameters:
    ///   - rpc: The provider used for prerequisites, simulation, and the real-time watch. Public mainnet is the default.
    ///   - store: The recovery store that authenticates access to the selected wallet.
    ///   - rpcs: Ordinary RPC candidates for `.none`, or `nil` to use `rpc` alone.
    ///   - strategy: The submission strategy. The default disables Sender.
    ///   - configuration: Explicit V1 requests, or `nil` for automatic resource estimation.
    /// - Throws: ``SubmitterError/noProviders`` if no selected route serves the read client's network.
    init(rpc: any RPC & SignatureEventProviding = Solana(), store: any RecoveryStoring, rpcs: [any RPC]? = nil,
         strategy: Strategy = .none, configuration: Configuration? = nil) throws {
        let clients = try strategy.clients(for: rpc.network, from: rpcs ?? [rpc])
        self.init(rpc: rpc, configuration: configuration, preparer: Preparer(rpc: rpc, rpcs: clients), signer: Signer(rpc: rpc, store: store),
                  submitter: Submitter(rpc: rpc, rpcs: clients), confirmer: Confirmer(rpc: rpc))
    }

    /// Creates a workflow with independently supplied transaction services.
    ///
    /// - Parameters:
    ///   - rpc: The provider used to resolve token prerequisites.
    ///   - configuration: Explicit requests or automatic estimation.
    ///   - preparer: The service that produces unsigned review data.
    ///   - signer: The service that validates and signs an approved preparation.
    ///   - submitter: The service that sends a reviewed, fully signed transaction.
    ///   - confirmer: The service that observes execution without broadcasting.
    init(rpc: any RPC, configuration: Configuration? = nil, preparer: any TransactionPreparing, signer: any TransactionSigning,
         submitter: any TransactionSubmitting, confirmer: any TransactionConfirming) {
        tokens = TokenTransfers(rpc: rpc)
        self.configuration = configuration
        self.preparer = preparer
        self.signer = signer
        self.submitter = submitter
        self.confirmer = confirmer
    }

    /// Simulates ordered instructions using the first wallet as fee payer.
    ///
    /// - Parameters:
    ///   - instructions: The invocations composing one atomic transaction.
    ///   - wallets: The selected local signers; the first account pays fees.
    /// - Returns: An immutable review bound to these wallets and this coordinator.
    /// - Throws: A validation, preparation, RPC, or cancellation error.
    func simulate(_ instructions: [Instruction], using wallets: [Account]) async throws -> Simulation {
        let wallet = try selectedWallet(in: wallets)
        let preparation = try await preparer.prepare(instructions, payer: wallet.address, signer: wallet.address,
            configuration: configuration, minimumSlot: nil)
        return try review(preparation, wallets: wallets)
    }

    /// Simulates an imported transaction without replacing its message or cosignatures.
    ///
    /// - Parameters:
    ///   - transaction: The complete imported transaction.
    ///   - wallets: The local accounts whose required slots will be signed after approval.
    /// - Returns: The unchanged transaction and its review observations.
    /// - Throws: A structural, signature, RPC, or cancellation error.
    func simulate(_ transaction: Transaction, using wallets: [Account]) async throws -> Simulation {
        let wallet = try selectedWallet(in: wallets)
        let preparation = try await preparer.prepare(transaction, for: wallet.address)
        return try review(preparation, wallets: wallets)
    }

    /// Resolves a payment into instructions and uses the shared simulation workflow.
    ///
    /// - Parameters:
    ///   - amount: The positive amount in lamports or raw token units.
    ///   - token: The token mint, or `nil` for native SOL.
    ///   - wallet: The selected token authority and fee payer.
    ///   - recipient: The receiving wallet, or a token account for `token`.
    ///   - source: An optional non-associated source token account.
    ///   - memo: An optional memo immediately before the payment instruction.
    /// - Returns: The exact simulated transaction with applicable token and rent observations.
    /// - Throws: An account, instruction, resource, RPC, or cancellation error.
    func transfer(_ amount: UInt64, token: Address? = nil, using wallet: Account, to recipient: Address,
                  source: Address? = nil, memo: String? = nil) async throws -> Simulation {
        if let token {
            let resolved = try await tokens.transfer(mint: token, amount: amount, from: wallet.address,
                to: recipient, source: source, memo: memo)
            let preparation = try await preparer.prepare(resolved.transfer.instructions(), payer: wallet.address,
                signer: wallet.address, configuration: configuration, minimumSlot: resolved.slot)
            return try review(preparation, wallets: [wallet], token: resolved.transfer, rent: resolved.rent)
        }
        guard source == nil else { throw ValidationError.invalidMessage }
        var instructions: [Instruction] = []
        if let memo { instructions.append(try MemoProgram.memo(memo, signers: [wallet.address])) }
        instructions.append(try SystemProgram.transfer(from: wallet.address, to: recipient, lamports: amount))
        return try await simulate(instructions, using: [wallet])
    }

    /// Signs the approved review without broadcasting, including partial-signing requests.
    ///
    /// - Parameter simulation: The unchanged review whose details the user approved.
    /// - Returns: The exact transaction with the selected local signatures filled.
    /// - Throws: A review, authentication, signing, RPC, or cancellation error.
    func sign(_ simulation: Simulation) async throws -> Transaction {
        try await signed(simulation).transaction
    }

    /// Authenticates, signs, and sends the transaction after explicit approval.
    ///
    /// The message is never rebuilt. An expired review requires a new simulation
    /// and approval. Returns once sending settles and a route accepted the transaction,
    /// without waiting for its outcome; submission errors may leave delivery unknown.
    ///
    /// - Parameter simulation: The exact review approved by the user.
    /// - Returns: The receipt to observe with ``confirm(_:)``.
    /// - Throws: A review, authentication, signing, or cancellation error. After signing, a
    ///   ``DeliveryError`` that retains the receipt and the delivery or cancellation error.
    func submit(_ simulation: Simulation) async throws -> Submission {
        try validateOrigin(simulation)
        let local = Set(simulation.wallets.map(\.address))
        for (account, signature) in zip(simulation.transaction.accounts, simulation.transaction.signatures)
            where signature.allSatisfy({ $0 == 0 }) {
            guard local.contains(account.address) else { throw SubmitterError.missingSignatures }
        }
        let signed = try await signed(simulation)
        guard let signature = signed.signature else { throw SubmitterError.missingSignatures }
        let receipt = Submission(signature: signature, preparation: signed.preparation)
        do {
            return try await submitter.submit(signed)
        } catch {
            throw DeliveryError(submission: receipt, cause: error)
        }
    }

    /// Watches a sent transaction without reading recovery or sending it again.
    ///
    /// - Parameter submission: The receipt from ``submit(_:)`` or a ``DeliveryError``.
    /// - Returns: The succeeded, failed, or dropped outcome.
    /// - Throws: A ``DeliveryError`` that retains the receipt and the network, response, RPC,
    ///   or cancellation error.
    func confirm(_ submission: Submission) async throws -> Confirmation {
        do {
            return try await confirmer.confirm(submission)
        } catch {
            throw DeliveryError(submission: submission, cause: error)
        }
    }

    /// Adds local signatures while retaining the original review and all occupied slots.
    /// - Parameter simulation: The approved review bound to this coordinator.
    /// - Returns: A validated signed result for internal submission.
    /// - Throws: A review, authentication, signature, or cancellation error.
    private func signed(_ simulation: Simulation) async throws -> SignedTransaction {
        try validateOrigin(simulation)
        try await simulation.approval.consume()
        var transaction = simulation.transaction
        for wallet in simulation.wallets {
            let original = simulation.preparation
            let preparation = Preparation(source: original.source, signer: wallet.address, transaction: transaction,
                network: original.network, fee: original.fee, simulation: original.simulation, tips: original.tips)
            transaction = try await signer.sign(preparation, for: wallet,
                reason: String(localized: "Approve transaction")).transaction
        }
        return SignedTransaction(preparation: simulation.preparation, transaction: transaction)
    }

    /// Binds review observations to selected local accounts without accessing their recovery.
    /// - Parameters:
    ///   - preparation: The exact compiled or imported transaction and RPC observations.
    ///   - wallets: The local accounts whose empty required slots will be filled.
    ///   - token: Optional token-specific review details resolved before composition.
    ///   - rent: The observed account deposit, or `nil` when unestimated.
    /// - Returns: An immutable review with private authorization context.
    /// - Throws: A signer-selection error for duplicate, unrelated, or occupied slots.
    private func review(_ preparation: Preparation, wallets: [Account], token: TokenTransfer? = nil,
                        rent: UInt64? = nil) throws -> Simulation {
        for wallet in wallets {
            guard let index = preparation.transaction.accounts.firstIndex(where: { $0.address == wallet.address && $0.isSigner }) else {
                throw ValidationError.signerNotRequired
            }
            guard preparation.transaction.signatures[index].allSatisfy({ $0 == 0 }) else {
                throw ValidationError.signatureAlreadyPresent
            }
        }
        return Simulation(preparation: preparation, wallets: wallets, coordinator: id,
                          tokenTransfer: token, destinationAccountRent: rent)
    }

    /// Checks selected signers before beginning network work.
    /// - Parameter wallets: The local accounts supplied by the caller.
    /// - Returns: The first account, used as fee payer for local composition.
    /// - Throws: A validation error for an empty or duplicate selection.
    private func selectedWallet(in wallets: [Account]) throws -> Account {
        guard let first = wallets.first, Set(wallets.map(\.address)).count == wallets.count else {
            throw ValidationError.invalidMessage
        }
        return first
    }

    /// Prevents a review from silently changing provider or submission policy.
    /// - Parameter simulation: The review to bind to its original workflow.
    /// - Throws: A validation error when another coordinator produced the review.
    private func validateOrigin(_ simulation: Simulation) throws {
        guard simulation.coordinator == id else { throw ValidationError.invalidTransaction }
    }
}

/// The exact transaction and observations to present before requesting approval.
nonisolated struct Simulation: Sendable {
    fileprivate let preparation: Preparation
    fileprivate let wallets: [Account]
    fileprivate let coordinator: UUID
    fileprivate let approval = Approval()
    /// The locally resolved token debit, fee, and destination, when applicable.
    let tokenTransfer: TokenTransfer?
    /// The estimated destination deposit; `nil` means this composition doesn't estimate it.
    let destinationAccountRent: UInt64?
    /// The complete ordered instructions, accounts, resource requests, and signature slots.
    var transaction: Transaction { preparation.transaction }
    /// The network used for all review observations.
    var network: Network { preparation.network }
    /// The network fee, including its priority fee; `nil` remains unknown.
    var fee: UInt64? { preparation.fee.value }
    /// The original local block-height expiry, or `nil` for imported recent blockhashes.
    var lastValidBlockHeight: UInt64? {
        guard case .local = preparation.source else { return nil }
        return preparation.source.lastValidBlockHeight
    }
    /// The final RPC simulation, retaining execution failures and their diagnostics.
    var diagnostics: SimulateTransaction.Response { preparation.simulation }
    /// The balances the node observed changing, or `nil` when they're unknown.
    ///
    /// Changes are observations of simulated execution, not a cost claim, intent, or safety judgment.
    var balanceChanges: [BalanceChange]? { BalanceChange.changes(in: transaction, from: diagnostics.value) }
    /// The separate service payments included before approval.
    var tips: [SubmissionRequirements] { preparation.tips }

    /// Creates a review only through the coordinator that will later authorize it.
    /// - Parameters:
    ///   - preparation: The exact transaction and its observations.
    ///   - wallets: The selected local signers.
    ///   - coordinator: The identity of the originating workflow.
    ///   - tokenTransfer: Optional token-specific observations.
    ///   - destinationAccountRent: The optional account deposit estimate.
    fileprivate init(preparation: Preparation, wallets: [Account], coordinator: UUID,
                     tokenTransfer: TokenTransfer?, destinationAccountRent: UInt64?) {
        self.preparation = preparation
        self.wallets = wallets
        self.coordinator = coordinator
        self.tokenTransfer = tokenTransfer
        self.destinationAccountRent = destinationAccountRent
    }
}

/// Serializes consent consumption across copies and concurrent uses of one review.
fileprivate actor Approval {
    private var consumed = false

    /// Creates unused approval state for one simulation.
    init() {}

    /// Reserves the only signing attempt before awaiting authentication or provider work.
    /// - Throws: A cancellation error or an already-used review error.
    func consume() throws {
        try Task.checkCancellation()
        guard !consumed else { throw TransactionCoordinatorError.reviewAlreadyUsed }
        consumed = true
    }
}
