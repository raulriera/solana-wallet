import Foundation
import RPC
import Transactions

/// A stateless service that evaluates exact V1 bytes through an injected RPC provider.
nonisolated struct Preparer: TransactionPreparing {
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

    /// Compiles and simulates ordered instructions without accessing wallet recovery.
    ///
    /// Service tips precede the caller's instructions, so the caller's last instruction stays last.
    /// Automatic resource estimation happens before the final review. Explicit
    /// configuration is preserved. No instructions or requests change after review.
    ///
    /// - Parameters:
    ///   - instructions: The ordered invocations composing one atomic transaction.
    ///   - payer: The transaction fee payer, independent of instruction authorities.
    ///   - signer: The wallet account selected for later signing.
    ///   - configuration: Explicit requests, or `nil` to estimate resources.
    ///   - minimumSlot: The earliest ledger context permitted by resolved instructions.
    /// - Returns: The exact final transaction, fee, expiry, and simulation diagnostics.
    /// - Throws: A composition, resource estimation, RPC, or cancellation error.
    @concurrent
    func prepare(_ instructions: [Instruction], payer: Address, signer: Address,
                 configuration: Configuration? = nil, minimumSlot: UInt64? = nil) async throws -> Preparation {
        try Task.checkCancellation()
        let minimumFee = requirements.map(\.minimumPriorityFeeLamports).max() ?? 0
        var requests = try configuration ?? Configuration(priorityFeeLamports: minimumFee,
            computeUnitLimit: 1_400_000, loadedAccountsDataSizeLimit: 67_108_864)
        guard requests.priorityFeeLamports >= minimumFee else {
            throw PreparerError.priorityFeeTooLow(minimumLamports: minimumFee)
        }
        let tips = try requirements.map {
            try SystemProgram.transfer(from: payer, to: Address($0.tipRecipient), lamports: $0.tipLamports)
        }
        let invocations = tips + instructions
        let blockhash = try await rpc.send(GetLatestBlockhash(commitment: .confirmed, minContextSlot: minimumSlot))
        try Task.checkCancellation()
        guard blockhash.context.slot >= (minimumSlot ?? 0) else { throw PreparerError.inconsistentResponse }
        var message = try messageBuilder.message(instructions: invocations, payer: payer,
            recentBlockhash: blockhash.value.blockhash, configuration: requests)
        var transaction = try transactionBuilder.validateSignatures(in:
            transactionBuilder.simulationTransaction(for: message), for: signer)
        var context = blockhash.context.slot
        if configuration == nil {
            let estimate = try await rpc.send(SimulateTransaction(transaction: transaction.serializedRepresentation,
                commitment: .confirmed, minContextSlot: context, verifiesSignatures: false,
                replacesRecentBlockhash: false))
            try Task.checkCancellation()
            guard estimate.context.slot >= context, estimate.value.replacementBlockhash == nil else {
                throw PreparerError.inconsistentResponse
            }
            context = estimate.context.slot
            if estimate.value.error == nil {
                guard let units = estimate.value.unitsConsumed, let bytes = estimate.value.loadedAccountsDataSize,
                      units <= 1_400_000, bytes <= 67_108_864 else { throw PreparerError.resourceUsageUnavailable }
                requests = try Configuration(priorityFeeLamports: minimumFee,
                    computeUnitLimit: UInt32(min(1_400_000, max(1, units + (units + 9) / 10))),
                    loadedAccountsDataSizeLimit: UInt32(min(67_108_864, max(1, bytes + (bytes + 9) / 10))))
                message = try messageBuilder.message(instructions: invocations, payer: payer,
                    recentBlockhash: blockhash.value.blockhash, configuration: requests)
                transaction = try transactionBuilder.validateSignatures(in:
                    transactionBuilder.simulationTransaction(for: message), for: signer)
            }
        }
        return try await evaluate(transaction, source: .local(invocations, payer, requests, blockhash),
                                  signer: signer, network: rpc.network, minimumSlot: context, tips: requirements)
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
        guard validity.value else { throw PreparerError.invalidBlockhash }
        return try await evaluate(transaction, source: .external(validity.context), signer: signer, network: network)
    }

    /// Retrieves the fee and final simulation concurrently.
    ///
    /// - Parameters:
    ///   - transaction: The exact inspected message and existing signature slots.
    ///   - source: The original construction intent or external validity context.
    ///   - signer: The selected required signer.
    ///   - network: The provider's network captured before the first request.
    ///   - minimumSlot: The latest resource-estimation context, when applicable.
    ///   - tips: The service payments added before compilation.
    /// - Returns: An immutable review that retains execution failures and unknown fees.
    /// - Throws: An RPC error or cancellation; structured child requests are cancelled together.
    private func evaluate(_ transaction: Transaction, source: Preparation.Source, signer: Address,
                  network: Network, minimumSlot: UInt64? = nil,
                  tips: [SubmissionRequirements] = []) async throws -> Preparation {
        try Task.checkCancellation()
        async let fee = rpc.send(GetFeeForMessage(
            message: transaction.message, commitment: .confirmed, minContextSlot: minimumSlot ?? source.context.slot
        ))
        async let simulation = rpc.send(SimulateTransaction(
            transaction: transaction.serializedRepresentation, commitment: .confirmed, minContextSlot: minimumSlot ?? source.context.slot,
            verifiesSignatures: false, replacesRecentBlockhash: false
        ))
        let observations = try await (fee, simulation)
        try Task.checkCancellation()
        let floor = minimumSlot ?? source.context.slot
        guard observations.0.context.slot >= floor, observations.1.context.slot >= floor,
              observations.1.value.replacementBlockhash == nil else { throw PreparerError.inconsistentResponse }
        return Preparation(
            source: source, signer: signer, transaction: transaction, network: network,
            fee: observations.0, simulation: observations.1, tips: tips
        )
    }
}
