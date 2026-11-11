import Foundation
import RPC
import Testing
import Wallet
@testable import widgets

struct DiscoveryTests {
    @Test
    func `Discovery checks twenty addresses once and keeps only SOL-funded accounts`() async throws {
        var native = Array(repeating: "null", count: 20)
        native[0] = nativeAccount(lamports: 0)
        native[14] = nativeAccount(lamports: 1)
        native[19] = nativeAccount(lamports: 2_000_000)
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse(native)]])
        let service: any AccountDiscovering = AccountDiscovery(rpc: http.client)

        let accounts = try await service.discover(for: publicPhrase(), passphrase: "")

        #expect(accounts.map(\.path.description) == ["m/44'/501'/7'/0'", "m/44'/501'/9'"])
        let requests = await http.requests
        try #require(requests.count == 1)
        let body = try requests[0].jsonBody()
        #expect(body["method"] as? String == "getMultipleAccounts")
        let addresses = try #require(requests[0].rpcParameters.first as? [String])
        try #require(addresses.count == 20)
        #expect(accounts.map(\.address) == [addresses[14], addresses[19]])
        let encoded = try #require(requests[0].httpBody)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("abandon"))
    }

    @Test
    func `An empty scan stops after one SOL lookup`() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse(Array(repeating: "null", count: 20))]])
        let accounts = try await AccountDiscovery(rpc: http.client).discover(for: publicPhrase(), passphrase: "")
        #expect(accounts.isEmpty)
        #expect(await http.requests.count == 1)
    }

    @Test
    func `Discovery surfaces rate limits without retrying`() async throws {
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = HTTPResponses([:], error: error)
        let phrase = try publicPhrase()
        await #expect(throws: error) { try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "") }
        #expect(await http.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling discovery cancels its single account lookup`() async throws {
        let gate = Suspension()
        let http = HTTPResponses([:], gate: gate, heldMethod: "getMultipleAccounts")
        let phrase = try publicPhrase()
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

    private func nativeAccount(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    private func publicPhrase() throws -> RecoveryPhrase {
        try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
    }

    private func accountResponse(_ values: [String]) -> String {
        #"{"context":{"slot":400},"value":[\#(values.joined(separator: ","))]}"#
    }
}
