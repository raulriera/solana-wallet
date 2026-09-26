import RPC
import Testing

/// Tests client configuration through the framework's public API.
struct ConfigurationTests {
    /// Verifies that omitting the network selects mainnet.
    @Test("clients without a network use mainnet")
    func clientsWithoutANetworkUseMainnet() {
        let rpc: any RPC = HeliusRPC(apiKey: "test-key")

        #expect(rpc.network == .mainnet)
    }
}
