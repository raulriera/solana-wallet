import Attestation
public import Foundation

/// A client that reads the Solana Rings indexer and proves transfers with its prover on a selected Solana network.
public struct Zolana: PrivateNoteProviding {
    /// The client for the Solana Rings indexer.
    let indexer: HTTPClient

    /// The client for the Solana Rings prover.
    let prover: HTTPClient

    /// The prover's HPKE key, attested under the network's policy.
    let attestedKey: AttestedProverKey

    /// Creates a client for the selected network.
    ///
    /// - Parameter network: The Solana network to query.
    public init(network: Network) {
        self.init(network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport, source of attestation nonces, clock, and attestation check.
    ///
    /// - Parameters:
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - nonce: The source of each prover attestation request's 32-byte nonce.
    ///   - now: The source of the current time.
    ///   - verify: The check that returns the key a prover attestation binds to its nonce under the network's policy.
    init(
        network: Network,
        transport: any HTTPTransport,
        nonce: @escaping @Sendable () -> [UInt8] = AttestedProverKey.randomNonce,
        now: @escaping @Sendable () -> Date = { .now },
        verify: @escaping AttestedProverKey.Verification = { try $0.publicKey(for: $1, under: $2, at: $3) }
    ) {
        let (indexerHost, proverHost, policy): (String, String, NitroPolicy) =
            switch network {
            case .mainnet: ("dgcj4pjarvo65.cloudfront.net", "d3ky2kt0ntqxt1.cloudfront.net", .mainnet)
            case .devnet: ("d34xe1hqb2ibg2.cloudfront.net", "dd73hh473h6ha.cloudfront.net", .devnet)
            }
        indexer = Self.client(host: indexerHost, transport: transport)
        prover = Self.client(host: proverHost, transport: transport)
        attestedKey = AttestedProverKey(prover: prover, policy: policy, nonce: nonce, now: now, verify: verify)
    }

    /// Creates a client for an endpoint that serves a network's Solana Rings indexer and prover, or `nil` unless the
    /// endpoint uses HTTPS and has a host.
    ///
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host, whose path and query every request keeps.
    ///   - network: The network that the endpoint serves.
    public init?(endpoint: URL, network: Network) {
        guard let endpoint = endpoint.httpsEndpoint else { return nil }
        self.init(network: network, endpoint: endpoint, redactor: SecretRedactor(urls: [endpoint]),
                  transport: URLSessionTransport())
    }

    /// Creates a client for an endpoint with an injected transport, source of attestation nonces, clock, and
    /// attestation check.
    ///
    /// - Parameters:
    ///   - network: The network that the endpoint serves.
    ///   - endpoint: The HTTPS endpoint of the indexer and prover.
    ///   - redactor: The redactor that removes secrets from diagnostics.
    ///   - transport: The transport that performs HTTP requests.
    ///   - nonce: The source of each prover attestation request's 32-byte nonce.
    ///   - now: The source of the current time.
    ///   - verify: The check that returns the key a prover attestation binds to its nonce under the network's policy.
    init(
        network: Network,
        endpoint: URL,
        redactor: SecretRedactor,
        transport: any HTTPTransport,
        nonce: @escaping @Sendable () -> [UInt8] = AttestedProverKey.randomNonce,
        now: @escaping @Sendable () -> Date = { .now },
        verify: @escaping AttestedProverKey.Verification = { try $0.publicKey(for: $1, under: $2, at: $3) }
    ) {
        let client = HTTPClient(endpoint: endpoint, transport: transport, redactor: redactor)
        let policy: NitroPolicy = switch network {
        case .mainnet: .mainnet
        case .devnet: .devnet
        }
        indexer = client
        prover = client
        attestedKey = AttestedProverKey(prover: client, policy: policy, nonce: nonce, now: now, verify: verify)
    }

    /// Creates a keyless client for an HTTPS host.
    ///
    /// - Parameters:
    ///   - host: The host's name.
    ///   - transport: The transport that performs HTTP requests.
    /// - Returns: The client.
    private static func client(host: String, transport: any HTTPTransport) -> HTTPClient {
        // swift-format-ignore: NeverForceUnwrap
        HTTPClient(
            endpoint: URL(string: "https://\(host)")!,
            transport: transport,
            redactor: SecretRedactor(secrets: [])
        )
    }
}
