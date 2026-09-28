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
    }
    private let rpc: any RPC
    private let messageBuilder: any MessageBuilding
    private let transactionBuilder: any TransactionBuilding
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
        messageBuilder: any MessageBuilding = MessageBuilder(),
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
        let minimumFee = requirements.map(\.minimumPriorityFeeLamports).max() ?? 0
        guard configuration.priorityFeeLamports >= minimumFee else {
            throw Failure.priorityFeeTooLow(minimumLamports: minimumFee)
        }
        let tips = try requirements.map {
            try Transfer(sender: transfer.sender, recipient: Address($0.tipRecipient), lamports: $0.tipLamports)
        }
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

    /// Retrieves fee and simulation observations for either preparation path.
    ///
    /// - Parameters:
    ///   - transaction: The exact inspected message and existing signature slots.
    ///   - source: The original construction intent or external validity context.
    ///   - signer: The selected required signer.
    ///   - network: The provider's network captured before the first request.
    /// - Returns: An immutable review that retains execution failures and unknown fees.
    /// - Throws: An RPC error or cancellation; structured child requests are cancelled together.
    private func evaluate(_ transaction: Transaction, source: Preparation.Source, signer: Address,
                          network: Network) async throws -> Preparation {
        try Task.checkCancellation()
        async let fee = rpc.send(GetFeeForMessage(
            message: transaction.message, commitment: .confirmed, minContextSlot: source.context.slot
        ))
        async let simulation = rpc.send(SimulateTransaction(
            transaction: transaction.serializedRepresentation, commitment: .confirmed, minContextSlot: source.context.slot,
            verifiesSignatures: false, replacesRecentBlockhash: false
        ))
        let observations = try await (fee, simulation)
        try Task.checkCancellation()
        return Preparation(
            source: source, signer: signer, transaction: transaction, network: network,
            fee: observations.0, simulation: observations.1
        )
    }
}
