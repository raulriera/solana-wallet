import ModularArithmetic
import RPC
import Transactions

extension ShieldedPool {
    /// Reads which of the notes' nullifiers the program already queued, with one finalized
    /// `getMultipleAccounts` read of their nullifier accounts.
    ///
    /// A transact creates its nullifiers' accounts as it spends their notes, before the indexer
    /// reports the spend, and the program rejects a transact whose nullifier account is already in
    /// use. An account is in use once the program owns it or it holds data; a missing account, or a
    /// System Program account without data, isn't.
    ///
    /// - Parameters:
    ///   - notes: One through 100 notes, such as a spend's selection.
    ///   - rpc: The client of the notes' network.
    /// - Returns: The 32-byte nullifiers whose accounts are in use.
    /// - Throws: ``RPC/GetMultipleAccountsError/invalidAddressCount`` without notes or for more
    ///   than 100, an RPC error, a ``ValidationError`` if a derivation fails, which doesn't happen,
    ///   or ``TreeError/mismatchedResponse`` if the provider returns another number of accounts.
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
