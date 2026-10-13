import Foundation
import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks the add-token sheet: what it says about pasted text, and what it adds.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TokenAdditionTests {
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
    private static let jup = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"

    /// Pasted text that isn't an address asks for a valid one and looks nothing up.
    @Test
    func `Pasted text that isn't an address asks for one without a lookup`() {
        let addition = TokenAddition(coordinator: RecordingPortfolio())

        addition.paste("not an address")
        #expect(shown(addition.message) == "This isn't a valid address.")
        #expect(addition.refusalCount == 1)
        #expect(addition.lookup == nil)

        addition.paste("")
        #expect(addition.message == nil)
    }

    /// Each refusal signals again, even when the same message is already on screen.
    @Test
    func `Each refusal signals again`() {
        let addition = TokenAddition(coordinator: RecordingPortfolio())

        addition.paste("not an address")
        addition.paste("still not an address")

        #expect(shown(addition.message) == "This isn't a valid address.")
        #expect(addition.refusalCount == 2)
    }

    /// A pasted address, with the spaces and line break a copy can bring, shows the token it names.
    /// - Throws: A test prerequisite error.
    @Test
    func `A pasted address shows its token`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAddition(coordinator: portfolio)

        addition.paste(" \(Self.bonk)\n")
        await addition.lookUp(addition.lookup)

        #expect(addition.text == Self.bonk)
        #expect(addition.preview == portfolio.preview)
        #expect(addition.message == nil)
        #expect(portfolio.lookups.map(\.value) == [Self.bonk])
    }

    /// A refusal stays while the next address is looked up, so its message changes in place, and a found token clears it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A refusal stays until the next lookup answers`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.lookupError = TokenLookupError.notToken
        let addition = TokenAddition(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        portfolio.lookupError = nil
        portfolio.preview = try Self.preview(Self.jup)
        addition.paste(Self.jup)
        #expect(shown(addition.message) == "This address isn't a token.")

        await addition.lookUp(addition.lookup)
        #expect(addition.message == nil)
        #expect(addition.preview == portfolio.preview)
    }

    /// A token that's already in the list is refused before any lookup.
    @Test
    func `A listed token is refused without a lookup`() async {
        let portfolio = RecordingPortfolio()
        portfolio.holdings = [Holding(id: .asset(Self.bonk), amount: nil, name: "Bonk", symbol: "Bonk", imageURL: nil,
                                      valuation: nil)]
        let addition = TokenAddition(coordinator: portfolio)

        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        #expect(shown(addition.message) == "This token is already in your list.")
        #expect(addition.refusalCount == 1)
        #expect(portfolio.lookups.isEmpty)
    }

    /// Addresses that aren't fungible token mints are refused with what they are.
    /// - Parameters:
    ///   - error: Why the lookup refused the address.
    ///   - message: What the sheet says under the pasted text.
    @Test(arguments: [(TokenLookupError.notToken, "This address isn't a token."),
                      (.nonFungible, "NFTs can't be added yet.")])
    func `Addresses that aren't fungible tokens are refused`(error: TokenLookupError, message: String) async {
        let portfolio = RecordingPortfolio()
        portfolio.lookupError = error
        let addition = TokenAddition(coordinator: portfolio)

        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)

        #expect(shown(addition.message) == message)
        #expect(addition.refusalCount == 1)
        #expect(addition.preview == nil)
    }

    /// A different address replaces the previous preview at once, so the earlier token can't be added by mistake.
    /// - Throws: A test prerequisite error.
    @Test
    func `A new address replaces the previous preview`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAddition(coordinator: portfolio)
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
        let addition = TokenAddition(coordinator: portfolio)
        addition.paste(Self.bonk)
        let stale = addition.lookup
        let lookup = Task { await addition.lookUp(stale) }
        for await _ in portfolio.heldLookups { break }

        addition.paste(Self.jup)
        let newer = addition.lookup
        portfolio.releaseLookups()
        await lookup.value

        #expect(addition.preview == nil)
        #expect(addition.message == nil)
        #expect(addition.error == nil)
        #expect(addition.lookup == newer)
    }

    /// Adding the previewed token saves it and closes the sheet.
    /// - Throws: A test prerequisite error.
    @Test
    func `Adding the previewed token closes the sheet`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        let addition = TokenAddition(coordinator: portfolio)
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
    ///   - error: Why the list refused the token.
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
        let addition = TokenAddition(coordinator: portfolio)
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
        let addition = TokenAddition(coordinator: portfolio)
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

    /// A rejected RPC API key offers no retry, and pasting the address again looks it up again.
    /// - Throws: A test prerequisite error.
    @Test
    func `A rejected key offers no retry until the address is pasted again`() async throws {
        let portfolio = RecordingPortfolio()
        portfolio.preview = try Self.preview(Self.bonk)
        portfolio.lookupError = ProviderClientError.invalidKey
        let addition = TokenAddition(coordinator: portfolio)
        addition.paste(Self.bonk)
        await addition.lookUp(addition.lookup)
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
        let addition = TokenAddition(coordinator: portfolio)
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

    /// Resolves a message the sheet shows, for comparison with its English text.
    /// - Parameter message: The message, if any.
    /// - Returns: The message's text, or `nil` when there's none.
    private func shown(_ message: LocalizedStringResource?) -> String? {
        message.map { String(localized: $0) }
    }
}
