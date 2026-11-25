import Foundation
import RPC
import Testing
import Wallet
@testable import widgets

struct DiscoveryTests {
    @Test
    func `Discovery checks twenty addresses once and keeps only SOL-funded accounts`() async throws {
        var native = [String?](repeating: nil, count: 20)
        native[0] = AccountReplies.systemAccount(lamports: 0)
        native[14] = AccountReplies.systemAccount(lamports: 1)
        native[19] = AccountReplies.systemAccount(lamports: 2_000_000)
        let http = HTTPResponses(["getMultipleAccounts": [AccountReplies.accounts(native)]])
        let service: any AccountDiscovering = AccountDiscovery(rpc: http.client)

        let accounts = try await service.discover(for: RecoveryPhrase(ThrowawayWallet.words), passphrase: "")

        #expect(accounts.map(\.path.description) == ["m/44'/501'/7'/0'", "m/44'/501'/9'"])
        let requests = await http.requests
        try #require(requests.count == 1)
        #expect(try requests[0].rpcMethod == "getMultipleAccounts")
        let addresses = try requestedAddresses(requests[0])
        try #require(addresses.count == 20)
        #expect(accounts.map(\.address) == [addresses[14], addresses[19]])
        let encoded = try #require(requests[0].httpBody)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("abandon"))
    }

    @Test
    func `Discovery surfaces rate limits without retrying`() async throws {
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = HTTPResponses([:], error: error)
        let phrase = try RecoveryPhrase(ThrowawayWallet.words)
        await #expect(throws: error) { try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "") }
        #expect(await http.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling discovery cancels its single account lookup`() async throws {
        let gate = Suspension()
        let http = HTTPResponses([:], gate: gate, heldMethod: "getMultipleAccounts")
        let phrase = try RecoveryPhrase(ThrowawayWallet.words)
        let service = AccountDiscovery(rpc: http.client)
        let operation = Task { @concurrent in
            try await service.discover(for: phrase, passphrase: "")
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await http.wasCancelled)
        #expect(await http.requests.count == 1)
    }
}
