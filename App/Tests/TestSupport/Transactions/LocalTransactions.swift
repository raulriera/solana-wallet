@testable import RPC
import Transactions
@testable import widgets

/// A devnet transaction coordinator whose preparation reads, simulations, sends, and watch answer from local responses
/// and sockets, so it never reaches the network.
struct LocalTransactions {
    /// The coordinator, which signs with the given recovery.
    let coordinator: TransactionCoordinator
    /// The responses that answer the coordinator's preparation reads and simulations.
    let preparation: HTTPResponses

    /// Creates the coordinator for a signing fixture's transaction.
    /// - Parameters:
    ///   - fixture: The transaction, its explicit configuration, and its simulation.
    ///   - recovery: The recovery storage that signing reads, or `nil` for the fixture's recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - statusGate: An optional suspension of the watch's status reads.
    ///   - sockets: The watch's connections.
    ///   - sent: The responses that acknowledge each sent transaction.
    /// - Throws: A fixture error.
    init(fixture: SigningFixture, recovery: SigningRecoveryStore? = nil, statuses: [GetSignatureStatuses.Response],
         height: UInt64 = 500, statusGate: Suspension? = nil, sockets: SocketSequence,
         sent: HTTPResponses = .sending()) throws {
        preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let confirmation = try HTTPResponses.confirmation(
            statuses: statuses, epochs: [GetEpochInfo.Response(epoch: 1, absoluteSlot: 1_000, blockHeight: height)],
            gate: statusGate, heldMethod: statusGate == nil ? nil : "getSignatureStatuses"
        )
        let signing = try HTTPResponses.signing()
        coordinator = TransactionCoordinator(
            rpc: preparation.client, configuration: fixture.configuration, preparer: Preparer(rpc: preparation.client),
            signer: Signer(validator: PreparationValidator(rpc: signing.client),
                           store: recovery ?? SigningRecoveryStore(recovery: fixture.recovery)),
            submitter: Submitter(rpcs: [sent.client]),
            confirmer: Confirmer(rpc: confirmation.client(socket: { sockets.connect($0) }))
        )
    }
}
