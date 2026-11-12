import Foundation
import Observation
import RPC
import Storage
import Testing
@testable import Portfolio
@testable import widgets

struct PortfolioErrorTests {
    @Test(arguments: [
        (RPCProviderError.missingKey as any Error, PortfolioError.missingKey),
        (RPCProviderError.invalidKey, .invalidKey),
        (RPCProviderError.unsupportedNetwork, .unsupportedNetwork),
        (RPCError.http(statusCode: 401, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 403, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 429, retryAfter: "3"), .rateLimited),
        (RPCError.server(code: 429, message: "Too many requests"), .rateLimited),
        (RPCError.http(statusCode: 500, retryAfter: nil), .unavailable),
        (RPCError.transport(.notConnectedToInternet), .unavailable),
        (KeychainItemError.unreadable, .unavailable),
        (TokenListError.unreadable, .listUnreadable),
    ])
    func `Portfolio errors map to what the person can do`(error: any Error, expected: PortfolioError) {
        #expect(PortfolioError(error) == expected)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [
        (Network.mainnet, RPCSettings.Provider.helius, PortfolioError.missingKey),
        (.devnet, .custom(URL(string: "https://rpc.example.com")!), .unsupportedNetwork),
    ] as [(Network, RPCSettings.Provider, PortfolioError)])
    func `A provider failure reaches the portfolio as a typed failure`(network: Network, provider: RPCSettings.Provider,
                                                                      expected: PortfolioError) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = HTTPResponses.keyCheck().rpcProvider(network: network,
                                                              rpcStore: .inMemory(selection: provider))
        let portfolios = PortfolioStore.serving(Portfolio(
            rpc: client, store: FileSnapshotStore(directory: directory),
            tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists"))))
        let account = try Account.publicWallet()
        let viewing = Task { await portfolios.observe(account, on: network) }
        defer { viewing.cancel() }

        for await error in Observations({ portfolios.portfolio(for: account, on: network)?.error }) {
            if error != nil { break }
        }

        #expect(portfolios.portfolio(for: account, on: network)?.error == expected)
        viewing.cancel()
        await viewing.value
    }

    @Test
    func `Only refresh failures explain stale balances and prices`() {
        let rateLimited = PortfolioError.rateLimited.staleStatus?.key
        let unavailable = PortfolioError.unavailable.staleStatus?.key

        #expect(rateLimited != nil)
        #expect(unavailable != nil)
        #expect(rateLimited != unavailable)
        #expect(PortfolioError.listUnreadable.staleStatus?.key == unavailable)
        #expect([PortfolioError.missingKey, .invalidKey, .unsupportedNetwork].allSatisfy { $0.staleStatus == nil })
    }
}
