public import RPC
import Transactions

extension ShieldedAccount {
    /// Reads the lamports that the account's registration moves from its payer.
    ///
    /// - Parameter rpc: The client of the network whose registry to read.
    /// - Returns: The cost of the account's registration, in lamports, excluding fees.
    /// - Throws: A ``Transactions/ValidationError`` if the record's derivation fails, or an error from
    ///   ``RPC/RPC/accounts(at:minContextSlot:)``.
    @concurrent
    public func registrationCost(using rpc: some RPC) async throws -> UInt64 {
        let record = try UserRegistry.record(of: signingAddress).address.value
        async let rent = ShieldedPool.registryRecordRent(using: rpc)
        async let records = rpc.accounts(at: [record])
        let held = try await records.value[0]?.lamports ?? 0
        let required = try await rent
        return required > held ? required - held : 0
    }
}
