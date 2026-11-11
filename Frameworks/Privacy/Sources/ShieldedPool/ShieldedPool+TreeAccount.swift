import RPC
import Transactions

extension ShieldedPool {
    /// A tree read that didn't return a valid tree account.
    public enum TreeError: Error, Equatable {
        case missingTree
        /// The shielded-pool program doesn't own the account at the tree's address.
        case foreignOwner
        case invalidLength
        /// The account's UTXO root history doesn't have the program's capacity or a consistent cursor and length.
        case invalidRootHistory
        /// The account's fee per tree exceeds the program's cap.
        case invalidFee
    }

    /// The layout of a tree account's data.
    enum TreeAccount {
        /// The length of a tree account, in bytes.
        static let length = 40_080

        static let feePerTreeOffset = 8

        /// The most that a tree charges each transact that writes it, in lamports.
        static let maximumFeePerTree: UInt64 = 1_000_000

        /// The offset of the UTXO root history's 16-bit index of its newest root.
        static let utxoRootCursorOffset = 112

        /// The offset of the UTXO root history's 16-bit count of written roots.
        static let utxoRootCountOffset = 114

        /// The offset of the UTXO root history's 16-bit capacity.
        static let utxoRootCapacityOffset = 116

        /// The offset of the UTXO root history's first 32-byte root.
        static let utxoRootsOffset = 1_152

        /// The number of UTXO roots that a full history holds.
        static let utxoRootCapacity = 500

        /// The number of nullifier roots that a full history holds.
        static let nullifierRootCapacity = 100
    }

    /// Reads the data of trees' accounts with one request after checking that the shielded-pool program owns each and
    /// that each has a tree account's length.
    ///
    /// - Parameters:
    ///   - trees: One through 100 tree accounts.
    ///   - rpc: The client of the network whose trees to read.
    /// - Returns: Each account's 40,080 bytes of data, in the order of `trees`.
    /// - Throws: An error from ``RPC/RPC/accounts(at:minContextSlot:)``, ``TreeError/missingTree`` without an account,
    ///   ``TreeError/foreignOwner`` if the program doesn't own one, or ``TreeError/invalidLength`` for data of another
    ///   length.
    static func treeAccountData(at trees: [Address], using rpc: some RPC) async throws -> [[UInt8]] {
        let accounts = try await rpc.accounts(at: trees.map(\.value)).value
        let owner = try program.value
        return try accounts.map { account in
            guard let account else { throw TreeError.missingTree }
            guard account.owner == owner else { throw TreeError.foreignOwner }
            guard account.data.count == TreeAccount.length else { throw TreeError.invalidLength }
            return [UInt8](account.data)
        }
    }
}
