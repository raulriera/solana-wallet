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
            .connect(" https://rpc.example.com/fixture-token \n")

        #expect(await settings.value == ProviderSettings(selection: .custom(url), customRPCs: [url]))
        #expect(revision.value == 1)
        #expect(await responses.requests.map(\.url) == [url])
        #expect(try await responses.requests.first?.rpcParameters.first as? [String] == [HTTPResponses.keyCheckAsset])
        #expect(socket.subscribedAddresses == [HTTPResponses.keyCheckAsset])
    }

    /// Text that isn't an HTTPS URL with a host is refused before any request.
    /// - Parameter entry: The text as entered.
    @Test(arguments: ["http://rpc.example.com", "rpc.example.com", " "])
    func `A URL that isn't HTTPS is refused without a request`(entry: String) async {
        let settings = StoredValue<ProviderSettings>()
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.notHTTPS) {
            try await makeConnection(settings: settings, responses: responses, socket: SocketFixture()).connect(entry)
        }

        #expect(await responses.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// An RPC that's already listed is refused before any request.
    /// - Throws: A test prerequisite error.
    @Test
    func `A listed RPC is refused without a request`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue(ProviderSettings(customRPCs: [url]))
        let responses = HTTPResponses([:])

        await #expect(throws: CustomRPCError.duplicate) {
            try await makeConnection(settings: settings, responses: responses, socket: SocketFixture())
                .connect(url.absoluteString)
        }

        #expect(await responses.requests.isEmpty)
    }

    /// A URL that doesn't answer a standard request is refused before any subscription, and nothing is saved.
    /// - Parameter error: How the URL fails the request.
    @Test(arguments: [RPCError.http(statusCode: 404, retryAfter: nil), .http(statusCode: 401, retryAfter: nil),
                      .transport(.cannotFindHost)])
    func `A URL that doesn't answer as a Solana RPC is refused`(error: RPCError) async {
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture()
        defer { socket.cancel() }

        await #expect(throws: CustomRPCError.unreachable) {
            try await makeConnection(settings: settings, responses: HTTPResponses([:], error: error), socket: socket)
                .connect("https://rpc.example.com")
        }

        #expect(socket.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// An RPC whose live updates fail at the same URL is refused, and nothing is saved.
    @Test
    func `An RPC without live updates is refused`() async {
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture { _, _ in [Self.serverError(code: -32601)] }
        defer { socket.cancel() }

        await #expect(throws: CustomRPCError.noLiveUpdates) {
            let responses = HTTPResponses(["getMultipleAccounts": [Self.accounts]])
            try await makeConnection(settings: settings, responses: responses, socket: socket)
                .connect("https://rpc.example.com")
        }

        #expect(await settings.value == nil)
    }

    /// An RPC that limits standard requests asks to try again later before any subscription.
    @Test
    func `An RPC that limits requests asks to try again later`() async {
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture()
        defer { socket.cancel() }

        await #expect(throws: CustomRPCError.rateLimited) {
            let responses = HTTPResponses([:], error: .http(statusCode: 429, retryAfter: nil))
            try await makeConnection(settings: settings, responses: responses, socket: socket)
                .connect("https://rpc.example.com")
        }

        #expect(socket.requests.isEmpty)
        #expect(await settings.value == nil)
    }

    /// An RPC that limits subscriptions in its reply asks to try again later.
    @Test
    func `An RPC that limits live updates asks to try again later`() async {
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture { _, _ in [Self.serverError(code: 429)] }
        defer { socket.cancel() }

        await #expect(throws: CustomRPCError.rateLimited) {
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
    func `Only refused URLs show under the field`(error: CustomRPCError, rejectsEntry: Bool) {
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

    /// An RPC saved before the previous provider's logos fail to clear is in use, so the check succeeds.
    /// - Throws: A connection failure or a test prerequisite error.
    @Test
    func `An RPC saved before old logos fail to clear counts as added`() async throws {
        let url = try #require(URL(string: "https://rpc.example.com"))
        let settings = StoredValue<ProviderSettings>()
        let socket = SocketFixture()
        defer { socket.cancel() }
        let revision = Revision()

        try await makeConnection(settings: settings, responses: HTTPResponses(["getMultipleAccounts": [Self.accounts]]),
                                 socket: socket, portfolio: ProviderChanges(error: CocoaError(.fileWriteOutOfSpace)),
                                 revision: revision)
            .connect(url.absoluteString)

        #expect(await settings.value?.selection == .custom(url))
        #expect(revision.value == 1)
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
    ///   - portfolio: Records provider changes.
    ///   - revision: Counts provider changes that every window hears about.
    /// - Returns: A check whose requests never leave the process.
    private func makeConnection(settings: StoredValue<ProviderSettings>, responses: HTTPResponses,
                                socket: SocketFixture, portfolio: ProviderChanges = ProviderChanges(),
                                revision: Revision = Revision()) -> CustomRPCConnection {
        let providers = ProviderSelection(settings: settings, providerKey: StoredValue(), portfolio: portfolio,
                                          revision: revision)
        return CustomRPCConnection(providers: providers) { responses.client(for: $0, socket: { _ in socket }) }
    }
}
