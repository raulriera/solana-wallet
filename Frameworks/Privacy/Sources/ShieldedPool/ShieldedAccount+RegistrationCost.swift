public import RPC
import Transactions

extension ShieldedAccount {
    /// Reads the lamports that the account's registration moves from its payer: the record's
    /// rent-exempt balance less the lamports that the record's address already holds, at least zero.
    ///
    /// The rent read and one finalized `getMultipleAccounts` read of the record's address run
    /// concurrently. A missing account holds no lamports. A registered account costs nothing, since
    /// its record holds the rent; the program still rejects its registration.
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
