/// A provider that proves default-ring confidential transfers.
public protocol ProofProviding: Sendable {
    /// Proves a confidential transfer with a prover that reads the inputs' Merkle and non-inclusion proofs from its
    /// indexer.
    ///
    /// - Parameter request: The transfer's trees, inputs with their commitments, witness, and public inputs.
    /// - Returns: The proof, the proving key's digest, and the roots that the prover proved the transfer against.
    /// - Throws: A request, transport, response, or cancellation error.
    func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof
}
