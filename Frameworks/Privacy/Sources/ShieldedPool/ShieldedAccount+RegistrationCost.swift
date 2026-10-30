public import RPC
import Transactions

extension ShieldedAccount {
    /// Reads the lamports that the account's registration moves from its payer.
    ///
    /// - Parameter rpc: The client of the network whose registry to read.
    /// - Returns: The cost of the account's registration, in lamports, excluding fees.
    /// - Throws: An RPC error, or ``UserRegistry/ValidationError/mismatchedResponse`` if the provider
    ///   returns another number of accounts.
    @concurrent
    public func registrationCost(using rpc: some RPC) async throws -> UInt64 {
        let read = try GetMultipleAccounts(addresses: [try UserRegistry.record(of: signingAddress).address.value])
        async let rent = ShieldedPool.registryRecordRent(using: rpc)
        async let records = rpc.send(read)
        let response = try await records
        guard response.value.count == 1 else { throw UserRegistry.ValidationError.mismatchedResponse }
        let held = response.value[0]?.lamports ?? 0
        let required = try await rent
        return required > held ? required - held : 0
    }
}
