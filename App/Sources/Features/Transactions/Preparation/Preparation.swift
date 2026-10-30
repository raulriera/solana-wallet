import Foundation
import RPC
import Transactions

/// A transaction ready for approval, with its signer, fee, and simulation.
nonisolated struct Preparation: Sendable {
    /// Where a transaction came from and when its blockhash expires.
    enum Source: Sendable {
        /// Local instructions, in order, with their fee payer, resource requests, and blockhash.
        case local([Instruction], Address, Configuration, GetLatestBlockhash.Response)
        /// An imported transaction, with the context that checked its blockhash and an upper bound on its expiry.
        case external(Context, lastValidBlockHeight: UInt64)

        /// The context that fee estimation, simulation, and validation start from.
        var context: Context {
            switch self {
            case .local(_, _, _, let blockhash): blockhash.context
            case .external(let context, _): context
            }
        }

        /// The last block height at which the blockhash is valid, or an upper bound for an imported transaction.
        var lastValidBlockHeight: UInt64 {
            switch self {
            case .local(_, _, _, let blockhash): blockhash.value.lastValidBlockHeight
            case .external(_, let lastValidBlockHeight): lastValidBlockHeight
            }
        }
    }

    let source: Source
    let signer: Address
    let transaction: Transaction
    let network: Network
    /// The network fee with its context; the fee is `nil` if unknown.
    let fee: GetFeeForMessage.Response
    let simulation: SimulateTransaction.Response
    /// The services whose tips the transaction pays.
    let tips: [SubmissionRequirements]

    var message: Data { transaction.message }

    /// The serialized transaction.
    var bytes: Data { transaction.serializedRepresentation }

    /// The newest slot among the preparation's reads.
    var minimumSlot: UInt64 { max(source.context.slot, fee.context.slot, simulation.context.slot) }

    /// Creates a preparation.
    ///
    /// - Parameters:
    ///   - source: Where the transaction came from.
    ///   - signer: The account that signs.
    ///   - transaction: The transaction to approve.
    ///   - network: The network of every read.
    ///   - fee: The network fee and its context.
    ///   - simulation: The simulation and its context.
    ///   - tips: The services whose tips the transaction pays.
    init(source: Source, signer: Address, transaction: Transaction, network: Network,
         fee: GetFeeForMessage.Response, simulation: SimulateTransaction.Response,
         tips: [SubmissionRequirements] = []) {
        self.source = source
        self.signer = signer
        self.transaction = transaction
        self.network = network
        self.fee = fee
        self.simulation = simulation
        self.tips = tips
    }
}
