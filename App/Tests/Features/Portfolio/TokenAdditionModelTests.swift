import Foundation
import Observation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenAdditionModelTests {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    private static let jup = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"

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

    @Test
    func `Each rejection signals again`() {
        let addition = TokenAdditionModel()

        addition.paste("not an address")
        addition.paste("still not an address")

        #expect(addition.rejection == .notAddress)
        #expect(addition.rejectionCount == 2)
    }

    @Test
    func `A pasted address shows its token`() async throws {
        let preview = Self.preview(Self.bonk)
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

    @Test
    func `A rejection stays until the next lookup answers`() async throws {
        let preview = Self.preview(Self.jup)
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

    @Test
    func `A listed token is rejected without a lookup`() async throws {
        let service = PortfolioResponses()
        let portfolios = PortfolioStore.serving(service)
        let account = try Account.fixture(index: 1)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolios.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let bonk = Holding.fixture(.fixture(Self.bonk, decimals: 5), amount: nil)
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

    @Test
    func `A new address replaces the previous preview`() async throws {
        let preview = Self.preview(Self.bonk)
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

    @Test(arguments: [nil, TokenLookupError.notToken, RPCError.http(statusCode: 503, retryAfter: nil)] as [(any Error)?])
    func `A lookup that ends after a newer paste is ignored`(error: (any Error)?) async throws {
        let gate = Suspension()
        let service = PortfolioResponses(preview: Self.preview(Self.bonk), lookupGate: gate)
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

    @Test
    func `Adding the previewed token closes the sheet`() async throws {
        let preview = Self.preview(Self.bonk)
        let service = PortfolioResponses(preview: preview)
        let portfolios = PortfolioStore.serving(service)
        let addition = TokenAdditionModel()
        addition.paste(Self.bonk)
        try await addition.lookUp(in: portfolios)

        addition.add()
        try await addition.run(in: portfolios)

        #expect(await service.added == [preview.mint])
        #expect(addition.isAdded)
        #expect(addition.attempt == nil)
    }

    @Test(arguments: [
        (TokenListError.limitReached, TokenAdditionError.limitReached),
        (.unreadable, .listUnreadable),
    ])
    func `A list that can't take the token explains why`(error: TokenListError, expected: TokenAdditionError) async throws {
        let service = PortfolioResponses(preview: Self.preview(Self.bonk))
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

    @Test
    func `A failed save can try again`() async throws {
        let preview = Self.preview(Self.bonk)
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

        #expect(await service.added == [preview.mint])
        #expect(addition.isAdded)
    }

    @Test(arguments: [
        (RPCProviderError.invalidKey, TokenAdditionError.keyRejected),
        (.unsupportedNetwork, .unsupportedNetwork),
    ])
    func `A provider setup failure offers no retry until the address is pasted again`(error: RPCProviderError,
                                                                                      expected: TokenAdditionError) async throws {
        let preview = Self.preview(Self.bonk)
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

    @Test
    func `A failed lookup can try again`() async throws {
        let preview = Self.preview(Self.bonk)
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

    private static func preview(_ mint: String) -> TokenPreview {
        TokenPreview(mint: .fixture(mint, decimals: 5, name: "Bonk", symbol: "Bonk"),
                     logo: nil)
    }
}

private extension TokenAdditionModel {
    func lookUp(in portfolios: PortfolioStore) async throws {
        await lookUp(lookup, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }

    func run(in portfolios: PortfolioStore) async throws {
        await run(attempt, in: portfolios, for: try .fixture(index: 1), on: .devnet)
    }
}
