public import RPC

extension ShieldedPool {
    /// Reads the fee that a transact pays a tree for each input slot that spends from it.
    ///
    /// - Parameters:
    ///   - treeID: The tree's ID.
    ///   - rpc: The client of the network whose tree to read.
    /// - Returns: The fee per nullifier, in lamports.
    /// - Throws: An RPC error, a ``ValidationError`` if the tree's derivation fails,
    ///   ``TreeError/mismatchedResponse`` if the provider returns another
    ///   number of accounts, ``TreeError/missingTree`` without an account,
    ///   ``TreeError/foreignOwner`` if the program doesn't own it, or ``TreeError/invalidLength``
    ///   if it isn't a tree account's length.
    @concurrent
    public static func feePerNullifier(treeID: UInt16, using rpc: some RPC) async throws -> UInt64 {
        let data = try await treeAccountData(at: [try tree(id: treeID)], using: rpc)[0]
        return data.littleEndian(at: TreeAccount.feePerNullifierOffset)
    }
}
