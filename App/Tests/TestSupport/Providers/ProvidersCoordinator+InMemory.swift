import Foundation
@testable import widgets

extension ProvidersCoordinator {
    /// Creates a coordinator around the production key connection and custom RPC check over the shared settings.
    /// - Parameter providers: The provider choice, custom RPCs, and key that key entry fills and the coordinator
    ///   changes.
    /// - Returns: A coordinator that never leaves the process.
    static func inMemory(_ providers: ProviderStore) -> ProvidersCoordinator {
        let connection = HTTPResponses.keyCheck().connection(providers: providers)
        // Unplanned requests fail instead of reaching the network.
        let customRPCConnection = CustomRPCConnection(providers: providers) { HTTPResponses([:]).client(for: $0, on: $1) }
        return ProvidersCoordinator(providers: providers, connection: connection,
                                    customRPCConnection: customRPCConnection)
    }
}
