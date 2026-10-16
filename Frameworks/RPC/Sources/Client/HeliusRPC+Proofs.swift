extension HeliusRPC: ProofProviding {
    /// Proves a transfer with Helius's Solana Rings prover on its indexed route, waiting for the proof.
    ///
    /// The request posts JSON to `prove/transfer_confidential_{inputs}_{outputs}/indexed` below the gateway,
    /// with `X-Sync: true`, so the response carries the proof; it isn't queued or polled.
    /// - Parameter request: The transfer's lookups, public inputs, and witness.
    /// - Returns: The decoded proof and resolution, unchecked.
    /// - Throws: `RPCError.http(statusCode:retryAfter:)` for a refusal, such as a rate limit or a proof
    ///   timeout, another `RPCError`, or `CancellationError`.
    @concurrent
    public func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof {
        try await gateway.post(
            TransferProofBody(request),
            at: "prove/transfer_confidential_\(request.inputCount)_\(request.outputCount)/indexed",
            headers: ["X-Sync": "true"],
            decoding: TransferProofResponse.self
        ).proof
    }
}
