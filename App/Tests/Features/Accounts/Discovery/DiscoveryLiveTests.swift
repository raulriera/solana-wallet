import RPC
import Testing
import Vault
@testable import widgets

@Suite(.tags(.network))
struct DiscoveryLiveTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Mainnet discovery reads twenty addresses with one request`(helius: Bool) async throws {
        let transport = LiveResponses<GetMultipleAccounts>()
        let rpc = try LiveClients.client(helius: helius, transport: transport)
        let recovery = try await DevnetWallets.configured().recovery

        _ = try await AccountDiscovery(rpc: rpc).discover(for: recovery.phrase, passphrase: recovery.passphrase)

        #expect(await transport.responses.map(\.value.count) == [20])
    }
}
