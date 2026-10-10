import Foundation
import Observation
@testable import Portfolio
import RPC
import Testing
@testable import widgets

/// Checks that portfolio errors are classified by what the person can do about them.
struct PortfolioErrorTests {
    /// Each error maps to the error the app presents. Only Helius's own key failures ask for a new key;
    /// an HTTP rejection from another provider, such as prices, counts as unavailable.
    /// - Parameters:
    ///   - error: An error a portfolio update can report.
    ///   - expected: The error the app presents.
    @Test(arguments: [
        (ProviderClientError.missingKey as any Error, PortfolioError.missingKey),
        (ProviderClientError.invalidKey, .invalidKey),
        (RPCError.http(statusCode: 401, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 403, retryAfter: nil), .unavailable),
        (RPCError.http(statusCode: 429, retryAfter: "3"), .rateLimited),
        (RPCError.http(statusCode: 500, retryAfter: nil), .unavailable),
        (RPCError.transport(.notConnectedToInternet), .unavailable),
        (ObservationError.networkMismatch, .unavailable),
        (KeychainItemError.unreadable, .unavailable),
        (TokenListError.unreadable, .listUnreadable),
    ])
    func `Portfolio errors map to what the person can do`(error: any Error, expected: PortfolioError) {
        #expect(PortfolioError(error) == expected)
    }

    /// Only key failures send the person to provider setup.
    /// - Parameters:
    ///   - error: A presented error.
    ///   - requiresSetup: Whether entering a new key is the way forward.
    @Test(arguments: [
        (PortfolioError.missingKey, true),
        (.invalidKey, true),
        (.rateLimited, false),
        (.unavailable, false),
        (.listUnreadable, false),
    ])
    func `Only key failures ask for provider setup`(error: PortfolioError, requiresSetup: Bool) {
        #expect(error.requiresProviderSetup == requiresSetup)
    }

    /// The missing-key error from the subscription setup reaches the presentation unchanged.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func `A missing key reaches the portfolio as a typed failure`() async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = HTTPResponses.keyCheck().providerClient(settings: StoredValue<ProviderSettings>(), providerKey: StoredValue<String>())
        let coordinator = PortfolioCoordinator(service: Portfolio(rpc: client, store: FileSnapshotStore(directory: directory)))
        let viewing = Task { await coordinator.observe(for: PublicWallet.address, isActive: true) }
        defer { viewing.cancel() }

        for await error in Observations({ coordinator.error }) {
            if error != nil { break }
        }

        #expect(coordinator.error == .missingKey)
        viewing.cancel()
        await viewing.value
    }

    /// Refresh failures say why the shown balances may be out of date; key failures hide the balances instead.
    /// - Parameters:
    ///   - error: A presented error.
    ///   - status: The subtitle that the portfolio shows above stale balances.
    @Test(arguments: [
        (PortfolioError.rateLimited, "Too many requests" as String?),
        (.unavailable, "Couldn't update balances"),
        (.listUnreadable, "Couldn't update balances"),
        (.missingKey, nil),
        (.invalidKey, nil),
    ])
    func `Only refresh failures explain stale balances`(error: PortfolioError, status: String?) {
        #expect(error.staleStatus.map { String(localized: $0) } == status)
    }
}
