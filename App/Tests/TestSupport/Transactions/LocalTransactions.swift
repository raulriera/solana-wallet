import Transactions
@testable import RPC
@testable import widgets

struct LocalTransactions {
    let coordinator: TransactionCoordinator
    let preparation: HTTPResponses

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
            submitter: Submitter(rpc: sent.client),
            confirmer: Confirmer(rpc: confirmation.client(socket: { sockets.connect($0) }))
        )
    }
}
