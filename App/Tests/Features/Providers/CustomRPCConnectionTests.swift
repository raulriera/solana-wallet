import Foundation
import RPC
import Testing
@testable import widgets

/// Checks custom RPC URLs through the real Solana client, local HTTP fixtures, and scripted sockets.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CustomRPCConnectionTests {
    /// One standard reply to the check's account read.
    private static let accounts = #"{"context":{"slot":1},"value":[null]}"#

    /// A URL that answers standard requests, account subscriptions, and a payment watch at the same URL is saved and
    /// chosen for every window, and the check leaves no connection open.
    /// - Throws: A connection failure or a test prerequisite error.
    @Test
    func `A checked RPC is saved and chosen`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue<ProviderSettings>()
        let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]])
        let sockets = SocketSequence()
        let revision = Revision()

        try await makeConnection(settings: settings, responses: responses, sockets: sockets, revision: revision)
            .connect("https://rpc.example.com/fixture-token")

        #expect(await settings.value == ProviderSettings(selection: .custom(url), customRPCs: [url]))
        #expect(revision.value == 1)
        #expect(await responses.requests.map(\.url) == [url])
        #expect(try await responses.requests.first?.rpcParameters.first as? [String] == [HTTPResponses.keyCheckAsset])
        try #require(sockets.sockets.count == 2)
        // The two connections open at once, so find each by its first request.
        let connections = try sockets.sockets.map { try $0.requests.map(Self.body(of:)) }
        let account = try #require(connections.first { $0.first?["method"] as? String == "accountSubscribe" })
        #expect(account.count == 1)
        #expect((account.first?["params"] as? [Any])?.first as? String == HTTPResponses.keyCheckAsset)
        let watch = try #require(connections.first { $0.first?["method"] as? String == "signatureSubscribe" })
        #expect(watch.map { $0["method"] as? String } == ["signatureSubscribe", "rootSubscribe"])
        #expect((watch.first?["params"] as? [Any])?.first as? String == String(repeating: "1", count: 64))
        await sockets.waitUntilClosed()
    }

    /// Text that isn't an HTTPS URL with a host is rejected before any request.
    /// - Parameter entry: The text as entered.
    @Test(arguments: ["http://rpc.example.com", "rpc.example.com", ""])
    func `A URL that isn't HTTPS is rejected without a request`(entry: String) async {
        let settings = StoredValue<ProviderSettings>()
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.notHTTPS) {
            try await makeConnection(settings: settings, responses: responses).connect(entry)
        }

        #expect(await responses.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// An RPC that's already listed is rejected before any request.
    /// - Throws: A test prerequisite error.
    @Test
    func `A listed RPC is rejected without a request`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]))
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.duplicate) {
            try await makeConnection(settings: settings, responses: responses).connect(url.absoluteString)
        }

        #expect(await responses.requests.isEmpty)
    }

    /// A failed standard request stops the check before any subscription, and nothing is saved: a URL that doesn't
    /// answer as a Solana RPC is rejected, and one that limits requests asks to try again later.
    /// - Parameters:
    ///   - error: How the URL fails the request.
    ///   - expected: The check's failure.
    @Test(arguments: [
        (RPCError.http(statusCode: 404, retryAfter: nil), CustomRPCError.unreachable),
        (.http(statusCode: 401, retryAfter: nil), .unreachable),
        (.transport(.cannotFindHost), .unreachable),
        (.http(statusCode: 429, retryAfter: nil), .rateLimited),
    ] as [(RPCError, CustomRPCError)])
    func `A failed standard request stops the check before any subscription`(error: RPCError,
                                                                              expected: CustomRPCError) async {
        let settings = StoredValue<ProviderSettings>()
        let sockets = SocketSequence()

        await #expect(throws: expected) {
            try await makeConnection(settings: settings, responses: HTTPResponses([:], error: error), sockets: sockets)
                .connect("https://rpc.example.com")
        }

        #expect(sockets.sockets.isEmpty)
        #expect(await settings.value == nil)
    }

    /// A failed live-updates subscription at the same URL stops the check, nothing is saved, and no connection stays
    /// open: an RPC without account updates or a payment watch's signature or root updates is rejected, and one that
    /// limits subscriptions asks to try again later.
    /// - Parameters:
    ///   - method: The subscription method that fails.
    ///   - code: The JSON-RPC error code in the subscription's reply.
    ///   - expected: The check's failure.
    @Test(arguments: [
        ("accountSubscribe", -32601, CustomRPCError.noLiveUpdates), ("signatureSubscribe", -32601, .noLiveUpdates),
        ("rootSubscribe", -32601, .noLiveUpdates), ("accountSubscribe", 429, .rateLimited),
        ("rootSubscribe", 429, .rateLimited),
    ] as [(String, Int, CustomRPCError)])
    func `A failed live-updates subscription stops the check`(method: String, code: Int,
                                                             expected: CustomRPCError) async {
        let settings = StoredValue<ProviderSettings>()
        let sockets = SocketSequence { _ in
            { request, ordinal in
                guard try Self.body(of: request)["method"] as? String == method else {
                    return [try SocketFixture.acknowledgment(of: request, ordinal: ordinal)]
                }
                return [SocketFixture.serverError(code: code)]
            }
        }

        await #expect(throws: expected) {
            let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]])
            try await makeConnection(settings: settings, responses: responses, sockets: sockets)
                .connect("https://rpc.example.com")
        }

        #expect(await settings.value == nil)
        await sockets.waitUntilClosed()
    }

    /// Custom RPCs that can't be read explain it in an alert before any request.
    @Test
    func `Unreadable custom RPCs explain it without a request`() async {
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.unavailable) {
            try await makeConnection(settings: StoredValue(failsLoading: true), responses: responses)
                .connect("https://rpc.example.com")
        }

        #expect(await responses.requests.isEmpty)
    }

    /// Refused URLs show under the field, and other failures explain their cause in an alert.
    /// - Parameters:
    ///   - error: A check failure.
    ///   - rejectsEntry: Whether the failure shows under the field.
    @Test(arguments: [
        (CustomRPCError.notHTTPS, true), (.duplicate, true), (.unreachable, true), (.noLiveUpdates, true),
        (.rateLimited, false), (.unavailable, false), (.storageFailed, false),
    ])
    func `Only rejected URLs show under the field`(error: CustomRPCError, rejectsEntry: Bool) {
        #expect(error.rejectsEntry == rejectsEntry)
    }

    /// A checked RPC that this device can't store explains it, and every window keeps its provider.
    @Test
    func `A checked RPC that can't be saved explains it`() async {
        let revision = Revision()

        await #expect(throws: CustomRPCError.storageFailed) {
            try await makeConnection(settings: StoredValue(failsSaving: true),
                                     responses: HTTPResponses(["getMultipleAccounts": [Self.accounts]]),
                                     revision: revision)
                .connect("https://rpc.example.com")
        }

        #expect(revision.value == 0)
    }

    /// Leaving the screen during the check saves nothing.
    @Test
    func `A cancelled check saves nothing`() async {
        let gate = Suspension()
        let settings = StoredValue<ProviderSettings>()
        let sockets = SocketSequence()
        let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]], gate: gate)
        let connection = makeConnection(settings: settings, responses: responses, sockets: sockets)
        let operation = Task { try await connection.connect("https://rpc.example.com") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(sockets.sockets.isEmpty)
        #expect(await settings.value == nil)
    }

    /// Creates the production check over in-memory stores, local HTTP fixtures, and scripted sockets.
    /// - Parameters:
    ///   - settings: The saved provider choice and custom RPCs.
    ///   - responses: The fixtures that answer standard requests.
    ///   - sockets: The connections that answer subscriptions; by default, each one acknowledges every subscription.
    ///   - revision: Counts provider changes that every window hears about.
    /// - Returns: A check whose requests never leave the process.
    private func makeConnection(settings: StoredValue<ProviderSettings>, responses: HTTPResponses,
                                sockets: SocketSequence = SocketSequence(),
                                revision: Revision = Revision()) -> CustomRPCConnection {
        let providers = ProviderSelection(settings: settings, providerKey: StoredValue(),
                                          portfolios: { [ProviderChanges()] }, revision: revision)
        return CustomRPCConnection(providers: providers) { responses.client(for: $0, on: $1, socket: { sockets.connect($0) }) }
    }

    /// Decodes a subscription request that the real client sent.
    /// - Parameter request: The request's JSON bytes.
    /// - Returns: The JSON object sent by the client.
    /// - Throws: A test prerequisite error when the request isn't a JSON object.
    nonisolated private static func body(of request: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
    }
}
