import Foundation
import RPC
import Testing
@testable import widgets

/// Checks custom RPC URLs through the real Solana client, local HTTP fixtures, and a scripted socket.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CustomRPCConnectionTests {
    /// One standard reply to the check's account read.
    private static let accounts = #"{"context":{"slot":1},"value":[null]}"#

    /// A URL that answers standard requests and live updates at the same URL is saved and chosen for every window.
    /// - Throws: A connection failure or a test prerequisite error.
    @Test
    func `A checked RPC is saved and chosen`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com/fixture-token"))
        let settings = StoredValue<ProviderSettings>()
        let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]])
        let socket = SocketFixture()
        defer { socket.cancel() }
        let revision = Revision()

        try await makeConnection(settings: settings, responses: responses, socket: socket, revision: revision)
            .connect("https://rpc.example.com/fixture-token")

        #expect(await settings.value == ProviderSettings(selection: .custom(url), customRPCs: [url]))
        #expect(revision.value == 1)
        #expect(await responses.requests.map(\.url) == [url])
        #expect(try await responses.requests.first?.rpcParameters.first as? [String] == [HTTPResponses.keyCheckAsset])
        #expect(socket.subscribedAddresses == [HTTPResponses.keyCheckAsset])
    }

    /// Text that isn't an HTTPS URL with a host is rejected before any request.
    /// - Parameter entry: The text as entered.
    @Test(arguments: ["http://rpc.example.com", "rpc.example.com", ""])
    func `A URL that isn't HTTPS is rejected without a request`(entry: String) async {
        let settings = StoredValue<ProviderSettings>()
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.notHTTPS) {
            try await makeConnection(settings: settings, responses: responses, socket: SocketFixture()).connect(entry)
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
            try await makeConnection(settings: settings, responses: responses, socket: SocketFixture())
                .connect(url.absoluteString)
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
        let socket = SocketFixture()
        defer { socket.cancel() }

        await #expect(throws: expected) {
            try await makeConnection(settings: settings, responses: HTTPResponses([:], error: error), socket: socket)
                .connect("https://rpc.example.com")
        }

        #expect(socket.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// A failed live-updates subscription at the same URL stops the check, and nothing is saved: an RPC without live
    /// updates is rejected, and one that limits subscriptions asks to try again later.
    /// - Parameters:
    ///   - code: The JSON-RPC error code in the subscription's reply.
    ///   - expected: The check's failure.
    @Test(arguments: [(-32601, CustomRPCError.noLiveUpdates), (429, .rateLimited)])
    func `A failed live-updates subscription stops the check`(code: Int, expected: CustomRPCError) async {
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture { _, _ in [Self.serverError(code: code)] }
        defer { socket.cancel() }

        await #expect(throws: expected) {
            let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]])
            try await makeConnection(settings: settings, responses: responses, socket: socket)
                .connect("https://rpc.example.com")
        }

        #expect(await settings.value == nil)
    }

    /// Custom RPCs that can't be read explain it in an alert before any request.
    @Test
    func `Unreadable custom RPCs explain it without a request`() async {
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.unavailable) {
            try await makeConnection(settings: StoredValue(failsLoading: true), responses: responses,
                                     socket: SocketFixture())
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
        let socket = SocketFixture()
        defer { socket.cancel() }
        let revision = Revision()

        await #expect(throws: CustomRPCError.storageFailed) {
            try await makeConnection(settings: StoredValue(failsSaving: true),
                                     responses: HTTPResponses(["getMultipleAccounts": [Self.accounts]]),
                                     socket: socket, revision: revision)
                .connect("https://rpc.example.com")
        }

        #expect(revision.value == 0)
    }

    /// Leaving the screen during the check saves nothing.
    @Test
    func `A cancelled check saves nothing`() async {
        let gate = Suspension()
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture()
        defer { socket.cancel() }
        let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]], gate: gate)
        let connection = makeConnection(settings: settings, responses: responses, socket: socket)
        let operation = Task { try await connection.connect("https://rpc.example.com") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await responses.wasCancelled)
        #expect(socket.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// A subscription reply that refuses the request with a JSON-RPC error code.
    /// - Parameter code: The error code.
    /// - Returns: One WebSocket frame.
    nonisolated private static func serverError(code: Int) -> Data {
        Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":\#(code),"message":"refused"}}"#.utf8)
    }

    /// Creates the production check over in-memory stores, local HTTP fixtures, and a scripted socket.
    /// - Parameters:
    ///   - settings: The saved provider choice and custom RPCs.
    ///   - responses: The fixtures that answer standard requests.
    ///   - socket: The connection that answers subscriptions.
    ///   - revision: Counts provider changes that every window hears about.
    /// - Returns: A check whose requests never leave the process.
    private func makeConnection(settings: StoredValue<ProviderSettings>, responses: HTTPResponses,
                                socket: SocketFixture, revision: Revision = Revision()) -> CustomRPCConnection {
        let providers = ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: ProviderChanges(),
                                          revision: revision)
        return CustomRPCConnection(providers: providers) { responses.client(for: $0, socket: { _ in socket }) }
    }
}
