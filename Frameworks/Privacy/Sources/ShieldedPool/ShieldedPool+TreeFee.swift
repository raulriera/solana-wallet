public import RPC
import Transactions

extension ShieldedPool {
    /// A tree account that doesn't hold a fee schedule.
    public enum TreeError: Error, Equatable {
        /// No account exists at the tree's address.
        case missingTree
        /// The shielded-pool program doesn't own the account at the tree's address.
        case foreignOwner
        /// The account is too short to hold the fee per nullifier.
        case invalidLength
        /// The provider returned a different number of accounts than the read asked for.
        case mismatchedResponse
    }

    /// The position of the fee per nullifier in a tree account: after the discriminator, the state,
    /// the tree ID, and 4 bytes of padding, the first field of the fee schedule.
    private static let feePerNullifierOffset = 8

    /// Reads the fee that a transact pays a tree for each input slot that spends from it, with one
    /// finalized `getMultipleAccounts` read of the tree's account.
    ///
    /// The fee is the tree's `fee_per_nullifier`, a little-endian 64-bit integer at offset 8. The
    /// fee payer pays it once for each of a spend's ``PrivateSpend/nullifierCount`` slots in the
    /// tree, padding included. The tree's authority can change it.
    ///
    /// - Parameters:
    ///   - treeID: The tree's ID, such as ``NoteSyncState/outputTreeID``.
    ///   - rpc: The client of the network whose tree to read.
    /// - Returns: The fee per nullifier, in lamports.
    /// - Throws: An RPC error, ``TreeError/mismatchedResponse`` if the provider returns another
    ///   number of accounts, ``TreeError/missingTree`` without an account,
    ///   ``TreeError/foreignOwner`` if the program doesn't own it, or ``TreeError/invalidLength``
    ///   if it's shorter than 16 bytes.
    @concurrent
    public static func feePerNullifier(treeID: UInt16, using rpc: some RPC) async throws -> UInt64 {
        let response = try await rpc.send(GetMultipleAccounts(addresses: [try tree(id: treeID).value]))
        guard response.value.count == 1 else { throw TreeError.mismatchedResponse }
        guard let account = response.value[0] else { throw TreeError.missingTree }
        guard account.owner == (try program).value else { throw TreeError.foreignOwner }
        let data = [UInt8](account.data)
        guard data.count >= feePerNullifierOffset + UInt64.bitWidth / 8 else { throw TreeError.invalidLength }
        return data.littleEndian(at: feePerNullifierOffset)
    }
}
