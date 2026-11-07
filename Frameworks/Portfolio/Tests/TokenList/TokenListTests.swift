import Foundation
import RPC
import Testing
import Transactions
@testable import Portfolio

struct TokenListTests {
    enum UnreadableFile: CaseIterable {
        case corrupt
        case anotherAccount
    }

    @Test
    func `New mainnet lists start with USDC and USDT, and devnet lists start empty`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        async let mainnetList = fixture.list(for: "wallet", network: .mainnet)
        async let devnetList = fixture.list(for: "wallet", network: .devnet)
        let (mainnet, devnet) = try await (mainnetList, devnetList)
        #expect(mainnet.tokens.map(\.mint.value) == ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                                                     "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"])
        #expect(mainnet.tokens.map(\.symbol) == ["USDC", "USDT"])
        #expect(mainnet.tokens.map(\.name) == ["USD Coin", "Tether USD"])
        #expect(mainnet.tokens.allSatisfy { $0.program == .token && $0.decimals == 6 })
        #expect(devnet.tokens.isEmpty)
    }

    @Test
    func `Added and removed tokens are saved in order`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let added = try token(1)
        try await service.addToken(added, for: "wallet")
        let usdc = try #require(try await fixture.list(for: "wallet").tokens.first)
        try await service.removeToken(usdc.mint, for: "wallet")
        let restored = try await fixture.list(for: "wallet")
        #expect(restored.tokens.map(\.symbol) == ["USDT", "T1"])
        #expect(restored.tokens.last == added)
    }

    @Test
    func `A removed token leaves the cached holdings`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let tokens = try await fixture.list(for: "wallet").tokens
        let holdings = [Holding(id: .nativeSOL, amount: Amount(units: 1, decimals: 9), name: "Solana", symbol: "SOL",
                                imageURL: nil, valuation: nil)]
            + tokens.map { Holding(id: .asset($0.mint.value), amount: Amount(units: 1, decimals: $0.decimals),
                                   name: $0.name, symbol: $0.symbol, imageURL: nil, valuation: nil) }
        try fixture.snapshots.save(Snapshot(owner: "wallet", network: .mainnet, holdings: holdings),
                                   for: CacheKey(owner: "wallet", network: .mainnet))
        let usdc = try #require(tokens.first)

        try await service.removeToken(usdc.mint, for: "wallet")

        let saved = fixture.snapshots.snapshot(for: CacheKey(owner: "wallet", network: .mainnet))
        #expect(saved?.holdings.map(\.id) == [.nativeSOL, .asset(DefaultToken.usdt.rawValue)])
    }

    @Test
    func `Adding a listed token changes nothing`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let before = try await fixture.list(for: "wallet")
        let usdc = try #require(before.tokens.first)
        try await service.addToken(usdc, for: "wallet")
        #expect(try await fixture.list(for: "wallet") == before)
    }

    @Test
    func `A list takes fifty added tokens and refuses the fifty-first`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        for index in 1...TokenList.addedTokenLimit {
            try await service.addToken(token(index), for: "wallet")
        }
        let extra = try token(TokenList.addedTokenLimit + 1)
        await #expect(throws: TokenListError.limitReached) { try await service.addToken(extra, for: "wallet") }
        let list = try await fixture.list(for: "wallet")
        #expect(list.tokens.count == TokenList.addedTokenLimit + 2)
    }

    @Test
    func `A removed default token fits again in a full list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let usdc = try #require(try await fixture.list(for: "wallet").tokens.first)
        try await service.removeToken(usdc.mint, for: "wallet")
        for index in 1...TokenList.addedTokenLimit {
            try await service.addToken(token(index), for: "wallet")
        }
        try await service.addToken(usdc, for: "wallet")
        #expect(try await fixture.list(for: "wallet").tokens.last == usdc)
    }

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
        await #expect(throws: TokenListError.unreadable) { try await service.addToken(added, for: "wallet") }
        await #expect(throws: TokenListError.unreadable) { try await service.removeToken(added.mint, for: "wallet") }
        #expect(try files.read(for: key) == saved)
    }

    @Test
    func `Removing an account's data removes its token list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        try await service.addToken(token(1), for: "wallet")
        try await service.removeData(for: "wallet")
        #expect(try KeyedFiles(directory: fixture.directory).read(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
        #expect(try await fixture.list(for: "wallet").tokens.map(\.symbol) == ["USDC", "USDT"])
    }

    @Test
    func `Simultaneous additions all reach the saved list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let tokens = try (1...20).map(token)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for token in tokens {
                group.addTask { try await service.addToken(token, for: "wallet") }
            }
            try await group.waitForAll()
        }
        let saved = try await fixture.list(for: "wallet")
        #expect(Set(saved.tokens.map(\.mint)).isSuperset(of: tokens.map(\.mint)))
        #expect(saved.tokens.count == tokens.count + 2)
    }
}

private struct TokenListFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    var store: FileTokenListStore { FileTokenListStore(directory: directory) }
    var snapshots: FileSnapshotStore { FileSnapshotStore(directory: directory.appendingPathComponent("Snapshots")) }

    func portfolio(network: Network = .mainnet) -> Portfolio {
        Portfolio(rpc: SolanaRPC(network: network), store: snapshots, tokenLists: store)
    }

    func list(for owner: String, network: Network = .mainnet) async throws -> TokenList {
        try await TokenListCoordinator(store: store, network: network).list(for: owner)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

private func token(_ index: Int) throws -> ListedToken {
    let digits = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    let mint = try Address(String(repeating: "1", count: 31) + String(digits[index - 1]))
    return ListedToken(mint: mint, program: .token2022, decimals: 9, symbol: "T\(index)", name: "Token \(index)")
}
