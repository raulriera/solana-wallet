import Foundation
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
        let addition = TokenAdditionModel(coordinator: RecordingPortfolio())

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
        let addition = TokenAdditionModel(coordinator: RecordingPortfolio())

        addition.paste("not an address")
        addition.paste("still not an address")

        #expect(addition.rejection == .notAddress)
        #expect(addition.rejectionCount == 2)
    }

    /// A pasted address, with the spaces and line break a copy can bring, shows the token it names.
    /// - Throws: A test prerequisite error.
    @Test
    func `A pasted address shows its token`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAdditionModel(coordinator: portfolio)

        addition.paste(" \(Self.bonk)\n")
        await addition.lookUp(addition.lookup)

        #expect(addition.text == Self.bonk)
        #expect(addition.preview == portfolio.preview)
        #expect(addition.rejection == nil)
        #expect(portfolio.lookups.map(\.value) == [Self.bonk])
    }

    /// A rejection stays while the next address is looked up, so it changes in place, and a found token clears it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A rejection stays until the next lookup answers`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.lookupError = TokenLookupError.notToken
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        portfolio.lookupError = nil
        portfolio.preview = try Self.preview(Self.jup)
        addition.paste(Self.jup)
        #expect(addition.rejection == .notToken)

        await addition.lookUp(addition.lookup)
        #expect(addition.rejection == nil)
        #expect(addition.preview == portfolio.preview)
    }

    /// A token that's already in the list is rejected before any lookup.
    @Test
    func `A listed token is rejected without a lookup`() async {
        let portfolio = RecordingPortfolio()
        portfolio.holdings = [Holding(id: .asset(Self.bonk), amount: nil, name: "Bonk", symbol: "Bonk", imageURL: nil,
                                      valuation: nil)]
        let addition = TokenAdditionModel(coordinator: portfolio)

        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        #expect(addition.rejection == .alreadyListed)
        #expect(addition.rejectionCount == 1)
        #expect(portfolio.lookups.isEmpty)
    }

    /// Addresses that aren't fungible token mints are rejected with what they are.
    /// - Parameters:
    ///   - error: Why the lookup rejected the address.
    ///   - rejection: Why the sheet rejects the address.
    @Test(arguments: [(TokenLookupError.notToken, TokenRejection.notToken), (.nonFungible, .nonFungible)])
    func `Addresses that aren't fungible tokens are rejected`(error: TokenLookupError,
                                                              rejection: TokenRejection) async {
        let portfolio = RecordingPortfolio()
        portfolio.lookupError = error
        let addition = TokenAdditionModel(coordinator: portfolio)

        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        #expect(addition.rejection == rejection)
        #expect(addition.rejectionCount == 1)
        #expect(addition.preview == nil)
    }

    /// A different address replaces the previous preview at once, so the earlier token can't be added by mistake.
    /// - Throws: A test prerequisite error.
    @Test
    func `A new address replaces the previous preview`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)
        try #require(addition.preview == portfolio.preview)
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
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.lookupError = error
        portfolio.holdsLookups = true
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        let stale = addition.lookup
        let lookup = Task { await addition.lookUp(stale) }
        for await _ in portfolio.heldLookups { break }

        addition.paste(Self.jup)
        let newer = addition.lookup
        portfolio.releaseLookups()
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
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        addition.add()
        await addition.run(addition.attempt)

        #expect(portfolio.added == [portfolio.preview?.token])
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
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.addError = error
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        addition.add()
        await addition.run(addition.attempt)

        #expect(addition.error == expected)
        #expect(addition.error?.canRetry == false)
        #expect(!addition.isAdded)
    }

    /// A token list that fails to save keeps the sheet open, and trying again adds the token.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed save can try again`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.addError = CocoaError(.fileWriteUnknown)
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)
        addition.add()
        await addition.run(addition.attempt)
        #expect(addition.error == .saveFailed)
        #expect(addition.error?.canRetry == true)
        #expect(!addition.isAdded)

        portfolio.addError = nil
        addition.error = nil
        addition.retry()
        await addition.run(addition.attempt)

        #expect(portfolio.added == [portfolio.preview?.token])
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
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.lookupError = error
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)
        #expect(addition.error == expected)
        #expect(addition.error?.canRetry == false)
        #expect(addition.lookup == nil)

        portfolio.lookupError = nil
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        #expect(addition.preview == portfolio.preview)
    }

    /// A lookup that fails for a reason outside the address can run again.
    /// - Throws: A test prerequisite error.
    @Test
    func `A failed lookup can try again`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.lookupError = RPCError.http(statusCode: 503, retryAfter: nil)
        let addition = TokenAdditionModel(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)
        #expect(addition.error?.canRetry == true)

        portfolio.lookupError = nil
        addition.error = nil
        addition.retry()
        await addition.lookUp(addition.lookup)

        #expect(addition.preview == portfolio.preview)
        #expect(portfolio.lookups.count == 2)
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
