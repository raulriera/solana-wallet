import Attestation
import CryptoKit
import Encoding
import Foundation

/// The Solana Rings prover's HPKE key, attested under a policy and reused for the policy's maximum age.
actor AttestedProverKey {
    /// A check that returns the HPKE key that an attestation binds to a nonce under a policy at a time.
    typealias Verification = @Sendable (ProverAttestation, [UInt8], NitroPolicy, Date) throws
        -> Curve25519.KeyAgreement.PublicKey

    /// The longest attestation response body, in bytes, to accept.
    private static let maximumAttestationLength = 65_536

    private let prover: HTTPClient
    private let policy: NitroPolicy
    private let makeNonce: @Sendable () -> [UInt8]
    private let now: @Sendable () -> Date
    private let verify: Verification

    /// The latest attestation, running or passed, and the time it started.
    private var attestation: (date: Date, task: Task<Curve25519.KeyAgreement.PublicKey, any Error>)?

    /// Creates an attested key for a prover.
    ///
    /// - Parameters:
    ///   - prover: The client for the prover's host.
    ///   - policy: The deployment the prover must run.
    ///   - nonce: The source of each attestation request's 32-byte nonce.
    ///   - now: The source of the current time.
    ///   - verify: The check that returns the key an attestation binds to its nonce under the policy.
    init(
        prover: HTTPClient,
        policy: NitroPolicy,
        nonce: @escaping @Sendable () -> [UInt8],
        now: @escaping @Sendable () -> Date,
        verify: @escaping Verification
    ) {
        self.prover = prover
        self.policy = policy
        makeNonce = nonce
        self.now = now
        self.verify = verify
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
            task = Task { @concurrent [prover, policy, verify] in
                let attestation = try await prover.get(
                    at: "tee/v1/attestation",
                    query: [URLQueryItem(name: "nonce", value: Hex.encode(nonce))],
                    maximumLength: Self.maximumAttestationLength,
                    decoding: ProverAttestation.self
                )
                return try verify(attestation, nonce, policy, date)
            }
            attestation = (date, task)
        }
        let result = await task.result
        if case .failure = result, attestation?.task == task { attestation = nil }
        try Task.checkCancellation()
        return try result.get()
    }

    /// Drops the latest attestation once it finishes if its key is the given key, even an attestation that started
    /// later and returned the same key, so the next caller attests again.
    ///
    /// - Parameter key: The key of a request that the prover couldn't decrypt.
    func forget(_ key: Curve25519.KeyAgreement.PublicKey) async {
        guard let task = attestation?.task, case .success(let attested) = await task.result,
            attestation?.task == task, attested.rawRepresentation == key.rawRepresentation
        else { return }
        attestation = nil
    }
}
