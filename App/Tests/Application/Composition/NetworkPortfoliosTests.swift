import Foundation
import Observation
@testable import Portfolio
@testable import RPC
import Testing
@testable import widgets

/// Checks that each network's portfolio service is created for the network's first window and then shared, and that
/// only the network that the price provider quotes values holdings.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkPortfoliosTests {
    /// Only mainnet's service exists until a window shows devnet; devnet's service is then created once.
    @Test
    func `Devnet's service is created for its first window and then reused`() {
        var made: [Network] = []
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:]))) { network, _ in
            made.append(network)
            return ProviderChanges()
        }
        #expect(made == [.mainnet])
        #expect(portfolios.created.count == 1)

        _ = portfolios.makeCoordinator(for: .devnet)
        _ = portfolios.makeCoordinator(for: .devnet)
        _ = portfolios.makeCoordinator(for: .mainnet)

        #expect(made == [.mainnet, .devnet])
        #expect(portfolios.created.count == 2)
    }

    /// Mainnet's service gets the price provider, which quotes mainnet; devnet's service gets none.
    @Test
    func `Only mainnet's service gets the price provider`() {
        var priced: [Network: Bool] = [:]
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: HTTPResponses([:]))) { network, prices in
            priced[network] = prices is Jupiter
            return ProviderChanges()
        }

        _ = portfolios.makeCoordinator(for: .devnet)

        #expect(priced == [.mainnet: true, .devnet: false])
    }

    /// A devnet window reads balances at the selected provider's devnet host, starting with SOL alone, and shows
    /// amounts without value because the price provider quotes mainnet.
    /// - Throws: A portfolio failure or a test prerequisite error.
    @Test
    func `A devnet window reads devnet balances without value`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responses = HTTPResponses(["getMultipleAccounts": [#"{"context":{"slot":1},"value":[null]}"#]])
        let portfolios = NetworkPortfolios(prices: Jupiter(transport: responses)) { network, prices in
            Portfolio(rpc: responses.providerClient(network: network, settings: StoredValue<ProviderSettings>(),
                                                    providerKey: StoredValue<String>()),
                      store: FileSnapshotStore(directory: directory),
                      tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")),
                      prices: prices)
        }
        let coordinator = portfolios.makeCoordinator(for: .devnet)
        let viewing = Task { await coordinator.observe(for: PublicWallet.address, isActive: true) }
        defer { viewing.cancel() }

        for await update in Observations({ coordinator.update }) {
            if let error = update?.error { throw error }
            if update?.isRefreshing == false, update?.snapshot != nil { break }
        }

        #expect(coordinator.update?.snapshot?.network == .devnet)
        #expect(coordinator.holdings.map(\.symbol) == ["SOL"])
        #expect(coordinator.holdings.allSatisfy { $0.valuation == nil })
        #expect(await responses.requests.map { $0.url?.host() } == ["api.devnet.solana.com"])
        viewing.cancel()
        await viewing.value
    }
}
