import CryptoKit

extension Zolana: ProofProviding {
    /// The longest encrypted proof answer, in bytes, to accept.
    private static let maximumProofLength = 1_048_576

    /// The UTXO root index of a resolved tree that has no state proofs.
    private static let absentUTXORootIndex: UInt16 = 0xFFFF

    /// Proves a default-ring confidential transfer with the network's prover, which reads the inputs' Merkle and
    /// non-inclusion proofs from its indexer.
    ///
    /// - Parameter request: The transfer's trees, inputs with their commitments, witness, and public inputs.
    /// - Returns: The proof, the proving key's digest, and the roots that the prover proved the transfer against.
    /// - Throws: ``RPCError/http(statusCode:retryAfter:)`` for a proof that the prover refuses,
    ///   ``RPCError/InvalidResponse/mismatchedResolution`` for a resolution of other trees or of state roots that
    ///   don't match the inputs, ``RPCError/InvalidResponse/staleProverKey`` when the prover can't decrypt the
    ///   request after a new attestation, another ``RPCError``, or `CancellationError`.
    @concurrent
    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        let body = IndexedTransferProofBody(request)
        let path = "prove/transfer_confidential_\(request.inputs.count)_\(request.outputs.count)/indexed"
        let key = try await attestedKey.key()
        let proof: IndexedTransferProof
        do {
            proof = try await post(body, at: path, to: key)
        } catch RPCError.invalidResponse(.staleProverKey) {
            await attestedKey.forget(key)
            proof = try await post(body, at: path, to: try await attestedKey.key())
        }
        try Self.check(proof.resolution, against: request)
        return proof
    }

    /// Posts a proof request encrypted to the prover's key and decodes its synchronous answer.
    ///
    /// - Parameters:
    ///   - body: The request's body.
    ///   - path: The proving key's indexed route.
    ///   - key: The prover's attested HPKE key.
    /// - Returns: The proof and its resolution.
    /// - Throws: ``RPCError/InvalidResponse/staleProverKey`` when the prover can't decrypt the request, another
    ///   ``RPCError``, or `CancellationError`.
    private func post(
        _ body: IndexedTransferProofBody,
        at path: String,
        to key: Curve25519.KeyAgreement.PublicKey
    ) async throws -> IndexedTransferProof {
        let sealed = try SealedProverRequest(sealing: body, at: path, to: key)
        return try await prover.post(
            sealed.body,
            at: path,
            headers: sealed.headers.merging(["X-Sync": "true"]) { $1 },
            maximumLength: Self.maximumProofLength,
            reading: sealed.open,
            decoding: IndexedTransferProofResponse.self
        ).proof
    }

    /// Checks that a resolution names the request's trees in order, each with a state root, since a real input spends
    /// from every tree of a request.
    ///
    /// - Parameters:
    ///   - resolution: The prover's resolution.
    ///   - request: The request that the prover resolved.
    /// - Throws: ``RPCError/InvalidResponse/mismatchedResolution`` for other trees, another order, or a tree without a
    ///   state root.
    private static func check(_ resolution: ProofResolution, against request: IndexedTransferProofRequest) throws {
        guard resolution.trees.elementsEqual(request.trees, by: { $0.id == $1.id && $0.address == $1.address }),
              resolution.trees.allSatisfy({ $0.utxoRootIndex != absentUTXORootIndex }) else {
            throw RPCError.invalidResponse(.mismatchedResolution)
        }
    }
}
