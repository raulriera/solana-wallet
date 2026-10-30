import Foundation
@testable import widgets

extension ProvidersCoordinator {
    static func inMemory(_ providers: ProviderStore) -> ProvidersCoordinator {
        let connection = HTTPResponses.keyCheck().connection(providers: providers)
        let customRPCConnection = CustomRPCConnection(providers: providers) { HTTPResponses([:]).client(for: $0, on: $1) }
        return ProvidersCoordinator(providers: providers, connection: connection,
                                    customRPCConnection: customRPCConnection)
    }
}
