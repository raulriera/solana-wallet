import Foundation
import RPC
import Transactions

/// A preparer that compiles and simulates transactions through a provider.
nonisolated struct Preparer: TransactionPreparing {
    private let rpc: any RPC
    private let messageBuilder: any MessageBuilding = MessageBuilder()
    private let transactionBuilder: any TransactionBuilding = TransactionBuilder()
    private let requirements: SubmissionRequirements?

    /// Creates a preparer.
    ///
    /// - Parameters:
    ///   - rpc: The provider that reads the blockhash, fee, and simulation.
    ///   - requirements: The submitting service's requirements, whose tip the transaction pays, or `nil` for none.
    init(rpc: any RPC, requirements: SubmissionRequirements? = nil) {
        self.rpc = rpc
        self.requirements = requirements
    }

    @concurrent
    func prepare(_ instructions: [Instruction], payer: Address, signer: Address,
                 configuration: Configuration? = nil, minimumSlot: UInt64? = nil) async throws -> Preparation {
        try Task.checkCancellation()
        let minimumFee = requirements?.minimumPriorityFeeLamports ?? 0
        var requests = try configuration ?? resourceRequests(priorityFee: minimumFee)
        guard requests.priorityFeeLamports >= minimumFee else {
            throw PreparerError.priorityFeeTooLow(minimumLamports: minimumFee)
        }
        var invocations = instructions
        if let requirements {
            invocations.insert(try SystemProgram.transfer(from: payer, to: Address(requirements.tipRecipient),
                                                          lamports: requirements.tipLamports), at: 0)
        }
        let blockhash = try await rpc.send(GetLatestBlockhash(minContextSlot: minimumSlot))
        try Task.checkCancellation()
        var transaction = try simulationTransaction(invocations, payer: payer, blockhash: blockhash.value.blockhash,
                                                    requests: requests, signer: signer)
        var context = blockhash.context.slot
        if configuration == nil {
            let estimate = try await rpc.send(SimulateTransaction(transaction: transaction.serializedRepresentation,
                minContextSlot: context))
            try Task.checkCancellation()
            context = estimate.context.slot
            if estimate.value.error == nil {
                guard let units = estimate.value.unitsConsumed, let bytes = estimate.value.loadedAccountsDataSize else {
                    throw PreparerError.resourceUsageUnavailable
                }
                requests = try resourceRequests(priorityFee: minimumFee, measured: (units, UInt64(bytes)))
                transaction = try simulationTransaction(invocations, payer: payer, blockhash: blockhash.value.blockhash,
                                                        requests: requests, signer: signer)
            }
        }
        return try await evaluate(transaction, source: .local(invocations, payer, requests, blockhash),
                                  signer: signer, network: rpc.network, minimumSlot: context, requirements: requirements)
    }

    /// Returns a priority fee with the network's resource limits, or with a tenth more than the measured usage.
    ///
    /// - Parameters:
    ///   - priorityFee: The priority fee in lamports.
    ///   - measured: The simulated compute units and loaded account bytes, or `nil` to request the limits.
    /// - Returns: The priority fee and resource requests.
    /// - Throws: ``PreparerError/resourceUsageUnavailable`` when measured usage exceeds a limit, or a configuration
    ///   error.
    private func resourceRequests(priorityFee: UInt64, measured: (units: UInt64, bytes: UInt64)? = nil) throws
        -> Configuration {
        let limits: (units: UInt64, bytes: UInt64) = (1_400_000, 67_108_864)
        guard (measured?.units ?? 0) <= limits.units, (measured?.bytes ?? 0) <= limits.bytes else {
            throw PreparerError.resourceUsageUnavailable
        }
        let units = measured.map { min(limits.units, max(1, $0.units + ($0.units + 9) / 10)) } ?? limits.units
        let bytes = measured.map { min(limits.bytes, max(1, $0.bytes + ($0.bytes + 9) / 10)) } ?? limits.bytes
        return try Configuration(priorityFeeLamports: priorityFee, computeUnitLimit: UInt32(units),
                                 loadedAccountsDataSizeLimit: UInt32(bytes))
    }

    /// Compiles instructions into an unsigned transaction for simulation.
    ///
    /// - Parameters:
    ///   - invocations: The instructions, the service tip first.
    ///   - payer: The account that pays the fees.
    ///   - blockhash: The recent blockhash.
    ///   - requests: The priority fee and resource requests.
    ///   - signer: The account whose signature slot must be empty.
    /// - Returns: The unsigned transaction.
    /// - Throws: A composition or validation error.
    private func simulationTransaction(_ invocations: [Instruction], payer: Address, blockhash: String,
                                       requests: Configuration, signer: Address) throws -> Transaction {
        let message = try messageBuilder.message(instructions: invocations, payer: payer, recentBlockhash: blockhash,
                                                 configuration: requests)
        return try transactionBuilder.validateSignatures(in: transactionBuilder.simulationTransaction(for: message),
                                                         for: signer)
    }

    @concurrent
    func prepare(_ imported: Transaction, for signer: Address) async throws -> Preparation {
        try Task.checkCancellation()
        let network = rpc.network
        let transaction = try transactionBuilder.validateSignatures(in: imported.serializedRepresentation, for: signer)
        guard transaction == imported else { throw ValidationError.invalidTransaction }
        let validity = try await rpc.send(IsBlockhashValid(blockhash: transaction.lifetimeSpecifier))
        try Task.checkCancellation()
        guard validity.value else { throw PreparerError.invalidBlockhash }
        let height = try await rpc.send(GetBlockHeight(minContextSlot: validity.context.slot))
        try Task.checkCancellation()
        let (lastValidBlockHeight, overflow) = height.addingReportingOverflow(150)
        guard !overflow else { throw PreparerError.expiryOutOfRange }
        return try await evaluate(transaction, source: .external(validity.context, lastValidBlockHeight: lastValidBlockHeight),
                                  signer: signer, network: network)
    }

    /// Reads a transaction's fee and simulation at once.
    ///
    /// - Parameters:
    ///   - transaction: The transaction to evaluate.
    ///   - source: Where the transaction came from.
    ///   - signer: The account that signs.
    ///   - network: The provider's network.
    ///   - minimumSlot: The earliest slot for the reads, or `nil` for the source's context.
    ///   - requirements: The submitting service's requirements, whose tip the transaction pays, or `nil` for none.
    /// - Returns: The preparation.
    /// - Throws: An RPC or cancellation error.
    private func evaluate(_ transaction: Transaction, source: Preparation.Source, signer: Address,
                  network: Network, minimumSlot: UInt64? = nil,
                  requirements: SubmissionRequirements? = nil) async throws -> Preparation {
        try Task.checkCancellation()
        async let fee = rpc.send(GetFeeForMessage(
            message: transaction.message, minContextSlot: minimumSlot ?? source.context.slot
        ))
        async let simulation = rpc.send(SimulateTransaction(
            transaction: transaction.serializedRepresentation, minContextSlot: minimumSlot ?? source.context.slot
        ))
        let observations = try await (fee, simulation)
        try Task.checkCancellation()
        return Preparation(
            source: source, signer: signer, transaction: transaction, network: network,
            fee: observations.0, simulation: observations.1, requirements: requirements
        )
    }
}
