import Encoding
import ModularArithmetic
public import Transactions

/// The shielded-pool program and the accounts that its instructions use.
public enum ShieldedPool: Program {
    /// The shielded-pool program's address.
    public static let id = "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW"

    static let transactTag: UInt8 = 16

    static let mergeTransactTag: UInt8 = 17

    private static let solInterfaceSeeds = [Array("sol_interface".utf8), [0]]

    private static let splInterfaceSeed = Array("spl_asset_vault".utf8)

    private static let cpiAuthoritySeed = Array("cpi_authority".utf8)

    private static let treeSeed = Array("tree".utf8)

    private static let nullifierSeed = Array("nullifier".utf8)

    /// The account that holds the pool's native SOL.
    static var solInterface: Address {
        get throws { try ProgramAddress.find(seeds: solInterfaceSeeds, program: address).address }
    }

    /// The program's authority over the token accounts that hold the pool's tokens, which signs token withdrawals.
    static var cpiAuthority: Address {
        get throws { try ProgramAddress.find(seeds: [cpiAuthoritySeed], program: address).address }
    }

    /// Returns the token account that holds the pool's tokens of a mint, with its bump.
    ///
    /// - Parameter mint: The token's mint.
    /// - Returns: The interface account's address and bump.
    /// - Throws: A ``Transactions/ValidationError`` if the derivation fails.
    static func splInterface(of mint: Address) throws -> (address: Address, bump: UInt8) {
        try ProgramAddress.find(seeds: [splInterfaceSeed, mint.bytes], program: address)
    }

    /// Derives a UTXO tree's account.
    ///
    /// - Parameter id: The tree's ID.
    /// - Returns: The tree's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails.
    static func tree(id: UInt16) throws -> Address {
        var idBytes: [UInt8] = []
        idBytes.append(littleEndian: id)
        return try ProgramAddress.find(seeds: [treeSeed, idBytes], program: address).address
    }

    /// Derives the account that records a spent nullifier.
    ///
    /// - Parameters:
    ///   - tree: The account of the tree that holds the spent UTXO.
    ///   - nullifier: The nullifier.
    /// - Returns: The nullifier's account address.
    /// - Throws: A ``ValidationError`` if the derivation fails.
    static func nullifierAccount(tree: Address, nullifier: Poseidon.Element) throws -> Address {
        try ProgramAddress.find(seeds: [nullifierSeed, tree.bytes, nullifier.bigEndianBytes], program: address).address
    }
}
