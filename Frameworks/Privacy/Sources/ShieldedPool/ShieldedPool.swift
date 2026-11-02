import ModularArithmetic
import Transactions

/// The shielded-pool program and the accounts that its instructions use.
public enum ShieldedPool {
    public static let programID = "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW"

    static let transactTag: UInt8 = 16

    private static let systemProgramID = "11111111111111111111111111111111"

    private static let solInterfaceSeeds = [Array("sol_interface".utf8), [0]]

    private static let treeSeed = Array("tree".utf8)

    private static let nullifierSeed = Array("nullifier".utf8)

    static var program: Address {
        get throws { try Address(programID) }
    }

    static var systemProgram: Address {
        get throws { try Address(systemProgramID) }
    }

    /// The account that holds the pool's native SOL.
    static var solInterface: Address {
        get throws { try ProgramAddress.find(seeds: solInterfaceSeeds, program: program).address }
    }

    /// Derives a UTXO tree's account.
    ///
    /// - Parameter id: The tree's ID.
    /// - Returns: The tree's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails.
    static func tree(id: UInt16) throws -> Address {
        var idBytes = [UInt8]()
        idBytes.appendLittleEndian(id)
        return try ProgramAddress.find(seeds: [treeSeed, idBytes], program: program).address
    }

    /// Derives the account that records a spent nullifier.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the spent UTXO.
    ///   - nullifier: The nullifier.
    /// - Returns: The nullifier's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails.
    static func nullifierAccount(tree: Address, nullifier: Poseidon.Element) throws -> Address {
        try ProgramAddress.find(seeds: [nullifierSeed, tree.bytes, nullifier.bigEndianBytes], program: program).address
    }
}
