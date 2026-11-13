import Attestation
import Foundation

/// A client that reads a Solana Rings indexer and proves transfers with its prover at an endpoint.
public struct Zolana: PrivateNoteProviding {
    /// The client for the Solana Rings indexer and prover.
    let client: HTTPClient

    /// The prover's HPKE key, attested under the network's policy.
    let attestedKey: AttestedProverKey

    /// Creates a client for an endpoint that serves a network's Solana Rings indexer and prover. Every request keeps
    /// the endpoint's path and query.
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
        verify: @escaping AttestedProverKey.Verification = AttestedProverKey.verification
    ) {
        client = HTTPClient(endpoint: endpoint, transport: transport, redactor: redactor)
        let policy: NitroPolicy = switch network {
        case .mainnet: .mainnet
        case .devnet: .devnet
        }
        attestedKey = AttestedProverKey(prover: client, policy: policy, nonce: nonce, now: now, verify: verify)
    }
}
