import Attestation
import CryptoKit
import Encoding
import Foundation

/// The Solana Rings prover's AWS Nitro attestation: the key that requests are encrypted to and its evidence.
struct ProverAttestation: Decodable, Sendable {
    /// The `evidence` field of an attestation.
    struct Evidence: Decodable, Sendable {
        /// The lowercase hexadecimal attestation document.
        let document: String
    }

    /// The lowercase hexadecimal HPKE key that requests are encrypted to.
    let hpkePublicKey: String

    let evidence: Evidence

    private enum CodingKeys: String, CodingKey {
        case platform
        case hpkePublicKey = "hpke_public_key"
        case gpu
        case evidence
    }

    /// Decodes an attestation from a platform without a GPU.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: ``RPCError/InvalidResponse/untrustedProver`` for a platform other than `aws-nitro` or a missing or
    ///   non-null `gpu`, or a decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .platform) == "aws-nitro", container.contains(.gpu),
            try container.decodeNil(forKey: .gpu)
        else { throw RPCError.invalidResponse(.untrustedProver) }
        hpkePublicKey = try container.decode(String.self, forKey: .hpkePublicKey)
        evidence = try container.decode(Evidence.self, forKey: .evidence)
    }

    /// Verifies the attestation and returns the HPKE key it binds to a nonce under a policy.
    ///
    /// - Parameters:
    ///   - nonce: The 32-byte nonce sent with the attestation request.
    ///   - policy: The deployment the prover must run.
    ///   - date: The time the evidence's certificates must be valid at.
    /// - Returns: The attested HPKE key.
    /// - Throws: ``RPCError/InvalidResponse/untrustedProver`` for a field that isn't lowercase hexadecimal or
    ///   evidence that fails the policy.
    func publicKey(for nonce: [UInt8], under policy: NitroPolicy, at date: Date) throws
        -> Curve25519.KeyAgreement.PublicKey {
        guard let key = Hex.decode(hpkePublicKey), let document = Hex.decode(evidence.document) else {
            throw RPCError.invalidResponse(.untrustedProver)
        }
        do {
            return try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: key,
                attestedBy: document,
                nonce: nonce,
                policy: policy,
                at: date
            )
        } catch {
            throw RPCError.invalidResponse(.untrustedProver)
        }
    }
}
