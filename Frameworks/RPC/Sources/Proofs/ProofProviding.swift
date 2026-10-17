/// A provider that proves Solana Rings default-ring transfers.
///
/// The request carries the transfer's whole witness, including the owner's nullifier secret, which lets the
/// prover link the owner's spends but not spend. Requests are single-attempt.
public protocol ProofProviding: Sendable {
    /// Proves a confidential transfer from its whole witness.
    ///
    /// - Parameter request: The transfer's tree slots, public input hash, and witness.
    /// - Returns: The proof and the proving key's digest.
    /// - Throws: A request, transport, response, or cancellation error.
    func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof
}
