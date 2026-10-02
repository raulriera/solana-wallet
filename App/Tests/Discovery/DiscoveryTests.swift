import Foundation
import RPC
import Testing
import Wallet
@testable import widgets

/// Exercises SOL-only discovery through local derivation and actual client response decoding.
struct DiscoveryTests {
    /// Verifies one request covers both families and retains only positive SOL balances, including across gaps.
    @Test
    func `Discovery checks twenty addresses once and keeps only SOL-funded accounts`() async throws {
        var native = Array(repeating: "null", count: 20)
        native[0] = nativeAccount(lamports: 0)
        native[14] = nativeAccount(lamports: 1)
        native[19] = nativeAccount(lamports: 2_000_000)
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse(native)]])
        let service: any AccountDiscovering = AccountDiscovery(rpc: http.client)

        let result = try await service.discover(for: publicPhrase())

        #expect(result.network == .devnet)
        #expect(result.indices == 0..<10)
        #expect(result.nextIndices == 10..<20)
        #expect(result.accounts.map(\.path.description) == ["m/44'/501'/7'/0'", "m/44'/501'/9'"])
        let requests = await http.requests
        try #require(requests.count == 1)
        let body = try requests[0].jsonBody()
        #expect(body["method"] as? String == "getMultipleAccounts")
        let addresses = try #require(requests[0].rpcParameters[0] as? [String])
        #expect(addresses.count == 20)
        #expect(result.accounts.map(\.address) == [addresses[14], addresses[19]])
        let encoded = try #require(requests[0].httpBody)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("abandon"))
    }

    /// Verifies empty explicit scans stop after one request, without token, history, or range fallbacks.
    @Test
    func `Empty continuation scans stop after one SOL lookup`() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse(Array(repeating: "null", count: 4))]])
        let result = try await AccountDiscovery(rpc: http.client).discover(
            for: publicPhrase(), passphrase: "", indices: 10..<12)
        #expect(result.accounts.isEmpty)
        #expect(result.indices == 10..<12)
        #expect(result.nextIndices == 12..<22)
        #expect(await http.requests.count == 1)
    }

    /// Verifies invalid bounds fail locally before requesting network observations.
    /// - Parameter indices: An empty, oversized, or non-hardened range.
    @Test(arguments: [
        UInt32(0)..<0, UInt32(0)..<11, UInt32(0x7fff_ffff)..<0x8000_0001,
    ])
    func `Discovery rejects invalid ranges before networking`(_ indices: Range<UInt32>) async throws {
        let http = HTTPResponses([:])
        let phrase = try publicPhrase()
        await #expect(throws: AccountDiscovery.Failure.invalidRange) {
            try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "", indices: indices)
        }
        #expect(await http.requests.isEmpty)
    }

    /// Verifies the last valid hardened index has no overflowing continuation.
    @Test
    func `The last hardened index ends continuation`() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse(Array(repeating: nativeAccount(lamports: 1), count: 2))]])
        let result = try await AccountDiscovery(rpc: http.client).discover(
            for: publicPhrase(), passphrase: "", indices: 0x7fff_ffff..<0x8000_0000)
        #expect(result.nextIndices == nil)
        #expect(result.accounts.map(\.path.description) == ["m/44'/501'/2147483647'/0'", "m/44'/501'/2147483647'"])
    }

    /// Verifies a truncated positional response cannot masquerade as a completed scan.
    @Test
    func `Discovery rejects a truncated native account response`() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse([nativeAccount(lamports: 1)])]])
        let phrase = try publicPhrase()
        await #expect(throws: AccountDiscovery.Failure.mismatchedAccounts) {
            try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "", indices: 0..<1)
        }
        #expect(await http.requests.count == 1)
    }

    /// Verifies provider rate limits propagate without retries or a misleading empty result.
    @Test
    func `Discovery surfaces rate limits without retrying`() async throws {
        let failure = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = HTTPResponses([:], failure: failure)
        let phrase = try publicPhrase()
        await #expect(throws: failure) { try await AccountDiscovery(rpc: http.client).discover(for: phrase) }
        #expect(await http.requests.count == 1)
    }

    /// Verifies cancellation reaches the only in-flight RPC request and prevents a completed result.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling discovery cancels its single account lookup`() async throws {
        let gate = Suspension()
        let http = HTTPResponses([:], gate: gate, heldMethod: "getMultipleAccounts")
        let phrase = try publicPhrase()
        let service = AccountDiscovery(rpc: http.client)
        let operation = Task { @concurrent in
            try await service.discover(for: phrase)
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await http.wasCancelled)
        #expect(await http.requests.count == 1)
    }

    /// Creates a native account observation, including zero balances that must be excluded.
    /// - Parameter lamports: The exact SOL balance to return.
    /// - Returns: The account JSON.
    private func nativeAccount(lamports: UInt64) -> String {
        #"{"owner":"11111111111111111111111111111111","lamports":\#(lamports),"executable":false,"data":["","base64"]}"#
    }

    /// Creates the public zero-entropy BIP-39 test phrase, never used for funding.
    /// - Returns: The validated public phrase.
    /// - Throws: A phrase validation error.
    private func publicPhrase() throws -> RecoveryPhrase {
        try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
    }

    /// Wraps positional native account fixtures in a shared ledger context.
    /// - Parameter values: Encoded account values or explicit nulls.
    /// - Returns: The RPC result JSON.
    private func accountResponse(_ values: [String]) -> String {
        #"{"context":{"slot":400},"value":[\#(values.joined(separator: ","))]}"#
    }
}
