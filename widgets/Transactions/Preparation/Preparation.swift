import Foundation
import RPC
import Transactions

/// The exact transaction, selected signer, and observations presented for approval.
///
/// Simulation doesn't establish program intent, user consent, or future execution.
nonisolated struct Preparation: Sendable {
    /// The construction intent or the context that validated an externally supplied hash.
    enum Source: Sendable {
        /// A primary SOL transfer followed by service tips, configuration, and block-height expiry.
        case transfer([Transfer], Configuration, GetLatestBlockhash.Response)
        /// Externally supplied bytes whose recent blockhash was checked at this context.
        case external(Context)

        /// The baseline context for fee estimation, simulation, and subsequent validation.
        var context: Context {
            switch self {
            case .transfer(_, _, let blockhash): blockhash.context
            case .external(let context): context
            }
        }
    }

    /// The origin and lifetime information associated with the reviewed transaction.
    let source: Source
    /// The required signer selected for protected wallet access.
    let signer: Address
    /// The exact message, account privileges, instructions, and existing signature slots.
    let transaction: Transaction
    /// The network explicitly selected for this review; wire bytes don't identify it.
    let network: Network
    /// The total fee, including priority fees, or `nil` when unknown, with its context.
    let fee: GetFeeForMessage.Response
    /// The execution outcome and diagnostics, including unsuccessful execution.
    let simulation: SimulateTransaction.Response

    /// Service tips added during local preparation, separate from the network fee.
    ///
    /// Imported transactions remain unchanged; their original instructions require
    /// independent interpretation and aren't represented by this property.
    var tips: [Transfer] {
        guard case .transfer(let transfers, _, _) = source else { return [] }
        return Array(transfers.dropFirst())
    }

    /// The exact unsigned message used for fee estimation and signing.
    var message: Data { transaction.message }

    /// The complete reviewed envelope, retaining empty and occupied signature slots.
    var bytes: Data { transaction.serializedRepresentation }

    /// The newest reviewed context that subsequent provider checks must respect.
    var minimumSlot: UInt64 { max(source.context.slot, fee.context.slot, simulation.context.slot) }

    /// Creates review data without asserting validation, authorization, or program intent.
    ///
    /// - Parameters:
    ///   - source: The construction intent or external blockhash observation.
    ///   - signer: The selected required signer.
    ///   - transaction: The exact structural inspection and preserved signature slots.
    ///   - network: The selected network used for all observations.
    ///   - fee: The total network fee and evaluation context.
    ///   - simulation: The transaction's execution result and evaluation context.
    init(source: Source, signer: Address, transaction: Transaction, network: Network,
         fee: GetFeeForMessage.Response, simulation: SimulateTransaction.Response) {
        self.source = source
        self.signer = signer
        self.transaction = transaction
        self.network = network
        self.fee = fee
        self.simulation = simulation
    }
}
