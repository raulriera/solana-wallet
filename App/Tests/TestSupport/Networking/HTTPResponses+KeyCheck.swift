import Foundation
@testable import RPC
@testable import widgets

extension HTTPResponses {
    nonisolated static let keyCheckAsset = "So11111111111111111111111111111111111111112"

    static func keyCheck(error: RPCError? = nil, gate: Suspension? = nil) -> HTTPResponses {
        let asset = #"{"id":"\#(keyCheckAsset)","interface":"FungibleToken","mutable":false}"#
        return HTTPResponses(["getAsset": [asset]], error: error, gate: gate)
    }

    nonisolated static func connection(providers: ProviderStore,
                                       responding responses: @escaping @Sendable (String) -> HTTPResponses) -> HeliusConnection {
        HeliusConnection(providers: providers) {
            HeliusRPC(apiKey: $0, network: .mainnet, transport: responses($0))
        }
    }

    nonisolated func connection(providers: ProviderStore) -> HeliusConnection {
        Self.connection(providers: providers) { _ in self }
    }

    nonisolated func client(for endpoint: ProviderClient.Endpoint, on network: Network,
                            socket: @escaping @Sendable (URL) -> any WebSocketConnection = { _ in SocketFixture() })
        -> (any RPC & AccountChangeProviding & SignatureEventProviding)? {
        switch endpoint {
        case .solana: Solana(network: network, transport: self, socket: socket)
        case .helius(let key):
            HeliusRPC(apiKey: key, network: network, transport: self, socket: socket,
                      zolana: StubProver.zolana(on: network, transport: self))
        case .custom(let url): Solana(endpoint: url, network: network, transport: self, socket: socket)
        }
    }

    nonisolated func providerClient(network: Network = .mainnet, providers: ProviderStore) -> ProviderClient {
        ProviderClient(network: network, providers: providers) { self.client(for: $0, on: $1) }
    }
}
