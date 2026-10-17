extension HeliusRPC: ProofProviding {
    /// Proves a transfer with Helius's Solana Rings prover on its complete route, waiting for the proof.
    ///
    /// The request posts the whole witness as JSON to `prove` below the gateway, the only proving route that the
    /// gateway serves, with `X-Sync: true`, so the response carries the proof; it isn't queued or polled.
    /// - Parameter request: The transfer's tree slots, public input hash, and witness.
    /// - Returns: The decoded proof, unchecked.
    /// - Throws: `RPCError.http(statusCode:retryAfter:)` for a refusal, such as a rate limit, a proof timeout, or a
    ///   witness that the circuit rejects, another `RPCError`, or `CancellationError`.
    @concurrent
    public func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof {
        try await gateway.post(TransferProofBody(request), at: "prove", headers: ["X-Sync": "true"],
                               decoding: TransferProofResponse.self).proof
    }
}
