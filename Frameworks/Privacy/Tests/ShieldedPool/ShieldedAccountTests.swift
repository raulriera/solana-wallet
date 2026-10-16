import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies shielded accounts: their keys, their shielded address, and their redaction.
struct ShieldedAccountTests {
    /// Verifies that the sender's keys derive its published nullifier public key and owner hash.
    @Test
    func `Accounts derive their shielded address`() throws {
        let rail = try CommitmentVectors.load().ed25519Rail

        let recipient = try TransferVectors.sender().recipient

        #expect(recipient.signingAddress.value == TransferVectors.senderSigningAddress)
        #expect(recipient.nullifierPublicKey == (try rail.nullifierKey().publicKey))
        #expect(recipient.owner == (try rail.ownerHash()))
    }

    /// Verifies that a nullifier secret of another length is rejected.
    ///
    /// - Parameter length: The secret's number of bytes.
    @Test(arguments: [30, 32])
    func `Nullifier secrets of another length are rejected`(length: Int) throws {
        let signingAddress = try Address(TransferVectors.senderSigningAddress)

        #expect(throws: NullifierKey.ValidationError.invalidSecretLength) {
            try ShieldedAccount(
                signingAddress: signingAddress, nullifierSecret: SymmetricKey(data: [UInt8](repeating: 1, count: length)),
                viewingKey: P256.KeyAgreement.PrivateKey()
            )
        }
    }

    /// Verifies that printing, dumping, and reflecting an account omit its keys.
    @Test
    func `Account diagnostics omit the keys`() throws {
        let account = try TransferVectors.sender()
        var dumped = ""
        dump(account, to: &dumped)

        #expect(String(describing: account) == "ShieldedAccount")
        #expect(String(reflecting: account) == "ShieldedAccount")
        #expect(dumped == "- ShieldedAccount\n")
    }
}
