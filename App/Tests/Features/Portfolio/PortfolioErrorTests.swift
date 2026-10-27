import Foundation
import Observation
@testable import Portfolio
import RPC
import Storage
import Testing
@testable import widgets

/// Checks that portfolio errors are classified by what the person can do about them.
struct PortfolioErrorTests {
    /// Each error maps to the error the app presents. Only Helius's own key failures ask for a new key, and only the
    /// selected provider's network failure asks for another provider; an HTTP rejection from another provider, such as
    /// prices, counts as unavailable. A rate limit over HTTP or in a subscription reply asks the person to wait.
    /// - Parameters:
    ///   - error: An error a portfolio update can report.
    ///   - expected: The error the app presents.
    @Test(arguments: [
        (ProviderClientError.missingKey as any Error, PortfolioError.missingKey),
        (ProviderClientError.invalidKey, .invalidKey),
        (ProviderClientError.unsupportedNetwork, .unsupportedNetwork),
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

    /// A provider failure from the subscription setup reaches the presentation unchanged: a missing key on mainnet,
    /// or a custom RPC on devnet.
    /// - Parameters:
    ///   - network: The portfolio's network.
    ///   - provider: The selected provider, which can't serve that network as saved.
    ///   - expected: The error the portfolio presents.
    /// - Throws: A fixture error.
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: [
        (Network.mainnet, ProviderSettings.Provider.helius, PortfolioError.missingKey),
        (.devnet, .custom(URL(string: "https://rpc.example.com")!), .unsupportedNetwork),
    ] as [(Network, ProviderSettings.Provider, PortfolioError)])
    func `A provider failure reaches the portfolio as a typed failure`(network: Network, provider: ProviderSettings.Provider,
                                                                      expected: PortfolioError) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = HTTPResponses.keyCheck().providerClient(network: network,
                                                              providers: .inMemory(selection: provider))
        let coordinator = PortfolioCoordinator(store: .serving(Portfolio(
            rpc: client, store: FileSnapshotStore(directory: directory),
            tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")))), network: network)
        let account = try Account.publicWallet()
        let viewing = Task { await coordinator.observe(for: account, isActive: true) }
        defer { viewing.cancel() }

        for await error in Observations({ coordinator.error }) {
            if error != nil { break }
        }

        #expect(coordinator.error == expected)
        viewing.cancel()
        await viewing.value
    }

    /// Refresh failures say why the shown balances may be out of date, with a rate limit told apart from the other
    /// refresh failures; key and network failures hide the balances instead.
    @Test
    func `Only refresh failures explain stale balances`() {
        let rateLimited = PortfolioError.rateLimited.staleStatus?.key
        let unavailable = PortfolioError.unavailable.staleStatus?.key

        #expect(rateLimited != nil)
        #expect(unavailable != nil)
        #expect(rateLimited != unavailable)
        #expect(PortfolioError.listUnreadable.staleStatus?.key == unavailable)
        #expect([PortfolioError.missingKey, .invalidKey, .unsupportedNetwork].allSatisfy { $0.staleStatus == nil })
    }
}
