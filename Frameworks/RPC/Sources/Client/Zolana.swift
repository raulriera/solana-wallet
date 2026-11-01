import Foundation

/// A client that reads the Solana Rings indexer on a selected Solana network without an API key.
public struct Zolana: PrivateNoteProviding {
    /// The client for the Solana Rings indexer.
    let indexer: HTTPClient

    /// Creates a client for the selected network.
    ///
    /// - Parameter network: The Solana network to query.
    public init(network: Network) {
        self.init(network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport.
    ///
    /// - Parameters:
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    init(network: Network, transport: any HTTPTransport) {
        let host = switch network {
        case .mainnet: "dgcj4pjarvo65.cloudfront.net"
        case .devnet: "d34xe1hqb2ibg2.cloudfront.net"
        }
        // swift-format-ignore: NeverForceUnwrap
        indexer = HTTPClient(endpoint: URL(string: "https://\(host)")!, transport: transport,
                             redactor: SecretRedactor(secrets: []))
    }
}
