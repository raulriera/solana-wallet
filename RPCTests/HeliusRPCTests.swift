import Foundation
import Testing
@testable import RPC

/// Tests typed RPC requests and failures through an injected HTTP transport.
struct HeliusRPCTests {
    private let address = "83astBRguLMdt2h5U1Tpdq5tjFoJ6noeGwaY3mDLVcri"

    /// Verifies that requests reach the Helius endpoint for the selected network.
    ///
    /// - Parameters:
    ///   - network: The Solana network selected when creating the client.
    ///   - expectedHost: The Helius host that should receive the request.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("requests use the selected network endpoint", arguments: [
        (Network.mainnet, "mainnet.helius-rpc.com"),
        (.devnet, "devnet.helius-rpc.com"),
    ])
    func requestsUseTheSelectedNetworkEndpoint(network: Network, expectedHost: String) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"solana-core":"3.0.0","feature-set":2891131721}"#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: network, transport: transport)

        _ = try await rpc.send(GetVersion())

        let request = try #require(await transport.requests.first)
        #expect(request.url?.host() == expectedHost)
        #expect(rpc.network == network)
    }

    /// Verifies the outgoing balance request and its exact lamports and slot.
    ///
    /// The fixture's balance exceeds `Double`'s exact integer range to detect
    /// precision loss during decoding.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get balance returns wallet lamports and slot")
    func getBalanceReturnsWalletLamportsAndSlot() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":9007199254740993}"#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let balance = try await rpc.send(GetBalance(address: address))

        #expect(balance.value == 9_007_199_254_740_993)
        #expect(balance.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["jsonrpc"] as? String == "2.0")
        #expect(body["method"] as? String == "getBalance")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == address)
        #expect((parameters.last as? [String: String])?["commitment"] == "confirmed")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 30)
        let url = try #require(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "api-key", value: "test-key")])
    }

    /// Verifies the account request and its decoded state, bytes, and ledger slot.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get account returns owner lamports data and slot")
    func getAccountReturnsOwnerLamportsDataAndSlot() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":{"lamports":9007199254740993,"owner":"11111111111111111111111111111111","data":["AQIDBA==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":4}}"#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAccountInfo(address: address))

        let account = try #require(response.value)
        #expect(account.owner == "11111111111111111111111111111111")
        #expect(account.lamports == 9_007_199_254_740_993)
        #expect(account.data == Data([1, 2, 3, 4]))
        #expect(!account.isExecutable)
        #expect(account.rentEpoch == UInt64.max)
        #expect(account.space == 4)
        #expect(response.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "getAccountInfo")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == address)
        #expect(parameters.last as? [String: String] == ["commitment": "confirmed", "encoding": "base64"])
    }

    /// Verifies that a nonexistent account produces a nil value with its ledger context.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get account returns nil when the account does not exist")
    func getAccountReturnsNilWhenTheAccountDoesNotExist() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":null}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAccountInfo(address: address))

        #expect(response.value == nil)
        #expect(response.context.slot == 12345)
    }

    /// Verifies that malformed base64 account data produces a decoding failure.
    @Test("get account rejects invalid base64 data")
    func getAccountRejectsInvalidBase64Data() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":{"lamports":100,"owner":"11111111111111111111111111111111","data":["%%%","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":4}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetAccountInfo(address: address))
        }
    }

    /// Verifies the outgoing address order and the corresponding accounts and ledger slot.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get multiple accounts returns accounts in request order")
    func getMultipleAccountsReturnsAccountsInRequestOrder() async throws {
        let addresses = [address, "11111111111111111111111111111111"]
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[
                    {"lamports":200,"owner":"11111111111111111111111111111111","data":["AQ==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":1},
                    {"lamports":100,"owner":"11111111111111111111111111111111","data":["Ag==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":1}
                ]}
                """#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses))

        #expect(response.value.map { $0?.lamports } == [200, 100])
        #expect(response.context.slot == 12345)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["method"] as? String == "getMultipleAccounts")
        #expect(parameters.count == 2)
        #expect(parameters.first as? [String] == addresses)
        #expect(parameters.last as? [String: String] == ["commitment": "confirmed", "encoding": "base64"])
    }

    /// Verifies that a missing account retains its position between existing accounts.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get multiple accounts preserves missing account positions")
    func getMultipleAccountsPreservesMissingAccountPositions() async throws {
        let addresses = [address, "11111111111111111111111111111111", "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[
                    {"lamports":200,"owner":"11111111111111111111111111111111","data":["AQ==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":1},
                    null,
                    {"lamports":100,"owner":"11111111111111111111111111111111","data":["Ag==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":1}
                ]}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses))

        #expect(response.value.map { $0?.lamports } == [200, nil, 100])
    }

    /// Verifies filter encoding and the returned account's address, state, and ledger slot.
    ///
    /// - Parameters:
    ///   - filter: The mint or token program used to select token accounts.
    ///   - expectedFilter: The single filter field expected in the outgoing request.
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get token accounts returns account addresses and slot", arguments: [
        (GetTokenAccountsByOwner.Filter.mint("So11111111111111111111111111111111111111112"),
         ["mint": "So11111111111111111111111111111111111111112"]),
        (.program("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
         ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]),
    ])
    func getTokenAccountsReturnsAccountAddressesAndSlot(
        filter: GetTokenAccountsByOwner.Filter,
        expectedFilter: [String: String]
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"context":{"slot":12345},"value":[
                    {"pubkey":"BGocb4GEpbTFm8UFV2VsDSaBXHELPfAXrvd4vtt8QWrA","account":{
                        "lamports":2039280,"owner":"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
                        "data":["AQIDBA==","base64"],"executable":false,"rentEpoch":18446744073709551615,"space":4
                    }}
                ]}
                """#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetTokenAccountsByOwner(owner: address, filter: filter))

        #expect(response.value.count == 1)
        let entry = try #require(response.value.first)
        #expect(entry.address == "BGocb4GEpbTFm8UFV2VsDSaBXHELPfAXrvd4vtt8QWrA")
        #expect(entry.account.owner == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        #expect(entry.account.lamports == 2_039_280)
        #expect(response.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        try #require(parameters.count == 3)
        #expect(body["method"] as? String == "getTokenAccountsByOwner")
        #expect(parameters[0] as? String == address)
        #expect(parameters[1] as? [String: String] == expectedFilter)
        #expect(parameters[2] as? [String: String] == ["commitment": "confirmed", "encoding": "base64"])
    }

    /// Verifies that a lookup with no matching accounts returns an empty array and its context.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get token accounts returns an empty collection when none match")
    func getTokenAccountsReturnsAnEmptyCollectionWhenNoneMatch() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":[]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetTokenAccountsByOwner(
            owner: address,
            filter: .program("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        ))

        #expect(response.value.isEmpty)
        #expect(response.context.slot == 12345)
    }

    /// Verifies named DAS parameters and exact balances, metadata, prices, and indexing information.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get assets returns token balances metadata and native SOL")
    func getAssetsReturnsTokenBalancesMetadataAndNativeSOL() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"last_indexed_slot":12345,"page":2,"limit":1000,"items":[{
                    "id":"mint-address","interface":"FungibleToken",
                    "content":{"metadata":{"name":"Example Token","symbol":"EX"},"links":{"image":"https://example.com/token.png"}},
                    "token_info":{"balance":9007199254740993,"decimals":6,
                        "price_info":{"price_per_token":0.1000000000000000001,"total_price":20.25,"currency":"USD"}}
                }],"nativeBalance":{"lamports":1234567890,"price_per_sol":120.5,"total_price":148.765430745}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address, page: 2))

        let asset = try #require(response.items.first)
        #expect(asset.id == "mint-address")
        #expect(asset.balance == 9_007_199_254_740_993)
        #expect(asset.decimals == 6)
        #expect(asset.name == "Example Token")
        #expect(asset.symbol == "EX")
        #expect(asset.imageURL?.absoluteString == "https://example.com/token.png")
        #expect(asset.price?.perToken == Decimal(string: "0.1000000000000000001"))
        #expect(asset.price?.total == Decimal(string: "20.25"))
        #expect(asset.price?.currency == "USD")
        #expect(response.nativeBalance?.lamports == 1_234_567_890)
        #expect(response.nativeBalance?.pricePerSOL == Decimal(string: "120.5"))
        #expect(response.lastIndexedSlot == 12345)
        #expect(response.page == 2)
        #expect(response.limit == 1000)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [String: Any])
        #expect(body["method"] as? String == "getAssetsByOwner")
        #expect(parameters["ownerAddress"] as? String == address)
        #expect(parameters["page"] as? Int == 2)
        #expect(parameters["limit"] as? Int == 1000)
        #expect(parameters["options"] as? [String: Bool] == ["showFungible": true, "showNativeBalance": true])
    }

    /// Verifies that malformed display fields preserve exact balances and healthy metadata.
    ///
    /// - Parameters:
    ///   - content: The synthetic content containing malformed display metadata.
    ///   - expectedName: The available name, or `nil` when malformed or missing.
    ///   - expectedSymbol: The available symbol, or `nil` when malformed or missing.
    ///   - expectedImageURL: The available image, or `nil` when none can be decoded.
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test("get assets preserves holdings when display metadata is malformed", arguments: [
        (#"{"metadata":{"name":"Example Collectible"},"links":{"image":false},"files":[]}"#,
         "Example Collectible", nil as String?, nil as String?),
        (#"{"metadata":{"name":"Example Collectible"},"links":{"image":false},"files":[{"uri":"https://example.com/fallback.png","mime":"image/png"}]}"#,
         "Example Collectible", nil, "https://example.com/fallback.png"),
        (#"{"metadata":{"name":false,"symbol":"EX"},"links":{"image":"https://example.com/token.png"}}"#,
         nil, "EX", "https://example.com/token.png"),
        (#"{"metadata":{"name":"Example Collectible","symbol":false},"files":[false,{"uri":false,"mime":"image/png"},{"uri":"https://example.com/ignored.png","mime":false},{"uri":"https://example.com/fallback.png","mime":"image/png"}]}"#,
         "Example Collectible", nil, "https://example.com/fallback.png"),
        (#"{"metadata":false,"links":false,"files":false}"#, nil, nil, nil),
        ("false", nil, nil, nil),
    ])
    func getAssetsPreservesHoldingsWhenDisplayMetadataIsMalformed(
        content: String, expectedName: String?, expectedSymbol: String?, expectedImageURL: String?
    ) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #"""
                "result":{"page":1,"limit":1000,"items":[
                    {"id":"collectible","interface":"V1_NFT","content":\#(content),
                     "token_info":{"balance":1,"decimals":0,"symbol":false}},
                    {"id":"mint-address","interface":"FungibleToken",
                     "token_info":{"balance":42,"decimals":6}}
                ],"nativeBalance":{"lamports":12345}}
                """#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        #expect(response.items.map(\.id) == ["collectible", "mint-address"])
        let collectible = try #require(response.items.first)
        #expect(collectible.name == expectedName)
        #expect(collectible.symbol == expectedSymbol)
        #expect(collectible.imageURL?.absoluteString == expectedImageURL)
        #expect(collectible.balance == 1)
        #expect(collectible.decimals == 0)
        let token = try #require(response.items.last)
        #expect(token.balance == 42)
        #expect(token.decimals == 6)
        #expect(response.nativeBalance?.lamports == 12345)
    }

    /// Verifies that metadata recovery never accepts malformed asset identity or amounts.
    ///
    /// - Parameter asset: A synthetic asset with an invalid required identity or supplied amount.
    @Test("get assets rejects malformed identity and amount fields", arguments: [
        #"{"id":false,"interface":"FungibleToken"}"#,
        #"{"id":"mint","interface":"FungibleToken","token_info":{"balance":"unknown","decimals":6}}"#,
        #"{"id":"mint","interface":"FungibleToken","token_info":{"balance":42,"decimals":1.5}}"#,
    ])
    func getAssetsRejectsMalformedIdentityAndAmountFields(asset: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[\#(asset)]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(GetAssetsByOwner(owner: address))
        }
    }

    /// Verifies that a token remains available when metadata and prices are absent.
    ///
    /// - Throws: An RPC error or a failed test prerequisite.
    @Test("get assets preserves balances without metadata or prices")
    func getAssetsPreservesBalancesWithoutMetadataOrPrices() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[{"id":"unknown-mint","interface":"FungibleToken","token_info":{"balance":18446744073709551615,"decimals":9}}]}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        let asset = try #require(response.items.first)
        #expect(asset.balance == UInt64.max)
        #expect(asset.name == nil)
        #expect(asset.symbol == nil)
        #expect(asset.imageURL == nil)
        #expect(asset.price == nil)
        #expect(response.lastIndexedSlot == nil)
    }

    /// Verifies that a wallet without assets retains an explicit zero native balance.
    ///
    /// - Throws: An RPC error.
    @Test("get assets returns an empty asset list and zero native SOL")
    func getAssetsReturnsAnEmptyAssetListAndZeroNativeSOL() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"page":1,"limit":1000,"items":[],"nativeBalance":{"lamports":0}}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let response = try await rpc.send(GetAssetsByOwner(owner: address))

        #expect(response.items.isEmpty)
        #expect(response.nativeBalance?.lamports == 0)
    }

    /// Verifies the parameterless version request and its decoded node metadata.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get version returns node version and feature set")
    func getVersionReturnsNodeVersionAndFeatureSet() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"solana-core":"3.0.0","feature-set":2891131721}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        let version = try await rpc.send(GetVersion())

        #expect(version.solanaCore == "3.0.0")
        #expect(version.featureSet == 2_891_131_721)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        #expect(body["method"] as? String == "getVersion")
        #expect((body["params"] as? [String]) == [])
    }

    /// Verifies that an invalid-address rejection preserves the server's code and message.
    @Test("get balance reports an invalid wallet address")
    func getBalanceReportsAnInvalidWalletAddress() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32602,"message":"Invalid param: WrongSize"}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: -32602, message: "Invalid param: WrongSize")) {
            try await rpc.send(GetBalance(address: "invalid-address"))
        }
    }

    /// Verifies that server errors returned by the client omit its API key and endpoint.
    ///
    /// - Parameter network: The Solana network whose authenticated endpoint to redact.
    @Test("server errors hide API keys and authenticated URLs", arguments: [Network.mainnet, .devnet])
    func serverErrorsHideAPIKeysAndAuthenticatedURLs(network: Network) async {
        let apiKey = "test-key"
        let transport = StubTransport { request in
            let endpoint = try #require(request.url?.absoluteString)
            return try reply(to: request,
                             payload: #""error":{"code":-32603,"message":"Request \#(endpoint) failed for \#(apiKey)"}"#)
        }
        let rpc = HeliusRPC(apiKey: apiKey, network: network, transport: transport)

        await #expect(throws: RPCError.server(code: -32603, message: "Request [redacted] failed for [redacted]")) {
            try await rpc.send(GetVersion())
        }
    }

    /// Verifies that rate limiting exposes the retry delay without another HTTP attempt.
    @Test("rate limited requests expose the retry delay without retrying")
    func rateLimitedRequestsExposeTheRetryDelayWithoutRetrying() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32005,"message":"Too many requests"}"#,
                      status: 429, headers: ["Retry-After": "5"])
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5")) {
            try await rpc.send(GetBalance(address: address))
        }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies that a response with a different request identifier is rejected.
    @Test("responses belonging to another request are rejected")
    func responsesBelongingToAnotherRequestAreRejected() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":100}"#,
                      id: "another-request")
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await rpc.send(GetBalance(address: address))
        }
    }

    /// Verifies transport cancellation after an RPC request has started.
    ///
    /// Streams coordinate request startup and cancellation without timed sleeps.
    ///
    /// - Throws: A test prerequisite error if the transport doesn't signal startup.
    @Test("cancelling a request cancels the HTTP operation", .timeLimit(.minutes(1)))
    func cancellingARequestCancelsTheHTTPOperation() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, pendingContinuation) = AsyncStream<Void>.makeStream()
        let transport = StubTransport { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            throw URLError(.cancelled)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let task = Task { @concurrent in try await rpc.send(GetVersion()) }
        defer {
            task.cancel()
            startedContinuation.finish()
            pendingContinuation.finish()
        }
        var iterator = started.makeAsyncIterator()
        try #require(await iterator.next() != nil)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.observedCancellation)
    }
}

/// A transport that records requests and delegates responses to a fixture closure.
private actor StubTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private(set) var observedCancellation = false
    private let respond: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Creates a transport with a fixture response handler.
    ///
    /// - Parameter respond: The closure that produces a response or throws an error.
    init(respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.respond = respond
    }

    /// Records a request and awaits its fixture response.
    ///
    /// - Parameter request: The outgoing request to record and pass to the handler.
    /// - Returns: The response body and metadata produced by the handler.
    /// - Throws: Any error thrown by the fixture handler.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        do {
            return try await respond(request)
        } catch {
            observedCancellation = Task.isCancelled
            throw error
        }
    }
}

/// Decodes an outgoing request body as a JSON object for assertions.
///
/// - Parameter request: The HTTP request whose body to inspect.
/// - Returns: The request's JSON object, keyed by field name.
/// - Throws: A JSON parsing error, or a test prerequisite error if the body is
///   missing or isn't an object.
private func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Creates an HTTP fixture response containing a JSON-RPC envelope.
///
/// - Parameters:
///   - request: The request supplying the URL and default response identifier.
///   - payload: A JSON member containing either `result` or `error`.
///   - status: The HTTP status code. The default is 200.
///   - headers: The response header fields. The default is an empty dictionary.
///   - id: A response identifier override, or `nil` to echo the request's identifier.
/// - Returns: The encoded response envelope and its HTTP metadata.
/// - Throws: A JSON parsing error, or a test prerequisite error if required
///   request fields or response metadata can't be obtained.
private func reply(
    to request: URLRequest,
    payload: String,
    status: Int = 200,
    headers: [String: String] = [:],
    id: String? = nil
) throws -> (Data, URLResponse) {
    let requestID = try #require(requestBody(request)["id"] as? String)
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    let data = Data(#"{"jsonrpc":"2.0","id":"\#(id ?? requestID)",\#(payload)}"#.utf8)
    return (data, response)
}
