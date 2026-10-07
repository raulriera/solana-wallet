import Foundation
import RPC
import Testing
import Transactions
@testable import Portfolio

/// Verifies each account's token list: its defaults, its limit, and saving it without losing added tokens.
struct TokenListTests {
    /// The ways a saved list can fail to belong to the account that reads it.
    enum UnreadableFile: CaseIterable {
        /// Bytes that don't decode as a token list.
        case corrupt
        /// A valid list saved for another account.
        case anotherAccount
    }

    /// Verifies new lists hold each network's defaults, which mainnet pins by mint address.
    @Test
    func `New mainnet lists start with USDC and USDT, and devnet lists start empty`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let mainnet = try await fixture.portfolio(network: .mainnet).tokenList(for: "wallet")
        let devnet = try await fixture.portfolio(network: .devnet).tokenList(for: "wallet")
        #expect(mainnet.tokens.map(\.mint.value) == ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                                                     "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"])
        #expect(mainnet.tokens.map(\.symbol) == ["USDC", "USDT"])
        #expect(mainnet.tokens.map(\.name) == ["USD Coin", "Tether USD"])
        #expect(mainnet.tokens.allSatisfy { $0.program == .token && $0.decimals == 6 })
        #expect(devnet.tokens.isEmpty)
    }

    /// Verifies additions and removals are saved in order.
    @Test
    func `Added and removed tokens survive a new service`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let added = try token(1)
        _ = try await service.addToken(added, for: "wallet")
        let usdc = try #require(try await service.tokenList(for: "wallet").tokens.first)
        _ = try await service.removeToken(usdc.mint, for: "wallet")
        let restored = try await fixture.portfolio().tokenList(for: "wallet")
        #expect(restored.tokens.map(\.symbol) == ["USDT", "T1"])
        #expect(restored.tokens.last == added)
    }

    /// Verifies a token that's already listed keeps its place instead of appearing twice.
    @Test
    func `Adding a listed token changes nothing`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let before = try await service.tokenList(for: "wallet")
        let usdc = try #require(before.tokens.first)
        #expect(try await service.addToken(usdc, for: "wallet") == before)
    }

    /// Verifies the limit counts added tokens only.
    @Test
    func `A list takes fifty added tokens and refuses the fifty-first`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        for index in 1...TokenList.addedTokenLimit {
            _ = try await service.addToken(token(index), for: "wallet")
        }
        let extra = try token(TokenList.addedTokenLimit + 1)
        await #expect(throws: TokenListError.limitReached) { try await service.addToken(extra, for: "wallet") }
        let list = try await service.tokenList(for: "wallet")
        #expect(list.tokens.count == TokenList.addedTokenLimit + 2)
    }

    /// Verifies a default someone removed still fits in a full list when they add it again.
    @Test
    func `A removed default token fits again in a full list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let usdc = try #require(try await service.tokenList(for: "wallet").tokens.first)
        _ = try await service.removeToken(usdc.mint, for: "wallet")
        for index in 1...TokenList.addedTokenLimit {
            _ = try await service.addToken(token(index), for: "wallet")
        }
        let list = try await service.addToken(usdc, for: "wallet")
        #expect(list.tokens.last == usdc)
    }

    /// Verifies a saved list that can't be read stops reads and changes, and its file stays as it was.
    ///
    /// - Parameter file: The kind of saved file the account can't use.
    @Test(arguments: UnreadableFile.allCases)
    func `An unreadable saved list stays in place instead of becoming the defaults`(_ file: UnreadableFile) async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let files = KeyedFiles(directory: fixture.directory)
        let key = CacheKey(owner: "wallet", network: .mainnet)
        switch file {
        case .corrupt:
            try files.write(Data("not a token list".utf8), for: key)
        case .anotherAccount:
            let other = CacheKey(owner: "other", network: .mainnet)
            try fixture.store.save(TokenList(defaultsFor: .mainnet), for: other)
            try files.write(try #require(try files.read(for: other)), for: key)
        }
        let saved = try files.read(for: key)
        let service = fixture.portfolio()
        let added = try token(1)
        await #expect(throws: TokenListError.unreadable) { try await service.tokenList(for: "wallet") }
        await #expect(throws: TokenListError.unreadable) { try await service.addToken(added, for: "wallet") }
        #expect(try files.read(for: key) == saved)
    }

    /// Verifies removing a wallet's data takes its list with it, so a later read starts from the defaults.
    @Test
    func `Removing an account's data removes its token list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        _ = try await service.addToken(token(1), for: "wallet")
        try await service.removeData(for: "wallet")
        #expect(try KeyedFiles(directory: fixture.directory).read(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
        #expect(try await service.tokenList(for: "wallet").tokens.map(\.symbol) == ["USDC", "USDT"])
    }

    /// Verifies simultaneous edits, as from several windows, don't overwrite each other.
    @Test
    func `Simultaneous additions all reach the saved list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let tokens = try (1...20).map(token)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask { _ = try await service.addToken(token, for: "wallet") }
            }
            try await group.waitForAll()
        }
        let saved = try await fixture.portfolio().tokenList(for: "wallet")
        #expect(Set(saved.tokens.map(\.mint)).isSuperset(of: tokens.map(\.mint)))
        #expect(saved.tokens.count == tokens.count + 2)
    }
}

/// A private token-list directory for one test.
private struct TokenListFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// The token-list store in this test's directory.
    var store: FileTokenListStore { FileTokenListStore(directory: directory) }

    /// Creates a service that keeps its token lists and snapshots in this test's directory.
    ///
    /// The service makes no network requests for token lists.
    /// - Parameter network: The network of the service's RPC client.
    /// - Returns: A service backed by this test's files.
    func portfolio(network: Network = .mainnet) -> Portfolio {
        Portfolio(rpc: Solana(network: network),
                  store: FileSnapshotStore(directory: directory.appendingPathComponent("Snapshots")), tokenLists: store)
    }

    /// Removes only this test's files.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

/// Creates a token with a distinct, valid mint address, so tests can fill a list.
///
/// - Parameter index: A number from 1 to 57; each gives a different mint.
/// - Returns: A Token-2022 token named after the index.
/// - Throws: A validation error if the generated address is malformed.
private func token(_ index: Int) throws -> ListedToken {
    // Thirty-one leading "1"s encode zero bytes, so one more Base58 digit completes a 32-byte address.
    let digits = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    let mint = try Address(String(repeating: "1", count: 31) + String(digits[index - 1]))
    return ListedToken(mint: mint, program: .token2022, decimals: 9, symbol: "T\(index)", name: "Token \(index)")
}
