import Foundation
import Observation
@testable import Portfolio
import RPC
import Testing
@testable import widgets

/// Checks that portfolio errors are classified by what the person can do about them.
struct PortfolioFailureTests {
    /// Each error maps to the failure the app presents. Only Helius's own key failures ask for a new key;
    /// an HTTP rejection from another provider, such as prices, counts as unavailable.
    /// - Parameters:
    ///   - error: An error a portfolio update can report.
    ///   - expected: The failure the app presents.
    @Test(arguments: [
        (HeliusClient.Failure.missingKey as any Error, PortfolioFailure.missingKey),
        (HeliusClient.Failure.invalidKey, .invalidKey),
        (RPCError.http(statusCode: 401, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 403, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 429, retryAfter: "3"), .rateLimited),
        (RPCError.http(statusCode: 500, retryAfter: nil), .unavailable),
        (RPCError.transport(.notConnectedToInternet), .unavailable),
        (ObservationError.indexingBehind(expected: 2, observed: 1), .unavailable),
        (ProviderKeyStore.Failure.unreadable, .unavailable),
    ])
    func `Portfolio errors map to what the person can do`(error: any Error, expected: PortfolioFailure) {
        #expect(PortfolioFailure(error) == expected)
    }

    /// Only key failures send the person to provider setup.
    /// - Parameters:
    ///   - failure: A presented failure.
    ///   - requiresSetup: Whether entering a new key is the way forward.
    @Test(arguments: [
        (PortfolioFailure.missingKey, true),
        (.invalidKey, true),
        (.rateLimited, false),
        (.unavailable, false),
    ])
    func `Only key failures ask for provider setup`(failure: PortfolioFailure, requiresSetup: Bool) {
        #expect(failure.requiresProviderSetup == requiresSetup)
    }

    /// The missing-key error from the subscription setup reaches the presentation unchanged.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `A missing key reaches the portfolio as a typed failure`() async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = HTTPResponses.keyCheck().heliusClient(keys: SavedKeys())
        let coordinator = PortfolioCoordinator(service: Portfolio(rpc: client, store: FileSnapshotStore(directory: directory)))
        let viewing = Task { await coordinator.observe(for: PublicWallet.address, isActive: true) }
        defer { viewing.cancel() }

        for await failure in Observations({ coordinator.failure }) {
            if failure != nil { break }
        }

        #expect(coordinator.failure == .missingKey)
        viewing.cancel()
        await viewing.value
    }

    /// Refresh failures say why the shown balances may be out of date; key failures hide the balances instead.
    /// - Parameters:
    ///   - failure: A presented failure.
    ///   - status: The subtitle that the portfolio shows above stale balances.
    @Test(arguments: [
        (PortfolioFailure.rateLimited, "Too many requests" as String?),
        (.unavailable, "Couldn't update balances"),
        (.missingKey, nil),
        (.invalidKey, nil),
    ])
    func `Only refresh failures explain stale balances`(failure: PortfolioFailure, status: String?) {
        #expect(failure.staleStatus.map { String(localized: $0) } == status)
    }
}
