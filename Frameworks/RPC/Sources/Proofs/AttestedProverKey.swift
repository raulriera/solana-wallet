import Attestation
import CryptoKit
import Encoding
import Foundation

/// The Solana Rings prover's HPKE key, attested under a policy and reused for the policy's maximum age.
actor AttestedProverKey {
    /// The longest attestation response body, in bytes, to accept.
    private static let maximumAttestationLength = 65_536

    private let prover: HTTPClient
    private let policy: NitroPolicy
    private let makeNonce: @Sendable () -> [UInt8]
    private let now: @Sendable () -> Date

    /// The latest attestation, running or passed, and the time it started.
    private var attestation: (date: Date, task: Task<Curve25519.KeyAgreement.PublicKey, any Error>)?

    /// Creates an attested key for a prover.
    ///
    /// - Parameters:
    ///   - prover: The client for the prover's host.
    ///   - policy: The deployment the prover must run.
    ///   - nonce: The source of each attestation request's 32-byte nonce.
    ///   - now: The source of the current time.
    init(
        prover: HTTPClient,
        policy: NitroPolicy,
        nonce: @escaping @Sendable () -> [UInt8],
        now: @escaping @Sendable () -> Date
    ) {
        self.prover = prover
        self.policy = policy
        makeNonce = nonce
        self.now = now
    }

    /// Draws a 32-byte nonce from the system's random number generator.
    ///
    /// - Returns: The nonce.
    static func randomNonce() -> [UInt8] {
        (0..<32).map { _ in UInt8.random(in: .min ... .max) }
    }

    /// Returns the key of the attestation that started within the policy's maximum age, or of a new attestation.
    ///
    /// - Returns: The attested HPKE key.
    /// - Throws: ``RPCError/InvalidResponse/untrustedProver`` for an attestation that fails the policy,
    ///   ``RPCError/InvalidResponse/oversized`` for an attestation longer than 64 KiB, another ``RPCError``, or
    ///   `CancellationError` if cancelled.
    func key() async throws -> Curve25519.KeyAgreement.PublicKey {
        let date = now()
        let task: Task<Curve25519.KeyAgreement.PublicKey, any Error>
        if let attestation, date < attestation.date.addingTimeInterval(policy.maximumAge) {
            task = attestation.task
        } else {
            let nonce = makeNonce()
            task = Task { @concurrent [prover, policy] in
                let attestation = try await prover.get(
                    at: "tee/v1/attestation",
                    query: [URLQueryItem(name: "nonce", value: Hex.encode(nonce))],
                    maximumLength: Self.maximumAttestationLength,
                    decoding: ProverAttestation.self
                )
                return try attestation.publicKey(for: nonce, under: policy, at: date)
            }
            attestation = (date, task)
        }
        let result = await task.result
        if case .failure = result, attestation?.task == task { attestation = nil }
        try Task.checkCancellation()
        return try result.get()
    }
}
