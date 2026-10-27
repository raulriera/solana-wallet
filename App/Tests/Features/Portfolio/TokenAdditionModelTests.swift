import Foundation
import Observation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks the add-token sheet's model: how it rejects pasted text, and what it adds.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenAdditionModelTests {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    private static let jup = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"

    /// Pasted text that isn't an address asks for a valid one and looks nothing up.
    @Test
    func `Pasted text that isn't an address asks for one without a lookup`() {
        let addition = TokenAdditionModel()

        addition.paste("not an address")
        #expect(addition.rejection == .notAddress)
        #expect(addition.rejectionCount == 1)
        #expect(addition.lookup == nil)

        addition.paste("")
        #expect(addition.rejection == nil)
    }

    /// Each rejection signals again, even when the same rejection is already on screen.
    @Test
    func `Each rejection signals again`() {
        let addition = TokenAdditionModel()

        addition.paste("not an address")
        addition.paste("still not an address")

        #expect(addition.rejection == .notAddress)
        #expect(addition.rejectionCount == 2)
    }

    /// A pasted address, with the spaces and line break a copy can bring, shows the token it names.
    /// - Throws: A test prerequisite error.
    @Test
    func `A pasted address shows its token`() async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()

        addition.paste(" \(Self.bonk)\n")
        try await addition.lookUp(in: portfolios)

        #expect(addition.text == Self.bonk)
        #expect(addition.preview == preview)
        #expect(addition.rejection == nil)
        #expect(await service.lookups.map(\.value) == [Self.bonk])
    }

    /// A rejection stays while the next address is looked up, so it changes in place, and a found token clears it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A rejection stays until the next lookup answers`() async throws {
        let preview = try Self.preview(Self.jup)
        let service = PortfolioResponses(preview: preview)
        await service.failLookups(with: TokenLookupError.notToken)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        await service.failLookups(with: nil)
        addition.paste(Self.jup)
        #expect(addition.rejection == .notToken)

        try await addition.lookUp(in: portfolios)
        #expect(addition.rejection == nil)
        #expect(addition.preview == preview)
    }

    /// A token that's already in the list is rejected before any lookup.
    @Test
    /// - Throws: A test prerequisite error.
    func `A listed token is rejected without a lookup`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let account = try Account.fixture(index: 1)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolios.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let bonk = Holding(id: .asset(Self.bonk), amount: nil, name: "Bonk", symbol: "Bonk", imageURL: nil,
                           valuation: nil)
        observation.continuation.yield(Update(snapshot: Snapshot(owner: account.address.value, network: .devnet,
                                                                 holdings: [bonk]),
                                              phase: .ready, revision: 1))
        for await holdings in Observations({ portfolios.portfolio(for: account, on: .devnet)?.holdings ?? [] })
        where !holdings.isEmpty {
            break
        }
        let addition = TokenAdditionModel()

        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        #expect(addition.rejection == .alreadyListed)
        #expect(addition.rejectionCount == 1)
        #expect(await service.lookups.isEmpty)
    }

    /// Addresses that aren't fungible token mints are rejected with what they are.
    /// - Parameters:
    ///   - error: Why the lookup rejected the address.
    ///   - rejection: Why the sheet rejects the address.
    @Test(arguments: [(TokenLookupError.notToken, TokenRejection.notToken), (.nonFungible, .nonFungible)])
    func `Addresses that aren't fungible tokens are rejected`(error: TokenLookupError,
                                                              rejection: TokenRejection) async throws {
        let service = PortfolioResponses()
        await service.failLookups(with: error)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()

        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        #expect(addition.rejection == rejection)
        #expect(addition.rejectionCount == 1)
        #expect(addition.preview == nil)
    }

    /// A different address replaces the previous preview at once, so the earlier token can't be added by mistake.
    /// - Throws: A test prerequisite error.
    @Test
    func `A new address replaces the previous preview`() async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)
        try #require(addition.preview == preview)
        let previous = addition.lookup

        addition.paste(Self.jup)

        #expect(addition.preview == nil)
        #expect(addition.lookup != nil && addition.lookup != previous)
    }

    /// A lookup that ends after a newer paste leaves the newer address's state alone, whatever its result.
    /// - Parameter error: The stale lookup's failure, or `nil` when it finds the token.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [nil, TokenLookupError.notToken, RPCError.http(statusCode: 503, retryAfter: nil)] as [(any Error)?])
    func `A lookup that ends after a newer paste is ignored`(error: (any Error)?) async throws {
        let gate = Suspension()
        let service = PortfolioResponses(preview: try Self.preview(Self.bonk), lookupGate: gate)
        await service.failLookups(with: error)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        let stale = addition.lookup
        let account = try Account.fixture(index: 1)
        let lookup = Task { await addition.lookUp(stale, in: portfolios, for: account, on: .devnet) }
        await gate.waitUntilStarted()

        addition.paste(Self.jup)
        let newer = addition.lookup
        gate.resume()
        await lookup.value

        #expect(addition.preview == nil)
        #expect(addition.rejection == nil)
        #expect(addition.error == nil)
        #expect(addition.lookup == newer)
    }

    /// Adding the previewed token saves it and closes the sheet.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding the previewed token closes the sheet`() async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        addition.add()
        try await addition.run(in: portfolios)

        #expect(await service.added == [preview.token])
        #expect(addition.isAdded)
        #expect(addition.attempt == nil)
    }

    /// A list that is full or can't be read explains why and keeps the sheet open, without offering to try again.
    /// - Parameters:
    ///   - error: Why the list rejected the token.
    ///   - expected: The error the alert explains.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [
        (TokenListError.limitReached, TokenAdditionError.limitReached),
        (.unreadable, .listUnreadable),
    ])
    func `A list that can't take the token explains why`(error: TokenListError, expected: TokenAdditionError) async throws {
        let service = PortfolioResponses(preview: try Self.preview(Self.bonk))
        await service.failAdds(with: error)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        addition.add()
        try await addition.run(in: portfolios)

        #expect(addition.error == expected)
        #expect(addition.error?.canRetry == false)
        #expect(!addition.isAdded)
    }

    /// A token list that fails to save keeps the sheet open, and trying again adds the token.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed save can try again`() async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        await service.failAdds(with: CocoaError(.fileWriteUnknown))
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)
        addition.add()
        try await addition.run(in: portfolios)
        #expect(addition.error == .saveFailed)
        #expect(addition.error?.canRetry == true)
        #expect(!addition.isAdded)

        await service.failAdds(with: nil)
        addition.error = nil
        addition.retry()
        try await addition.run(in: portfolios)

        #expect(await service.added == [preview.token])
        #expect(addition.isAdded)
    }

    /// A rejected RPC API key, or a provider that doesn't serve the network, offers no retry, and pasting the address
    /// again looks it up again.
    /// - Parameters:
    ///   - error: The provider's failure.
    ///   - expected: The error the alert explains.
    /// - Throws: A test prerequisite error.
    @Test(arguments: [
        (ProviderClientError.invalidKey, TokenAdditionError.keyRejected),
        (.unsupportedNetwork, .unsupportedNetwork),
    ])
    func `A provider setup failure offers no retry until the address is pasted again`(error: ProviderClientError,
                                                                                      expected: TokenAdditionError) async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        await service.failLookups(with: error)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)
        #expect(addition.error == expected)
        #expect(addition.error?.canRetry == false)
        #expect(addition.lookup == nil)

        await service.failLookups(with: nil)
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        #expect(addition.preview == preview)
    }

    /// A lookup that fails for a reason outside the address can run again.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed lookup can try again`() async throws {
        let preview = try Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        await service.failLookups(with: RPCError.http(statusCode: 503, retryAfter: nil))
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)
        #expect(addition.error?.canRetry == true)

        await service.failLookups(with: nil)
        addition.error = nil
        addition.retry()
        try await addition.lookUp(in: portfolios)

        #expect(addition.preview == preview)
        #expect(await service.lookups.count == 2)
    }

    /// Builds the preview of a token at an address.
    /// - Parameter mint: The token's mint address.
    /// - Returns: A preview without a logo.
    /// - Throws: A validation error if the address is malformed.
    private static func preview(_ mint: String) throws -> TokenPreview {
        TokenPreview(token: ListedToken(mint: try Address(mint), program: .token, decimals: 5, symbol: "Bonk",
                                        name: "Bonk"), logo: nil)
    }
}

private extension TokenAdditionModel {
    /// Looks up the pasted address for the test account on devnet, as the add-token screen's task does.
    /// - Parameter portfolios: The portfolios under test.
    /// - Throws: A fixture error.
    func lookUp(in portfolios: PortfolioStore) async throws {
        await lookUp(lookup, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }

    /// Adds the previewed token to the test account's list on devnet, as the add-token screen's task does.
    /// - Parameter portfolios: The portfolios under test.
    /// - Throws: A fixture error.
    func run(in portfolios: PortfolioStore) async throws {
        await run(attempt, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }
}
