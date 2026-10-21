@testable import RPC
import Testing
@testable import widgets

/// Checks that each network's transaction coordinator is created for the network's first window and then shared.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkTransactionsTests {
    /// No coordinator exists until a window needs one; each network's coordinator is then created once.
    /// - Throws: A coordinator creation error.
    @Test
    func `Each network's coordinator is created on first use and then reused`() throws {
        var made: [Network] = []
        let transactions = NetworkTransactions { network in
            made.append(network)
            return try Self.coordinator(on: network)
        }
        #expect(made.isEmpty)

        _ = try transactions.coordinator(for: .devnet)
        _ = try transactions.coordinator(for: .devnet)
        _ = try transactions.coordinator(for: .mainnet)

        #expect(made == [.devnet, .mainnet])
    }

    /// A coordinator that couldn't be created isn't kept, so the next request creates it.
    /// - Throws: A coordinator creation error on the second request.
    @Test
    func `A failed creation is tried again on the next request`() throws {
        var attempts = 0
        let transactions = NetworkTransactions { network in
            attempts += 1
            // The first attempt has no route that sends on the network.
            return try Self.coordinator(on: network, routes: attempts == 1 ? [] : nil)
        }

        #expect(throws: SubmitterError.noProviders) { _ = try transactions.coordinator(for: .devnet) }
        _ = try transactions.coordinator(for: .devnet)

        #expect(attempts == 2)
    }

    /// Creates a coordinator whose requests never leave the process.
    /// - Parameters:
    ///   - network: The network that the coordinator sends on.
    ///   - routes: The ordinary RPCs that send approved transactions, or `nil` to use the read client alone.
    /// - Returns: A coordinator that never reads recovery.
    /// - Throws: ``SubmitterError/noProviders`` without a route on the network.
    private static func coordinator(on network: Network, routes: [any RPC]? = nil) throws
        -> any TransactionCoordinating {
        try TransactionCoordinator(rpc: Solana(network: network, transport: HTTPResponses([:])),
                                   store: UnavailableRecoveryStore(), rpcs: routes)
    }
}
