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
        #expect(mainnet.mints.map(\.address.value) == ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                                                     "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"])
        #expect(mainnet.mints.map(\.metadata?.symbol) == ["USDC", "USDT"])
        #expect(mainnet.mints.map(\.metadata?.name) == ["USD Coin", "Tether USD"])
        #expect(mainnet.mints.allSatisfy { $0.program == .token && $0.decimals == 6 })
        #expect(devnet.mints.isEmpty)
    }

    @Test
    func `Added and removed tokens are saved in order`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let added = try mint(1)
        try await service.addToken(added, for: "wallet")
        let usdc = try #require(try await fixture.list(for: "wallet").mints.first)
        try await service.removeToken(usdc.address, for: "wallet")
        let restored = try await fixture.list(for: "wallet")
        #expect(restored.mints.map(\.metadata?.symbol) == ["USDT", "T1"])
        #expect(restored.mints.last == added)
    }

    @Test
    func `A removed token leaves the cached holdings`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let mints = try await fixture.list(for: "wallet").mints
        let holdings = [Holding(asset: .nativeSOL, balance: TokenAmount(amount: 1, decimals: 9),
                                imageURL: nil, valuation: nil)]
            + mints.map { Holding(asset: .token($0), balance: TokenAmount(amount: 1, decimals: $0.decimals),
                                   imageURL: nil, valuation: nil) }
        try fixture.snapshots.save(Snapshot(owner: "wallet", network: .mainnet, holdings: holdings),
                                   for: CacheKey(owner: "wallet", network: .mainnet))
        let usdc = try #require(mints.first)

        try await service.removeToken(usdc.address, for: "wallet")

        let saved = fixture.snapshots.snapshot(for: CacheKey(owner: "wallet", network: .mainnet))
        #expect(try saved?.holdings.map(\.id) == [.nativeSOL, .token(mint: Address(usdtMint))])
    }

    @Test
    func `A mint decoded from its account is saved with its facts`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let facts = try mint(1)
        let account = [UInt8](repeating: 0, count: 36) + [232, 3, 0, 0, 0, 0, 0, 0, 9, 1]
            + [UInt8](repeating: 0, count: 36)
        var decoded = try Mint(address: facts.address, owner: Address(TokenProgram.token2022.rawValue),
                               data: Data(account))
        decoded.metadata = facts.metadata

        try await fixture.portfolio().addToken(decoded, for: "wallet")

        #expect(try await fixture.list(for: "wallet").mints.last == facts)
    }

    @Test
    func `Adding a listed token changes nothing`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let before = try await fixture.list(for: "wallet")
        let usdc = try #require(before.mints.first)
        try await service.addToken(usdc, for: "wallet")
        #expect(try await fixture.list(for: "wallet") == before)
    }

    @Test
    func `A change that alters nothing saves no list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let usdc = try #require(try await fixture.list(for: "wallet").mints.first)
        try await service.addToken(usdc, for: "wallet")
        try await service.removeToken(try mint(1).address, for: "wallet")
        #expect(try fixture.store.tokenList(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
    }

    @Test
    func `A list holds fifty tokens with native SOL and refuses another`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        for index in 1...(TokenList.tokenLimit - 3) {
            try await service.addToken(mint(index), for: "wallet")
        }
        let extra = try mint(TokenList.tokenLimit - 2)
        await #expect(throws: TokenListError.limitReached) { try await service.addToken(extra, for: "wallet") }
        let list = try await fixture.list(for: "wallet")
        #expect(list.mints.count + 1 == TokenList.tokenLimit)
    }

    @Test
    func `A removed default token frees a place for another`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let usdc = try #require(try await fixture.list(for: "wallet").mints.first)
        try await service.removeToken(usdc.address, for: "wallet")
        for index in 1...(TokenList.tokenLimit - 2) {
            try await service.addToken(mint(index), for: "wallet")
        }
        await #expect(throws: TokenListError.limitReached) { try await service.addToken(usdc, for: "wallet") }
        #expect(try await fixture.list(for: "wallet").mints.last == mint(TokenList.tokenLimit - 2))
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
        let added = try mint(1)
        await #expect(throws: TokenListError.unreadable) { try await service.addToken(added, for: "wallet") }
        await #expect(throws: TokenListError.unreadable) { try await service.removeToken(added.address, for: "wallet") }
        #expect(try files.read(for: key) == saved)
    }

    @Test
    func `Removing an account's data removes its token list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        try await service.addToken(mint(1), for: "wallet")
        try await service.removeData(for: "wallet")
        #expect(try KeyedFiles(directory: fixture.directory).read(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
        #expect(try await fixture.list(for: "wallet").mints.map(\.metadata?.symbol) == ["USDC", "USDT"])
    }

    @Test
    func `Simultaneous additions all reach the saved list`() async throws {
        let fixture = TokenListFixture()
        defer { fixture.removeFiles() }
        let service = fixture.portfolio()
        let mints = try (1...20).map(mint)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for added in mints {
                group.addTask { try await service.addToken(added, for: "wallet") }
            }
            try await group.waitForAll()
        }
        let saved = try await fixture.list(for: "wallet")
        #expect(Set(saved.mints.map(\.address)).isSuperset(of: mints.map(\.address)))
        #expect(saved.mints.count == mints.count + 2)
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

private func mint(_ index: Int) throws -> Mint {
    let digits = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    let address = try Address(String(repeating: "1", count: 31) + String(digits[index - 1]))
    return Mint(address: address, program: .token2022, decimals: 9,
                metadata: TokenMetadata(name: "Token \(index)", symbol: "T\(index)"))
}
