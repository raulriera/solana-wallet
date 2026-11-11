public import RPC

extension ShieldedPool {
    /// Reads the fee that a transact pays the trees it writes, each once.
    ///
    /// - Parameters:
    ///   - treeIDs: The IDs of one through 100 trees.
    ///   - rpc: The client of the network whose trees to read.
    /// - Returns: The sum of the trees' fees, in lamports.
    /// - Throws: An error from ``RPC/RPC/accounts(at:minContextSlot:)``, a ``ValidationError`` if a tree's derivation
    ///   fails, ``TreeError/missingTree`` without an account, ``TreeError/foreignOwner`` if the program doesn't own
    ///   one, ``TreeError/invalidLength`` if one isn't a tree account's length, or ``TreeError/invalidFee`` if one's
    ///   fee exceeds the program's cap.
    @concurrent
    public static func treeFee(of treeIDs: Set<UInt16>, using rpc: some RPC) async throws -> UInt64 {
        let accounts = try await treeAccountData(at: try treeIDs.map { try tree(id: $0) }, using: rpc)
        return try accounts.reduce(0) { total, account in
            let fee: UInt64 = account.littleEndian(at: TreeAccount.feePerTreeOffset)
            guard fee <= TreeAccount.maximumFeePerTree else { throw TreeError.invalidFee }
            return total + fee
        }
    }
}
