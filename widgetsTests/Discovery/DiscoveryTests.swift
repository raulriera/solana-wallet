import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Exercises discovery policy through local derivation and actual client response decoding.
struct DiscoveryTests {
    /// Verifies gaps never truncate the default scan and both families retain exact recovery paths.
    /// - Parameter program: The token program supplying a token-only discovery signal.
    @Test("discovery scans past gaps and finds SOL, token-only, and history-only accounts",
          arguments: TokenProgram.allCases)
    func findsActivityAcrossGaps(_ program: TokenProgram) async throws {
        let phrase = try publicPhrase()
        let native = (0..<40).map { $0 == 14 ? nativeAccount : "null" }
        var tokenResponses: [String] = []
        var histories: [String] = []
        for position in 0..<40 where position != 14 {
            for candidateProgram in TokenProgram.allCases {
                let found = position == 39 && candidateProgram == program
                tokenResponses.append(found ? tokens(program) : emptyTokens)
                if found { break }
            }
            if position != 39 {
                histories.append(position == 38 ? #"[{"signature":"old-signature","slot":300,"err":"AccountNotFound"}]"# : "[]")
            }
        }
        let http = HTTPResponses([
            "getMultipleAccounts": [accountResponse(native)],
            "getTokenAccountsByOwner": tokenResponses,
            "getSignaturesForAddress": histories,
        ])
        let service: any AccountDiscovering = AccountDiscovery(rpc: http.client)

        let result = try await service.discover(for: phrase)

        #expect(result.network == .devnet)
        #expect(result.indices == 0..<20)
        #expect(result.nextIndices == 20..<40)
        #expect(result.accounts.map(\.account.path.description) == [
            "m/44'/501'/7'/0'", "m/44'/501'/19'/0'", "m/44'/501'/19'",
        ])
        #expect(result.accounts.map(\.evidence) == [.solBalance, .transactionHistory, .tokenAccount(program)])
        let requests = await http.requests
        let nativeRequest = try #require(requests.first)
        let addresses = try #require(nativeRequest.rpcParameters[0] as? [String])
        #expect(addresses.count == 40)
        #expect(result.accounts.map(\.account.address) == [addresses[14], addresses[38], addresses[39]])
        let queriedOwners = try requests.dropFirst().map { try #require($0.rpcParameters[0] as? String) }
        #expect(Set(queriedOwners) == Set(addresses.enumerated().filter { $0.offset != 14 }.map(\.element)))
        #expect(requests.allSatisfy { request in
            guard let body = request.httpBody else { return false }
            return !String(decoding: body, as: UTF8.self).contains("abandon")
        })
    }

    /// Verifies callers can explicitly resume a range without an empty result triggering expansion.
    @Test("empty continuation scans report their exact range and stop")
    func emptyContinuationStops() async throws {
        let http = HTTPResponses([
            "getMultipleAccounts": [accountResponse(Array(repeating: "null", count: 4))],
            "getTokenAccountsByOwner": [emptyTokens],
            "getSignaturesForAddress": ["[]"],
        ])
        let result = try await AccountDiscovery(rpc: http.client).discover(
            for: publicPhrase(), passphrase: "", indices: 20..<22)
        #expect(result.accounts.isEmpty)
        #expect(result.indices == 20..<22)
        #expect(result.nextIndices == 22..<42)
        #expect(await http.requests.count == 13)
    }

    /// Verifies invalid bounds fail locally before requesting network observations.
    /// - Parameter indices: An empty, oversized, or non-hardened range.
    @Test("discovery rejects invalid ranges before networking", arguments: [
        UInt32(0)..<0, UInt32(0)..<21, UInt32(0x7fff_ffff)..<0x8000_0001,
    ])
    func rejectsInvalidRange(_ indices: Range<UInt32>) async throws {
        let http = HTTPResponses([:])
        let phrase = try publicPhrase()
        await #expect(throws: AccountDiscovery.Failure.invalidRange) {
            try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "", indices: indices)
        }
        #expect(await http.requests.isEmpty)
    }

    /// Verifies the last valid hardened index has no overflowing continuation.
    @Test("the last hardened index ends continuation")
    func lastIndexEndsContinuation() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse([nativeAccount, nativeAccount])]])
        let result = try await AccountDiscovery(rpc: http.client).discover(
            for: publicPhrase(), passphrase: "", indices: 0x7fff_ffff..<0x8000_0000)
        #expect(result.nextIndices == nil)
        #expect(result.accounts.map(\.account.path.description) == ["m/44'/501'/2147483647'/0'", "m/44'/501'/2147483647'"])
    }

    /// Verifies a truncated positional response cannot masquerade as a completed scan.
    @Test("discovery rejects a truncated native account response")
    func rejectsTruncatedResponse() async throws {
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse([nativeAccount])]])
        let phrase = try publicPhrase()
        await #expect(throws: AccountDiscovery.Failure.mismatchedAccounts) {
            try await AccountDiscovery(rpc: http.client).discover(for: phrase, passphrase: "", indices: 0..<1)
        }
        #expect(await http.requests.count == 1)
    }

    /// Verifies provider rate limits propagate without retries or a misleading empty result.
    @Test("discovery surfaces rate limits without retrying")
    func surfacesRateLimit() async throws {
        let failure = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = HTTPResponses([:], failure: failure)
        let phrase = try publicPhrase()
        await #expect(throws: failure) { try await AccountDiscovery(rpc: http.client).discover(for: phrase) }
        #expect(await http.requests.count == 1)
    }

    /// Verifies cancellation during a later read discards partial matches and reaches the transport.
    @Test("cancelling discovery cancels a pending token lookup", .timeLimit(.minutes(1)))
    func cancellationDiscardsPartialScan() async throws {
        let gate = Suspension()
        let http = HTTPResponses(["getMultipleAccounts": [accountResponse([nativeAccount, "null"])]],
                                 gate: gate, heldMethod: "getTokenAccountsByOwner")
        let phrase = try publicPhrase()
        let service = AccountDiscovery(rpc: http.client)
        let operation = Task { @concurrent in
            try await service.discover(for: phrase, passphrase: "", indices: 0..<1)
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await http.wasCancelled)
        #expect(await http.requests.count == 2)
    }

    private var nativeAccount: String {
        #"{"owner":"11111111111111111111111111111111","lamports":1,"executable":false,"data":["","base64"]}"#
    }
    private var emptyTokens: String { #"{"context":{"slot":402},"value":[]}"# }

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

    /// Creates token ownership evidence without token-data decoding or balance assumptions.
    /// - Parameter program: The owning token program.
    /// - Returns: The RPC result JSON.
    private func tokens(_ program: TokenProgram) -> String {
        #"{"context":{"slot":402},"value":[{"pubkey":"token-account","account":{"owner":"\#(program.rawValue)","lamports":2039280,"executable":false,"data":["","base64"]}}]}"#
    }
}
