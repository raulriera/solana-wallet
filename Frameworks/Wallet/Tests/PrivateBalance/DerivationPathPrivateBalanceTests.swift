import CryptoKit
import Testing
@testable import Wallet

/// Verifies the Solana Rings coin type, account indices, which paths have keys, and role paths.
struct DerivationPathPrivateBalanceTests {
    /// Verifies the coin type against the rule that defines it: the first four bytes of
    /// SHA-256(`luminous.TSPP.v1`) as a big-endian integer, without its top bit.
    @Test
    func `The coin type is the truncated SHA-256 of its label`() {
        let digest = Array(SHA256.hash(data: Array("luminous.TSPP.v1".utf8)))
        let coinType = digest.prefix(4).reduce(UInt32.zero) { $0 << 8 | UInt32($1) } & 0x7fff_ffff

        #expect(DerivationPath.privateBalanceCoinType == coinType)
    }

    /// Verifies that a Solana account path gives its account index, up to the largest one.
    ///
    /// - Parameters:
    ///   - path: A path `m/44'/501'/i'/0'`.
    ///   - account: The path's account index i.
    @Test(arguments: [
        ("m/44'/501'/0'/0'", 0), ("m/44'/501'/1'/0'", 1), ("m/44'/501'/2147483647'/0'", 2_147_483_647),
    ])
    func `Solana account paths give their account index`(path: String, account: UInt32) throws {
        #expect(try DerivationPath(path).privateBalanceAccount == account)
    }

    /// Verifies that every other path, including Solana's other discovered family, has no account index.
    ///
    /// - Parameter path: A path outside `m/44'/501'/i'/0'`.
    @Test(arguments: [
        "m", "m/44'/501'/0'", "m/44'/501'/0'/1'", "m/44'/60'/0'/0'", "m/44'/501'/0'/0'/0'", "m/45'/501'/0'/0'",
    ])
    func `Other paths have no account index`(path: String) throws {
        #expect(try DerivationPath(path).privateBalanceAccount == nil)
    }

    /// Verifies that only Solana account paths report private-balance keys.
    ///
    /// - Parameters:
    ///   - path: A derivation path.
    ///   - hasKeys: Whether the path is `m/44'/501'/i'/0'`.
    @Test(arguments: [
        ("m/44'/501'/0'/0'", true), ("m/44'/501'/2147483647'/0'", true), ("m/44'/501'/0'", false),
        ("m/44'/501'/0'/1'", false), ("m/44'/60'/0'/0'", false), ("m", false),
    ])
    func `Only Solana account paths have private-balance keys`(path: String, hasKeys: Bool) throws {
        #expect(try DerivationPath(path).hasPrivateBalanceKeys == hasKeys)
    }
}
