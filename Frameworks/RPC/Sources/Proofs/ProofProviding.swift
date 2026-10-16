/// A provider that proves Solana Rings default-ring transfers.
///
/// The request carries the transfer's witness, including the owner's nullifier secret, which lets the
/// prover link the owner's spends but not spend. Requests are single-attempt.
public protocol ProofProviding: Sendable {
    /// Proves a confidential transfer, reading its Merkle data on the prover's side.
    ///
    /// - Parameter request: The transfer's lookups, public inputs, and witness.
    /// - Returns: The proof, the proving key's digest, and the roots that the prover resolved.
    /// - Throws: A request, transport, response, or cancellation error.
    func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof
}
