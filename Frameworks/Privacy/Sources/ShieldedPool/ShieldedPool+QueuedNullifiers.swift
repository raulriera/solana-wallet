import ModularArithmetic
import RPC
import Transactions

extension ShieldedPool {
    /// Reads which of the notes' nullifiers the program already queued.
    ///
    /// - Parameters:
    ///   - notes: One through 100 notes.
    ///   - rpc: The client of the notes' network.
    /// - Returns: The 32-byte nullifiers whose accounts are in use.
    /// - Throws: ``RPC/GetMultipleAccountsError/invalidAddressCount`` without notes or for more
    ///   than 100, an RPC error, a ``ValidationError`` if a derivation fails, or
    ///   ``TreeError/mismatchedResponse`` if the provider returns another number of accounts.
    static func queuedNullifiers(of notes: [ReceivedNote], using rpc: some RPC) async throws -> Set<[UInt8]> {
        let addresses = try notes.map { try nullifierAccount(tree: tree(id: $0.treeID), nullifier: $0.nullifier).value }
        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses))
        guard response.value.count == notes.count else { throw TreeError.mismatchedResponse }
        let systemOwner = try systemProgram.value
        return Set(zip(notes, response.value).compactMap { note, account in
            guard let account, account.owner != systemOwner || !account.data.isEmpty else { return nil }
            return note.nullifier.bigEndianBytes
        })
    }
}
