extension HeliusRPC: ProofProviding {
    @concurrent
    public func proveTransfer(_ request: TransferProofRequest) async throws -> TransferProof {
        try await gateway.post(TransferProofBody(request), at: "prove", headers: ["X-Sync": "true"],
                               decoding: TransferProofResponse.self).proof
    }
}
