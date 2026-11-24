import CryptoKit
import Foundation
import RPC
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CustomRPCConnectionTests {
    nonisolated private static let attestation: String = StubProver.attestation(
        of: Curve25519.KeyAgreement.PrivateKey().publicKey
    )
    nonisolated private static let checkedLogo = #"""
        [{"id":"So11111111111111111111111111111111111111112",
          "content":{"files":[{"cdn_uri":"https://cdn.example.com/sol.png","mime":"image/png"}]}}]
        """#

    @Test(
        arguments: [
            (checkedLogo, "{}", Capabilities.logos),
            ("[null]", attestation, Capabilities.privateBalances),
        ]
    )
    func `A checked RPC is saved and chosen with the optional features its server serves`(
        logoReply: String,
        attestationReply: String,
        capabilities: Capabilities
    ) async throws {
        let url = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue<RPCSettings>()
        let responses = Self.responses(logo: logoReply, attestation: attestationReply)
        let sockets = SocketSequence()
        let rpcStore = RPCStore.inMemory(settings)

        try await makeConnection(rpcStore: rpcStore, responses: responses, sockets: sockets)
            .connect("https://rpc.example.com/fixture-token")

        let saved = RPCSettings.CustomRPC(url: url, capabilities: capabilities)
        #expect(await settings.value == RPCSettings(selection: .custom(url), customRPCs: [saved]))
        #expect(rpcStore.connection == .custom(url, capabilities: capabilities))
        let paths = await responses.requests.compactMap { $0.url?.path() }
        #expect(
            paths.sorted() == [
                "/fixture-token", "/fixture-token", "/fixture-token/v1/spr/attestation",
                "/fixture-token/v1/spr/getShieldedTransactionsByNullifiers",
            ]
        )
        try #require(sockets.sockets.count == 2)
        let connections = try sockets.sockets.map { try $0.requests.map(Self.body(of:)) }
        let account = try #require(connections.first { $0.first?["method"] as? String == "accountSubscribe" })
        #expect(account.count == 1)
        let watch = try #require(connections.first { $0.first?["method"] as? String == "signatureSubscribe" })
        #expect(watch.map { $0["method"] as? String } == ["signatureSubscribe", "rootSubscribe"])
        await sockets.waitUntilClosed()
    }

    @Test(arguments: ["http://rpc.example.com", ""])
    func `A URL that isn't HTTPS is rejected without a request`(entry: String) async {
        let settings = StoredValue<RPCSettings>()
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.notHTTPS) {
            try await makeConnection(rpcStore: .inMemory(settings), responses: responses).connect(entry)
        }

        #expect(await responses.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    @Test
    func `A listed RPC is rejected without a request`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(RPCSettings(customRPCs: [url]))
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.duplicate) {
            try await makeConnection(rpcStore: .inMemory(settings), responses: responses).connect(url.absoluteString)
        }

        #expect(await responses.requests.isEmpty)
    }

    @Test(
        arguments: [
            (RPCError.http(statusCode: 404, retryAfter: nil), nil, CustomRPCError.unreachable),
            (.http(statusCode: 429, retryAfter: nil), nil, .rateLimited),
            (.http(statusCode: 429, retryAfter: nil), "getAssetBatch", .rateLimited),
        ] as [(RPCError, String?, CustomRPCError)]
    )
    func `A failed request fails the check`(
        error: RPCError,
        failingMethod: String?,
        expected: CustomRPCError
    ) async {
        let settings = StoredValue<RPCSettings>()
        let sockets = SocketSequence()
        let responses = Self.responses(error: error, failingMethod: failingMethod)

        await #expect(throws: expected) {
            try await makeConnection(rpcStore: .inMemory(settings), responses: responses, sockets: sockets)
                .connect("https://rpc.example.com")
        }

        #expect(await settings.value == nil)
        await sockets.waitUntilClosed()
    }

    @Test(arguments: [
        ("accountSubscribe", -32601, CustomRPCError.noLiveUpdates), ("signatureSubscribe", -32601, .noLiveUpdates),
        ("rootSubscribe", 429, .rateLimited),
    ] as [(String, Int, CustomRPCError)])
    func `A failed live-updates subscription stops the check`(method: String, code: Int,
                                                             expected: CustomRPCError) async {
        let settings = StoredValue<RPCSettings>()
        let sockets = SocketSequence { _ in
            { request, ordinal in
                guard try Self.body(of: request)["method"] as? String == method else {
                    return [try SocketFixture.acknowledgment(of: request, ordinal: ordinal)]
                }
                return [SocketFixture.serverError(code: code)]
            }
        }

        await #expect(throws: expected) {
            let responses = Self.responses()
            try await makeConnection(rpcStore: .inMemory(settings), responses: responses, sockets: sockets)
                .connect("https://rpc.example.com")
        }

        #expect(await settings.value == nil)
        await sockets.waitUntilClosed()
    }

    @Test
    func `Unreadable custom RPCs explain it without a request`() async {
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.unavailable) {
            try await makeConnection(rpcStore: .inMemory(StoredValue(failsLoading: true)), responses: responses)
                .connect("https://rpc.example.com")
        }

        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `A checked RPC that can't be saved explains it`() async {
        let rpcStore = RPCStore.inMemory(StoredValue(failsSaving: true))

        await #expect(throws: CustomRPCError.storageFailed) {
            try await makeConnection(rpcStore: rpcStore, responses: Self.responses())
                .connect("https://rpc.example.com")
        }

        #expect(rpcStore.connection == .solana)
    }

    @Test
    func `A cancelled check saves nothing`() async {
        let gate = Suspension()
        let settings = StoredValue<RPCSettings>()
        let sockets = SocketSequence()
        let responses = Self.responses(gate: gate)
        let connection = makeConnection(rpcStore: .inMemory(settings), responses: responses, sockets: sockets)
        let operation = Task { try await connection.connect("https://rpc.example.com") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(await settings.value == nil)
        await sockets.waitUntilClosed()
    }

    private static func responses(
        logo: String = "[null]",
        attestation: String = attestation,
        error: RPCError? = nil,
        failingMethod: String? = nil,
        gate: Suspension? = nil
    ) -> HTTPResponses {
        let replies = [
            "getMultipleAccounts": [AccountReplies.accounts([nil])],
            "getAssetBatch": [logo],
            "getShieldedTransactionsByNullifiers": [IndexerReplies.page([], in: "events")],
        ]
        return HTTPResponses(replies, error: error, failingMethod: failingMethod, gate: gate) { _ in attestation }
    }

    private func makeConnection(rpcStore: RPCStore, responses: HTTPResponses,
                                sockets: SocketSequence = SocketSequence()) -> CustomRPCConnection {
        CustomRPCConnection(rpcStore: rpcStore) { responses.client(for: $0, on: $1, socket: { sockets.connect($0) }) }
    }

    nonisolated private static func body(of request: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
    }
}
