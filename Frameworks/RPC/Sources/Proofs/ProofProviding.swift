/// A provider that proves default-ring confidential transfers.
public protocol ProofProviding: Sendable {
    /// Proves a confidential transfer from its whole witness.
    ///
    /// - Parameter request: The transfer's tree slots, public input hash, and witness.
    /// - Returns: The proof and the proving key's digest.
    /// - Throws: A request, transport, response, or cancellation error.
    func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof
}
