import Attestation
import Foundation

/// A client that reads the Solana Rings indexer on a selected Solana network without an API key.
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

    /// Creates a client with an injected transport, source of attestation nonces, and clock.
    ///
    /// - Parameters:
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - nonce: The source of each prover attestation request's 32-byte nonce.
    ///   - now: The source of the current time.
    init(
        network: Network,
        transport: any HTTPTransport,
        nonce: @escaping @Sendable () -> [UInt8] = AttestedProverKey.randomNonce,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let (indexerHost, proverHost, policy): (String, String, NitroPolicy) =
            switch network {
            case .mainnet: ("dgcj4pjarvo65.cloudfront.net", "d3ky2kt0ntqxt1.cloudfront.net", .mainnet)
            case .devnet: ("d34xe1hqb2ibg2.cloudfront.net", "dd73hh473h6ha.cloudfront.net", .devnet)
            }
        indexer = Self.client(host: indexerHost, transport: transport)
        prover = Self.client(host: proverHost, transport: transport)
        attestedKey = AttestedProverKey(prover: prover, policy: policy, nonce: nonce, now: now)
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
