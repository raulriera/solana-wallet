import Foundation
@testable import widgets

extension RPCCoordinator {
    static func inMemory(_ rpcStore: RPCStore) -> RPCCoordinator {
        let connection = HTTPResponses.keyCheck().connection(rpcStore: rpcStore)
        let customRPCConnection = CustomRPCConnection(rpcStore: rpcStore) { HTTPResponses([:]).client(for: $0, on: $1) }
        return RPCCoordinator(rpcStore: rpcStore, connection: connection, customRPCConnection: customRPCConnection)
    }
}
