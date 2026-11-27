import Foundation
import RPC

nonisolated extension TransactionOutcome {
    /// The transaction's page on Solana Explorer.
    var explorerURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "explorer.solana.com"
        components.path = "/tx/\(signature)"
        switch network {
        case .mainnet: break
        case .devnet: components.queryItems = [URLQueryItem(name: "cluster", value: "devnet")]
        }
        // swift-format-ignore: NeverForceUnwrap
        return components.url!
    }
}
