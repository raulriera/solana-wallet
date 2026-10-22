import Foundation
import RPC

nonisolated extension Submission {
    /// The sent transaction's page on Solana Explorer, on its own network, where anyone can check its outcome.
    var explorerURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "explorer.solana.com"
        components.path = "/tx/\(signature)"
        switch network {
        case .mainnet: break
        case .devnet: components.queryItems = [URLQueryItem(name: "cluster", value: "devnet")]
        }
        // A base-58 signature has only letters and digits, so the components always form a URL.
        return components.url!
    }
}
