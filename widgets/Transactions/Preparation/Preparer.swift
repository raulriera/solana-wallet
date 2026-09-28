import Foundation
import RPC
import Transactions

/// A stateless service that evaluates exact V1 bytes through an injected RPC provider.
nonisolated struct Preparer: TransactionPreparing {
    /// A preparation requirement that the supplied transaction or configuration doesn't meet.
    enum Failure: Error, Sendable, Equatable {
        /// The node cannot confirm the supplied value as a valid recent blockhash.
        case invalidBlockhash
        /// The selected submission service requires a larger reviewed priority fee.
        case priorityFeeTooLow(minimumLamports: UInt64)
        /// A mint or source token account doesn't exist on the selected network.
        case missingAccount(Address)
        /// Account observations have an unexpected count or an older ledger context.
        case inconsistentAccounts
    }
    let rpc: any RPC
    let messageBuilder: any MessageBuilding & TokenMessageBuilding
    let transactionBuilder: any TransactionBuilding
    private let requirements: [SubmissionRequirements]

    /// Creates a service with a provider and local V1 encoders.
    ///
    /// - Parameters:
    ///   - rpc: The provider supplying the blockhash, fee, and simulation.
    ///   - rpcs: Submission clients whose same-network payment requirements must be reviewed.
    ///   - messageBuilder: The unsigned message encoder. The default is `MessageBuilder`.
    ///   - transactionBuilder: The simulation envelope encoder. The default is `TransactionBuilder`.
    init(
        rpc: any RPC,
        rpcs: [any RPC]? = nil,
        messageBuilder: any MessageBuilding & TokenMessageBuilding = MessageBuilder(),
        transactionBuilder: any TransactionBuilding = TransactionBuilder()
    ) {
        self.rpc = rpc
        self.messageBuilder = messageBuilder
        self.transactionBuilder = transactionBuilder
        requirements = (rpcs ?? [rpc]).filter { $0.network == rpc.network }.compactMap(\.submissionRequirements)
    }

    /// Builds and evaluates the same unsigned message at confirmed commitment.
    ///
    /// Fee estimation and simulation run concurrently, at or after the blockhash's
    /// context slot. Simulation neither verifies signatures nor replaces the blockhash.
    /// Each request is attempted once; signing and submission are separate operations.
    ///
    /// - Parameters:
    ///   - transfer: The validated native SOL transfer.
    ///   - configuration: The explicit priority fee and execution resource limits.
    /// - Returns: Immutable review data, including unsuccessful simulation results.
    /// - Throws: ``Failure/priorityFeeTooLow(minimumLamports:)`` if a service requires a
    ///   higher fee, a construction or RPC error, or `CancellationError` if cancelled.
    @concurrent
    func prepare(_ transfer: Transfer, configuration: Configuration) async throws -> Preparation {
        try Task.checkCancellation()
        let tips = try serviceTips(from: transfer.sender, configuration: configuration)
        let transfers = [transfer] + tips
        let network = rpc.network
        let blockhash = try await rpc.send(GetLatestBlockhash(commitment: .confirmed))
        try Task.checkCancellation()
        let message = try messageBuilder.message(
            for: transfers, recentBlockhash: blockhash.value.blockhash, configuration: configuration
        )
        let transaction = try transactionBuilder.validateSignatures(in:
            transactionBuilder.simulationTransaction(for: message), for: transfer.sender
        )
        return try await evaluate(transaction, source: .transfer(transfers, configuration, blockhash),
                                  signer: transfer.sender, network: network)
    }

    /// Validates an imported transaction and its blockhash without accessing protected recovery.
    ///
    /// - Parameters:
    ///   - imported: The typed transaction supplied by the import boundary.
    ///   - signer: The account whose required signature slot must be empty.
    /// - Returns: The unchanged transaction and network observations available for review.
    /// - Throws: A validation, blockhash, RPC, or cancellation error.
    @concurrent
    func prepare(_ imported: Transaction, for signer: Address) async throws -> Preparation {
        try Task.checkCancellation()
        let network = rpc.network
        let transaction = try transactionBuilder.validateSignatures(in: imported.serializedRepresentation, for: signer)
        guard transaction == imported else { throw ValidationError.invalidTransaction }
        let validity = try await rpc.send(IsBlockhashValid(blockhash: transaction.lifetimeSpecifier))
        try Task.checkCancellation()
        guard validity.value else { throw Failure.invalidBlockhash }
        return try await evaluate(transaction, source: .external(validity.context), signer: signer, network: network)
    }

    /// Retrieves fee, simulation, and applicable destination-rent estimates concurrently.
    ///
    /// - Parameters:
    ///   - transaction: The exact inspected message and existing signature slots.
    ///   - source: The original construction intent or external validity context.
    ///   - signer: The selected required signer.
    ///   - network: The provider's network captured before the first request.
    /// - Returns: An immutable review that retains execution failures and unknown fees.
    /// - Throws: An RPC error or cancellation; structured child requests are cancelled together.
    func evaluate(_ transaction: Transaction, source: Preparation.Source, signer: Address,
                          network: Network) async throws -> Preparation {
        try Task.checkCancellation()
        async let fee = rpc.send(GetFeeForMessage(
            message: transaction.message, commitment: .confirmed, minContextSlot: source.context.slot
        ))
        async let simulation = rpc.send(SimulateTransaction(
            transaction: transaction.serializedRepresentation, commitment: .confirmed, minContextSlot: source.context.slot,
            verifiesSignatures: false, replacesRecentBlockhash: false
        ))
        async let rent = destinationAccountRent(for: source)
        let observations = try await (fee, simulation, rent)
        try Task.checkCancellation()
        return Preparation(
            source: source, signer: signer, transaction: transaction, network: network,
            fee: observations.0, simulation: observations.1, destinationAccountRent: observations.2
        )
    }

    /// Validates the selected service's fee floor and constructs its reviewed payments.
    ///
    /// - Parameters:
    ///   - sender: The transaction signer paying the service tips.
    ///   - configuration: The explicit priority fee, which is never increased automatically.
    /// - Returns: The selected clients' native SOL tips.
    /// - Throws: A fee requirement or transfer validation error.
    func serviceTips(from sender: Address, configuration: Configuration) throws -> [Transfer] {
        let minimumFee = requirements.map(\.minimumPriorityFeeLamports).max() ?? 0
        guard configuration.priorityFeeLamports >= minimumFee else {
            throw Failure.priorityFeeTooLow(minimumLamports: minimumFee)
        }
        return try requirements.map {
            try Transfer(sender: sender, recipient: Address($0.tipRecipient), lamports: $0.tipLamports)
        }
    }
}
