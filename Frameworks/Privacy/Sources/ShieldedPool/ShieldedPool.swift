import ModularArithmetic
import Transactions

/// Solana Rings' shielded-pool program and the accounts that its instructions use.
///
/// The program's address is zolana v0.4.0-alpha's development program ID. The other accounts are
/// its program-derived addresses: the native-SOL custody account, from the seeds `sol_interface`
/// and `[0]`; each UTXO tree, from `tree` and the tree ID as a little-endian 16-bit integer; and
/// each spent nullifier, from `nullifier`, the tree's address, and the nullifier's 32 big-endian
/// bytes. Instructions start with a one-byte tag and continue in ``WincodeWriter``'s encoding.
enum ShieldedPool {
    /// The program's development address.
    private static let programID = "sppU489D7A4U1exNo1oeMGZtLEofq3a6o2fR7UeoWB6"

    /// The tag of the `transact` instruction, which the external data hash also covers.
    static let transactTag: UInt8 = 16

    /// The System Program, which moves native SOL.
    private static let systemProgramID = "11111111111111111111111111111111"

    /// The seeds of the native-SOL custody account.
    private static let solInterfaceSeeds = [Array("sol_interface".utf8), [0]]

    /// The seed prefix of a UTXO tree.
    private static let treeSeed = Array("tree".utf8)

    /// The seed prefix of a nullifier account.
    private static let nullifierSeed = Array("nullifier".utf8)

    /// The shielded-pool program.
    ///
    /// - Throws: ``ValidationError/invalidAddress`` if the program ID doesn't decode,
    ///   which doesn't happen.
    static var program: Address {
        get throws { try Address(programID) }
    }

    /// The System Program, which the shielded pool invokes to move native SOL.
    ///
    /// - Throws: ``ValidationError/invalidAddress`` if the program ID doesn't decode,
    ///   which doesn't happen.
    static var systemProgram: Address {
        get throws { try Address(systemProgramID) }
    }

    /// The account that holds the pool's native SOL: deposits pay into it and withdrawals pay out
    /// of it.
    ///
    /// - Throws: A ``ValidationError`` if the derivation fails, which doesn't happen.
    static var solInterface: Address {
        get throws { try ProgramAddress.find(seeds: solInterfaceSeeds, program: program).address }
    }

    /// Derives a UTXO tree's account.
    ///
    /// - Parameter id: The tree's ID.
    /// - Returns: The tree's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails, which doesn't happen.
    static func tree(id: UInt16) throws -> Address {
        var idBytes = [UInt8]()
        idBytes.appendLittleEndian(id)
        return try ProgramAddress.find(seeds: [treeSeed, idBytes], program: program).address
    }

    /// Derives the account that records a spent nullifier, which the program creates when a
    /// transact spends the nullifier's UTXO.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the spent UTXO.
    ///   - nullifier: The nullifier.
    /// - Returns: The nullifier's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails, which doesn't happen.
    static func nullifierAccount(tree: Address, nullifier: Poseidon.Element) throws -> Address {
        try ProgramAddress.find(seeds: [nullifierSeed, tree.bytes, nullifier.bigEndianBytes], program: program).address
    }
}
