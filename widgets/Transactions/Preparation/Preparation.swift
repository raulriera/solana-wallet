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
        /// A validated token transfer, separate SOL tips, configuration, and block-height expiry.
        case token(TokenTransfer, [Transfer], Configuration, GetLatestBlockhash.Response)
        /// Externally supplied bytes whose recent blockhash was checked at this context.
        case external(Context)

        /// The baseline context for fee estimation, simulation, and subsequent validation.
        var context: Context {
            switch self {
            case .transfer(_, _, let blockhash): blockhash.context
            case .token(_, _, _, let blockhash): blockhash.context
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
    /// The network fee, including priority fees, or `nil` when unknown, with its context.
    let fee: GetFeeForMessage.Response
    /// The execution outcome and diagnostics, including unsuccessful execution.
    let simulation: SimulateTransaction.Response
    /// The estimated SOL deposit in lamports for a locally prepared token destination.
    ///
    /// Zero means the destination already exists; `nil` means this preparation
    /// doesn't estimate account creation. The deposit stays in the recipient's
    /// account and is separate from network fees, tips, and the token amount.
    /// Rent queries have no slot context; account or rent changes can alter the
    /// actual debit before execution. This value isn't a guaranteed total cost.
    let destinationAccountRent: UInt64?

    /// Service tips added during local preparation, separate from the network fee.
    ///
    /// Imported transactions remain unchanged; their original instructions require
    /// independent interpretation and aren't represented by this property.
    var tips: [Transfer] {
        switch source {
        case .transfer(let transfers, _, _): Array(transfers.dropFirst())
        case .token(_, let tips, _, _): tips
        case .external: []
        }
    }

    /// The reviewed token debit, recipient, fee, and account-creation requirement, when locally constructed.
    var tokenTransfer: TokenTransfer? {
        guard case .token(let transfer, _, _, _) = source else { return nil }
        return transfer
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
    ///   - destinationAccountRent: The estimated destination deposit, or `nil` when unestimated.
    init(source: Source, signer: Address, transaction: Transaction, network: Network,
         fee: GetFeeForMessage.Response, simulation: SimulateTransaction.Response,
         destinationAccountRent: UInt64? = nil) {
        self.source = source
        self.signer = signer
        self.transaction = transaction
        self.network = network
        self.fee = fee
        self.simulation = simulation
        self.destinationAccountRent = destinationAccountRent
    }
}
