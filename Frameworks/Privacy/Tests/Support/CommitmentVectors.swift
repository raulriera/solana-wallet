import CryptoKit
import ModularArithmetic
@testable import Privacy
import Testing

/// zolana's Solana Rings commitment vectors.
///
/// `CommitmentVectors.json` copies, unchanged at tag v0.4.0-alpha (Apache-2.0), the whole array of
/// `test-vectors/hash_bytes.json`; the `owner_identity`, `blinding_seed`, and `dummy_utxo_hash`
/// sections of `test-vectors/transact_derivation.json`; and the `ed25519_rail` and `p256_rail`
/// sections of `test-vectors/key_derivation.json`. `CommitmentVectors-LICENSE.txt` records the
/// sources and their digests. Byte strings are hexadecimal; small integers are JSON numbers, which
/// the vectors hash as right-aligned big-endian field elements.
struct CommitmentVectors: Decodable, Sendable {
    /// `hash_bytes_N` vectors for 0, 1, 31, 32, 62, and 63 bytes.
    let hashBytes: [ByteHash]

    /// Owner identities and a 33-byte `hash_bytes_33` vector.
    let ownerIdentity: OwnerIdentities

    /// The blindings of one transact blinding seed.
    let blindingSeed: BlindingSeed

    /// The hash of one empty UTXO.
    let dummyUTXOHash: DummyUTXOHash

    /// The keys that zolana's Ed25519 rail derives.
    let ed25519Rail: Rail

    /// The keys that zolana's P-256 rail derives.
    let p256Rail: Rail

    /// The fixture's JSON keys.
    private enum CodingKeys: String, CodingKey {
        case hashBytes = "hash_bytes"
        case ownerIdentity = "owner_identity"
        case blindingSeed = "blinding_seed"
        case dummyUTXOHash = "dummy_utxo_hash"
        case ed25519Rail = "ed25519_rail"
        case p256Rail = "p256_rail"
    }

    /// A byte string and its `hash_bytes_N` commitment, where N is its length.
    struct ByteHash: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name in the fixture.
        let name: String
        /// The bytes.
        let input: String
        /// The 32-byte commitment.
        let output: String

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// The parts of the owner-identity section that cover Solana owners and `hash_bytes_33`.
    struct OwnerIdentities: Decodable, Sendable {
        /// A 32-byte Solana public key.
        let solanaPubkey: String
        /// The key's owner identity, `hash_bytes_33(0x53 ‖ key)`.
        let solanaOwnerIdentity: String
        /// A 33-byte value.
        let hashBytes33Input: String
        /// The value's `hash_bytes_33` commitment.
        let hashBytes33: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case solanaPubkey = "solana_pubkey"
            case solanaOwnerIdentity = "solana_owner_identity"
            case hashBytes33Input = "hash_bytes_33_input"
            case hashBytes33 = "hash_bytes_33"
        }
    }

    /// One proof's blinding seed and the blindings derived from it.
    struct BlindingSeed: Decodable, Sendable {
        /// The nullifier of input slot 0, as an integer.
        let firstNullifier: UInt64
        /// The proof's blinding seed, as an integer.
        let blindingSeed: UInt64
        /// The derived output blinding seed.
        let outputBlindingSeed: String
        /// The derived private transaction blinding.
        let privateTxBlinding: String
        /// The output slot of both output blindings.
        let outputIndex: UInt32
        /// The output blinding of ``blindingSeed`` itself used as the output blinding seed.
        let directOutputBlinding: String
        /// The output blinding of ``outputBlindingSeed``, as the protocol derives it.
        let derivedOutputBlinding: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case firstNullifier = "first_nullifier"
            case blindingSeed = "blinding_seed"
            case outputBlindingSeed = "output_blinding_seed"
            case privateTxBlinding = "private_tx_blinding"
            case outputIndex = "output_index"
            case directOutputBlinding = "output_blinding"
            case derivedOutputBlinding = "output_blinding_derived"
        }
    }

    /// An empty UTXO's tree, blinding, and hash.
    struct DummyUTXOHash: Decodable, Sendable {
        /// The ID of the output tree.
        let treeID: UInt16
        /// The output blinding, as an integer.
        let blinding: UInt64
        /// The empty UTXO's hash.
        let hash: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case treeID = "tree_id"
            case blinding, hash
        }
    }

    /// The parts of one derivation rail that cover its signing public key, nullifier key, and
    /// viewing key.
    struct Rail: Decodable, Sendable, CustomTestStringConvertible {
        /// The 32-byte Ed25519 signing public key; the P-256 rail has none.
        let signerPubkey: String?
        /// The 31-byte nullifier secret.
        let nullifierSecret: String
        /// The nullifier public key, `Poseidon(nullifier secret)`.
        let nullifierPubkey: String
        /// The 32-byte P-256 viewing secret.
        let viewingSecret: String
        /// The viewing key's SEC1 compressed public key.
        let viewingPubkey: String

        /// The fixture's JSON keys.
        private enum CodingKeys: String, CodingKey {
            case signerPubkey = "signer_pubkey"
            case nullifierSecret = "nullifier_secret"
            case nullifierPubkey = "nullifier_pubkey"
            case viewingSecret = "viewing_secret"
            case viewingPubkey = "viewing_pubkey"
        }

        /// The rail's nullifier public key, in test results.
        var testDescription: String { "Nullifier public key \(nullifierPubkey)" }

        /// Creates the rail's published nullifier secret.
        ///
        /// - Returns: The secret.
        /// - Throws: A test failure if the secret is malformed.
        func nullifierSecretKey() throws -> SymmetricKey {
            SymmetricKey(data: try fixtureBytes(nullifierSecret))
        }

        /// Creates the rail's nullifier key from its published secret.
        ///
        /// - Returns: The nullifier key.
        /// - Throws: A test failure if the secret is malformed, or an error if it isn't 31 bytes.
        func nullifierKey() throws -> NullifierKey {
            try NullifierKey(secret: nullifierSecretKey())
        }

        /// Creates the rail's viewing key from its published secret.
        ///
        /// - Returns: The viewing key.
        /// - Throws: A test failure if the secret is malformed, or a CryptoKit error if it isn't a
        ///   P-256 private key.
        func viewingKey() throws -> P256.KeyAgreement.PrivateKey {
            try P256.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(viewingSecret))
        }

        /// Derives the rail's owner hash from its published signing public key and nullifier secret.
        ///
        /// - Returns: The owner hash.
        /// - Throws: A test failure if the rail has no signing public key, as the P-256 rail has none,
        ///   or if a value is malformed, or an error if the nullifier secret isn't 31 bytes.
        func ownerHash() throws -> Poseidon.Element {
            OwnerIdentity.ownerHash(
                signingPublicKey: try fixtureBytes(#require(signerPubkey)), nullifierPublicKey: try nullifierKey().publicKey
            )
        }
    }

    /// The Ed25519 and P-256 rails.
    var rails: [Rail] { [ed25519Rail, p256Rail] }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The commitment vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "CommitmentVectors")
    }
}
