import Foundation
@testable import widgets

extension ProvidersCoordinator {
    /// Creates a coordinator around the production selection, key connection, and custom RPC check over in-memory
    /// stores.
    /// - Parameters:
    ///   - settings: The saved provider choice and custom RPCs.
    ///   - providerKey: Helius's saved key, which key entry fills, the selection reads, and the coordinator previews.
    ///   - revision: Counts provider changes that every window hears about.
    /// - Returns: A coordinator that never leaves the process.
    static func inMemory(settings: StoredValue<ProviderSettings>, providerKey: StoredValue<String>,
                         revision: Revision = Revision()) -> ProvidersCoordinator {
        let providers = ProviderSelection(settings: settings, providerKey: providerKey, portfolio: ProviderChanges(),
                                          revision: revision)
        let connection = HTTPResponses.keyCheck().connection(providerKey: providerKey, revision: revision)
        // Unplanned requests fail instead of reaching the network.
        let customRPCConnection = CustomRPCConnection(providers: providers) { HTTPResponses([:]).client(for: $0) }
        return ProvidersCoordinator(providers: providers, providerKey: providerKey, connection: connection,
                                    customRPCConnection: customRPCConnection, revision: revision)
    }
}
