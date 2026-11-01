extension HeliusRPC: ProofProviding {
    public func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        try await zolana.proveTransfer(request)
    }
}
