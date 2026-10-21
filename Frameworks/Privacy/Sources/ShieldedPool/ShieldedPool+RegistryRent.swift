public import RPC

extension ShieldedPool {
    /// Reads the rent-exempt balance of a user-registry record with one finalized
    /// `getMinimumBalanceForRentExemption` read of its 134 bytes.
    ///
    /// Registration moves this balance, less the lamports that the record's address already holds,
    /// from the payer to the record; ``ShieldedAccount/registrationCost(using:)`` subtracts them.
    ///
    /// - Parameter rpc: The client of the network whose rent to read.
    /// - Returns: The record's rent-exempt balance, in lamports.
    /// - Throws: An RPC error.
    @concurrent
    public static func registryRecordRent(using rpc: some RPC) async throws -> UInt64 {
        try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: UInt64(UserRegistry.recordLength)))
    }
}
