import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies Solana owner identities and owner hashes.
struct OwnerIdentityTests {
    /// Verifies a Solana owner identity against zolana's published vector.
    ///
    /// The vector's public key is an arbitrary 32-byte value, tagged with 0x53 before
    /// `hash_bytes_33`.
    @Test
    func `Solana owner identities match the published vector`() throws {
        let vector = try CommitmentVectors.load().ownerIdentity

        #expect(OwnerIdentity.solana(signingPublicKey: try fixtureBytes(vector.solanaPubkey)).bigEndianBytes
            == (try fixtureBytes(vector.solanaOwnerIdentity)))
    }

    /// Verifies owner hashes against zolana's published Ed25519 accounts.
    ///
    /// The values are the `GOLDEN` accounts 0 and 1 of zolana's `seed-based-keypair.test.ts`,
    /// copied unchanged. The owner vector in `key_derivation.json` belongs to a P-256 owner, which
    /// this module doesn't support. CryptoKit derives each signing public key from its secret, and
    /// each nullifier key derives its public key from its secret.
    ///
    /// - Parameters:
    ///   - signingSecret: The account's 32-byte Ed25519 private key.
    ///   - signingPublicKey: The published public key of `signingSecret`.
    ///   - nullifierSecret: The account's 31-byte nullifier secret.
    ///   - nullifierPublicKey: The published public key of `nullifierSecret`.
    ///   - ownerHash: The published owner hash.
    @Test(arguments: [
        (
            "37df573b3ac4ad5b522e064e25b63ea16bcbe79d449e81a0268d1047948bb445",
            "f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7",
            "85e3a0d6bf9d62582e6500ea3245ddddbf65e517dbc985c85982e383e4751e",
            "070a4386ec323b299c7d7b9faf744e001b545974ac02fd148b537a4528ab8474",
            "06385c1c29400b46f21e0198c9f993663f8ee0475620734df093bdd1e4bae73b"
        ),
        (
            "ba5e7b6e3680b4eb81db8e54c8e466b2e9a899355888403355d858ab985d2fc4",
            "f8029acf5cbcbdd5ac46ec147f3b78a3df6e5022ef0411db2bab650d329a4cd4",
            "62351d526f51996740cc2e88978b084117fdee00af7c04df999a22321c9001",
            "1053061c5b9c4fc75b26b72d83d88d62f80e397cea6f36c07e25c9d8645106fc",
            "0fab761c5b882064cb84cdaed9809753d94cfb358375fc9b9f443750119edc86"
        ),
    ])
    func `Owner hashes match the published accounts`(
        signingSecret: String,
        signingPublicKey: String,
        nullifierSecret: String,
        nullifierPublicKey: String,
        ownerHash: String
    ) throws {
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: fixtureBytes(signingSecret))
        let derivedSigningPublicKey = Array(signingKey.publicKey.rawRepresentation)
        try #require(derivedSigningPublicKey == (try fixtureBytes(signingPublicKey)))
        let nullifierKey = try NullifierKey(secret: SymmetricKey(data: fixtureBytes(nullifierSecret)))
        try #require(nullifierKey.publicKey.bigEndianBytes == (try fixtureBytes(nullifierPublicKey)))

        let derivedOwnerHash = OwnerIdentity.ownerHash(
            signingPublicKey: derivedSigningPublicKey, nullifierPublicKey: nullifierKey.publicKey
        )

        #expect(derivedOwnerHash.bigEndianBytes == (try fixtureBytes(ownerHash)))
    }
}
