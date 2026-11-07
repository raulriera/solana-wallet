import Foundation
@testable import RPC
@testable import widgets

extension HTTPResponses {
    nonisolated static let keyCheckAsset = "So11111111111111111111111111111111111111112"

    static func keyCheck(error: RPCError? = nil, gate: Suspension? = nil) -> HTTPResponses {
        let asset = #"{"id":"\#(keyCheckAsset)","interface":"FungibleToken","mutable":false}"#
        return HTTPResponses(["getAsset": [asset]], error: error, gate: gate)
    }

    nonisolated static func connection(rpcStore: RPCStore,
                                       responding responses: @escaping @Sendable (String) -> HTTPResponses) -> HeliusConnection {
        HeliusConnection(rpcStore: rpcStore) {
            HeliusRPC(apiKey: $0, network: .mainnet, transport: responses($0))
        }
    }

    nonisolated func connection(rpcStore: RPCStore) -> HeliusConnection {
        Self.connection(rpcStore: rpcStore) { _ in self }
    }

    nonisolated func client(for endpoint: SelectedRPCProvider.Endpoint, on network: Network,
                            socket: @escaping @Sendable (URL) -> any WebSocketConnection = { _ in SocketFixture() })
        -> (any RPC & AccountChangeProviding & SignatureEventProviding)? {
        switch endpoint {
        case .solana: SolanaRPC(network: network, transport: self, socket: socket)
        case .helius(let key): HeliusRPC(apiKey: key, network: network, transport: self, socket: socket)
        case .custom(let url): SolanaRPC(endpoint: url, network: network, transport: self, socket: socket)
        }
    }

    nonisolated func rpcProvider(network: Network = .mainnet, rpcStore: RPCStore) -> SelectedRPCProvider {
        SelectedRPCProvider(network: network, rpcStore: rpcStore,
                            rings: StubProver.zolana(on: network, transport: self)) {
            self.client(for: $0, on: $1)
        }
    }
}
