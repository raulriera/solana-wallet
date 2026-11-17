import Transactions
@testable import RPC
@testable import widgets

extension TransactionCoordinator {
    static func simulating(with preparer: Preparer, configuration: Configuration,
                           accounts: (any RPC)? = nil) throws -> TransactionCoordinator {
        let signing = try HTTPResponses.signing()
        return TransactionCoordinator(
            rpc: accounts ?? signing.client, configuration: configuration, preparer: preparer,
            signer: Signer(validator: PreparationValidator(rpc: signing.client), store: UnavailableRecoveryStore()),
            submitter: Submitter(rpc: signing.client), confirmer: Confirmer(rpc: signing.client)
        )
    }
}
