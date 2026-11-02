extension Zolana: ProofProviding {
    /// The longest encrypted proof answer, in bytes, to accept.
    private static let maximumProofLength = 1_048_576

    /// Proves a default-ring confidential transfer with the network's prover, which reads the inputs' Merkle and
    /// non-inclusion proofs from its indexer.
    ///
    /// - Parameter request: The transfer's trees, inputs with their commitments, witness, and public inputs.
    /// - Returns: The proof, the proving key's digest, and the roots that the prover proved the transfer against.
    /// - Throws: ``RPCError/http(statusCode:retryAfter:)`` for a proof that the prover refuses, another ``RPCError``,
    ///   or `CancellationError`.
    @concurrent
    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        let path = "prove/transfer_confidential_\(request.inputs.count)_\(request.outputs.count)/indexed"
        let sealed = try SealedProverRequest(
            sealing: IndexedTransferProofBody(request),
            at: path,
            to: try await attestedKey.key()
        )
        return try await prover.post(
            sealed.body,
            at: path,
            headers: sealed.headers.merging(["X-Sync": "true"]) { $1 },
            maximumLength: Self.maximumProofLength,
            reading: sealed.open,
            decoding: IndexedTransferProofResponse.self
        ).proof
    }
}
