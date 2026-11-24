import Foundation
import Testing
@testable import RPC

extension SolanaRPC {
    static func custom(
        on network: Network,
        transport: StubTransport,
        verify: @escaping AttestedProverKey.Verification = AttestedProverKey.verification
    ) throws -> SolanaRPC {
        let endpoint = try #require(URL(string: "https://rpc.example.com"))
        return try #require(SolanaRPC(endpoint: endpoint, network: network, transport: transport, verify: verify))
    }
}
