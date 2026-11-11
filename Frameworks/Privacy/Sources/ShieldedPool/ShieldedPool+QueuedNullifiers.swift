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
    /// - Throws: An error from ``RPC/RPC/accounts(at:minContextSlot:)``, or a ``ValidationError`` if a derivation
    ///   fails.
    static func queuedNullifiers(of notes: [ReceivedNote], using rpc: some RPC) async throws -> Set<[UInt8]> {
        let addresses = try notes.map { try nullifierAccount(tree: tree(id: $0.treeID), nullifier: $0.nullifier).value }
        let accounts = try await rpc.accounts(at: addresses).value
        let systemOwner = try systemProgram.value
        return Set(zip(notes, accounts).compactMap { note, account in
            guard let account, account.owner != systemOwner || !account.data.isEmpty else { return nil }
            return note.nullifier.bigEndianBytes
        })
    }
}
