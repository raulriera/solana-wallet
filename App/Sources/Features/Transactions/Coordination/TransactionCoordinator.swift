import Foundation
import RPC
import Transactions
import Vault

/// A coordinator that simulates, signs, sends, and watches transactions.
nonisolated struct TransactionCoordinator: TransactionCoordinating {
    /// A way to submit transactions.
    enum Strategy: Sendable {
        /// Submits through the provider, without a Sender tip.
        case none
        /// Submits only through Sender's lower-cost route.
        case standard
        /// Submits only through Sender's broader routes, with a higher tip.
        case premium

        /// Returns the paid submission service of this strategy on a network.
        ///
        /// - Parameter network: The provider's network.
        /// - Returns: The submission service, or `nil` for `.none`, which submits through the provider.
        /// - Throws: ``TransactionCoordinatorError/unsupportedNetwork`` if the service doesn't serve the network.
        func service(on network: Network) throws -> (any SubmissionProviding)? {
            let service: (any SubmissionProviding)? = switch self {
            case .none: nil
            case .standard: SenderSubmissionProvider(tier: .standard)
            case .premium: SenderSubmissionProvider(tier: .premium)
            }
            if let service, service.network != network { throw TransactionCoordinatorError.unsupportedNetwork }
            return service
        }
    }

    /// The localized reason for the authentication that signs a transaction.
    private static var approvalReason: String { String(localized: "Approve transaction") }

    private let id = UUID()
    private let tokens: TokenTransfers
    private let configuration: Configuration?
    private let preparer: any TransactionPreparing
    private var signer: any TransactionSigning
    private let submitter: any TransactionSubmitting
    private let confirmer: any TransactionConfirming

    /// Creates a coordinator with a provider and a recovery store.
    ///
    /// - Parameters:
    ///   - rpc: The provider that reads, simulates, and watches transactions, and submits them for `.none`.
    ///   - store: The recovery store that authenticates access to saved accounts.
    ///   - strategy: The submission strategy.
    ///   - configuration: The priority fee and resource limits, or `nil` to estimate them.
    /// - Throws: ``TransactionCoordinatorError/unsupportedNetwork`` if the strategy has no route on the provider's
    ///   network.
    init(rpc: any RPC & SignatureEventProviding, store: any RecoveryStoring, strategy: Strategy = .none,
         configuration: Configuration? = nil) throws {
        let service = try strategy.service(on: rpc.network)
        self.init(rpc: rpc, configuration: configuration,
                  preparer: Preparer(rpc: rpc, requirements: service?.submissionRequirements),
                  signer: Signer(validator: PreparationValidator(rpc: rpc), store: store),
                  submitter: Submitter(rpc: service ?? rpc), confirmer: Confirmer(rpc: rpc))
    }

    /// Creates a coordinator with the given transaction services.
    ///
    /// - Parameters:
    ///   - rpc: The provider that reads token accounts.
    ///   - configuration: The priority fee and resource limits, or `nil` to estimate them.
    ///   - preparer: The service that prepares transactions.
    ///   - signer: The service that signs approved preparations.
    ///   - submitter: The service that sends signed transactions.
    ///   - confirmer: The service that watches sent transactions.
    init(rpc: any RPC, configuration: Configuration? = nil, preparer: any TransactionPreparing, signer: any TransactionSigning,
         submitter: any TransactionSubmitting, confirmer: any TransactionConfirming) {
        tokens = TokenTransfers(rpc: rpc)
        self.configuration = configuration
        self.preparer = preparer
        self.signer = signer
        self.submitter = submitter
        self.confirmer = confirmer
    }

    func simulate(_ instructions: [Instruction], using authorities: [Authority]) async throws -> Simulation {
        let payer = try payer(in: authorities)
        let preparation = try await preparer.prepare(instructions, payer: payer, signer: payer,
            configuration: configuration, minimumSlot: nil)
        return try review(preparation, authorities: authorities)
    }

    func simulate(_ transaction: Transaction, using wallets: [Account]) async throws -> Simulation {
        let authorities = wallets.map(Authority.account)
        let preparation = try await preparer.prepare(transaction, for: payer(in: authorities))
        return try review(preparation, authorities: authorities)
    }

    func transfer(_ amount: UInt64, of asset: Asset, using wallet: Account, to recipient: Address,
                  source: Address?, memo: String?) async throws -> Simulation {
        switch asset {
        case .token(let mint):
            let resolved = try await tokens.transfer(mint: mint, amount: amount, from: wallet.address,
                to: recipient, source: source, memo: memo)
            let preparation = try await preparer.prepare(resolved.transfer.instructions(), payer: wallet.address,
                signer: wallet.address, configuration: configuration, minimumSlot: resolved.slot)
            return try review(preparation, authorities: [.account(wallet)], token: resolved.transfer, rent: resolved.rent)
        case .nativeSOL:
            guard source == nil else { throw ValidationError.invalidMessage }
            var instructions: [Instruction] = []
            if let memo { instructions.append(try MemoProgram.memo(memo, signers: [wallet.address])) }
            instructions.append(try SystemProgram.transfer(from: wallet.address, to: recipient, lamports: amount))
            return try await simulate(instructions, using: [.account(wallet)])
        }
    }

    func sign(_ simulation: Simulation) async throws -> Transaction {
        try await signed(simulation).transaction
    }

    func submit(_ simulation: Simulation) async throws -> TransactionOutcome {
        try validateOrigin(simulation)
        let local = Set(try simulation.authorities.map { try $0.address })
        for (account, signature) in zip(simulation.transaction.accounts, simulation.transaction.signatures)
            where signature.allSatisfy({ $0 == 0 }) {
            guard local.contains(account.address) else { throw SubmitterError.missingSignatures }
        }
        return try await submitter.submit(signed(simulation))
    }

    func withSharedAuthentication<Value: Sendable>(
        _ operation: @Sendable (any TransactionCoordinating) async throws -> Value
    ) async throws -> Value {
        try await signer.withSharedAuthentication(reason: Self.approvalReason) { signer in
            var coordinator = self
            coordinator.signer = signer
            return try await operation(coordinator)
        }
    }

    func confirm(_ pending: TransactionOutcome, of transaction: Transaction) async throws -> TransactionOutcome {
        try await confirmer.confirm(pending, of: transaction)
    }

    /// Signs an approved simulation with each of its authorities in order.
    ///
    /// - Parameter simulation: The approved simulation from this coordinator.
    /// - Returns: The signed transaction.
    /// - Throws: A validation, authentication, signing, or cancellation error.
    private func signed(_ simulation: Simulation) async throws -> SignedTransaction {
        try validateOrigin(simulation)
        try await simulation.approval.consume()
        var transaction = simulation.transaction
        for authority in simulation.authorities {
            let original = simulation.preparation
            let preparation = Preparation(source: original.source, signer: try authority.address, transaction: transaction,
                network: original.network, fee: original.fee, simulation: original.simulation,
                requirements: original.requirements)
            transaction = try await signer.sign(preparation, for: authority, reason: Self.approvalReason).transaction
        }
        return SignedTransaction(preparation: simulation.preparation, transaction: transaction)
    }

    /// Creates a simulation of a preparation for its signing authorities.
    ///
    /// - Parameters:
    ///   - preparation: The prepared transaction.
    ///   - authorities: The accounts whose empty signature slots get filled.
    ///   - token: The resolved token transfer, or `nil` for none.
    ///   - rent: The new destination account's rent in lamports, or `nil` if not estimated.
    /// - Returns: The simulation to review.
    /// - Throws: A validation error for an authority that isn't a required signer or already signed.
    private func review(_ preparation: Preparation, authorities: [Authority], token: TokenTransfer? = nil,
                        rent: UInt64? = nil) throws -> Simulation {
        for authority in authorities {
            let address = try authority.address
            guard let index = preparation.transaction.accounts.firstIndex(where: { $0.address == address && $0.isSigner }) else {
                throw ValidationError.signerNotRequired
            }
            guard preparation.transaction.signatures[index].allSatisfy({ $0 == 0 }) else {
                throw ValidationError.signatureAlreadyPresent
            }
        }
        return Simulation(preparation: preparation, authorities: authorities, coordinator: id,
                          tokenTransfer: token, destinationAccountRent: rent)
    }

    /// Returns the fee payer among authorities.
    ///
    /// - Parameter authorities: The authorities that sign.
    /// - Returns: The first authority's address.
    /// - Throws: A validation error for an empty or duplicate selection.
    private func payer(in authorities: [Authority]) throws -> Address {
        let addresses = try authorities.map { try $0.address }
        guard let first = addresses.first, Set(addresses).count == addresses.count else {
            throw ValidationError.invalidMessage
        }
        return first
    }

    /// Checks that this coordinator created a simulation.
    ///
    /// - Parameter simulation: The simulation to check.
    /// - Throws: A validation error if another coordinator created the simulation.
    private func validateOrigin(_ simulation: Simulation) throws {
        guard simulation.coordinator == id else { throw ValidationError.invalidTransaction }
    }
}

/// A simulated transaction that a person reviews before approving it.
nonisolated struct Simulation: Sendable {
    fileprivate let preparation: Preparation
    fileprivate let authorities: [Authority]
    fileprivate let coordinator: UUID
    fileprivate let approval = Approval()
    /// The resolved token transfer, or `nil` for other transactions.
    let tokenTransfer: TokenTransfer?
    /// The new destination account's rent in lamports, or `nil` if not estimated.
    let destinationAccountRent: UInt64?
    var transaction: Transaction { preparation.transaction }
    var network: Network { preparation.network }
    /// The network fee in lamports, including its priority fee, or `nil` if unknown.
    var fee: UInt64? { preparation.fee.value }
    /// The simulation's response, including any execution error.
    var diagnostics: SimulateTransaction.Response { preparation.simulation }
    /// Why the simulated transaction can't run, or `nil` if it ran.
    var executionError: ExecutionError? { diagnostics.value.error.map { ExecutionError($0, in: transaction) } }
    /// The balances that the simulation changed, or `nil` if unknown.
    var balanceChanges: [BalanceChange]? { BalanceChange.changes(in: transaction, from: diagnostics.value) }
    /// The submitting service's requirements, whose tip the transaction pays, or `nil` for none.
    var requirements: SubmissionRequirements? { preparation.requirements }

    /// Creates a simulation.
    ///
    /// - Parameters:
    ///   - preparation: The prepared transaction.
    ///   - authorities: The accounts that sign, in signing order.
    ///   - coordinator: The identifier of the coordinator that created it.
    ///   - tokenTransfer: The resolved token transfer, or `nil` for none.
    ///   - destinationAccountRent: The new destination account's rent in lamports, or `nil` if not estimated.
    fileprivate init(preparation: Preparation, authorities: [Authority], coordinator: UUID,
                     tokenTransfer: TokenTransfer?, destinationAccountRent: UInt64?) {
        self.preparation = preparation
        self.authorities = authorities
        self.coordinator = coordinator
        self.tokenTransfer = tokenTransfer
        self.destinationAccountRent = destinationAccountRent
    }
}

/// A one-time approval that a simulation's copies share.
fileprivate actor Approval {
    private var consumed = false

    /// Creates an unused approval.
    init() {}

    /// Marks the approval as used.
    ///
    /// - Throws: A cancellation error, or ``TransactionCoordinatorError/reviewAlreadyUsed`` if it was used.
    func consume() throws {
        try Task.checkCancellation()
        guard !consumed else { throw TransactionCoordinatorError.reviewAlreadyUsed }
        consumed = true
    }
}
