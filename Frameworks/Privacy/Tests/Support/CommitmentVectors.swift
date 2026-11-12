import CryptoKit
import ModularArithmetic
import Testing
@testable import Privacy

struct CommitmentVectors: Decodable, Sendable {
    let hashBytes: [ByteHash]

    let ownerIdentity: OwnerIdentities

    let blindingSeed: BlindingSeed

    let dummyUTXOHash: DummyUTXOHash

    let ed25519Rail: Rail

    private enum CodingKeys: String, CodingKey {
        case hashBytes = "hash_bytes"
        case ownerIdentity = "owner_identity"
        case blindingSeed = "blinding_seed"
        case dummyUTXOHash = "dummy_utxo_hash"
        case ed25519Rail = "eddsa_rail"
    }

    struct ByteHash: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let input: String
        let output: String

        var testDescription: String { name }
    }

    struct OwnerIdentities: Decodable, Sendable {
        let solanaPubkey: String
        let solanaOwnerIdentity: String
        let hashBytes33Input: String
        let hashBytes33: String

        private enum CodingKeys: String, CodingKey {
            case solanaPubkey = "solana_pubkey"
            case solanaOwnerIdentity = "solana_owner_identity"
            case hashBytes33Input = "hash_bytes_33_input"
            case hashBytes33 = "hash_bytes_33"
        }
    }

    struct BlindingSeed: Decodable, Sendable {
        let firstNullifier: UInt64
        let blindingSeed: UInt64
        let outputBlindingSeed: String
        let privateTxBlinding: String
        let outputIndex: UInt32
        let directOutputBlinding: String
        let derivedOutputBlinding: String

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

    struct DummyUTXOHash: Decodable, Sendable {
        let treeID: UInt16
        let blinding: UInt64
        let hash: String

        private enum CodingKeys: String, CodingKey {
            case treeID = "tree_id"
            case blinding, hash
        }
    }

    struct Rail: Decodable, Sendable {
        let signerPubkey: String
        let nullifierSecret: String
        let nullifierPubkey: String
        let viewingSecret: String
        let viewingPubkey: String

        private enum CodingKeys: String, CodingKey {
            case signerPubkey = "signer_pubkey"
            case nullifierSecret = "nullifier_secret"
            case nullifierPubkey = "nullifier_pubkey"
            case viewingSecret = "viewing_secret"
            case viewingPubkey = "viewing_pubkey"
        }


        func nullifierSecretKey() throws -> SymmetricKey {
            SymmetricKey(data: try fixtureBytes(nullifierSecret))
        }

        func nullifierKey() throws -> NullifierKey {
            try NullifierKey(secret: nullifierSecretKey())
        }

        func viewingKey() throws -> Curve25519.KeyAgreement.PrivateKey {
            try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: fixtureBytes(viewingSecret))
        }

        func ownerHash() throws -> Poseidon.Element {
            OwnerIdentity.ownerHash(
                signingPublicKey: try fixtureBytes(signerPubkey), nullifierPublicKey: try nullifierKey().publicKey
            )
        }
    }

    static func load() throws -> Self {
        try fixture(named: "CommitmentVectors")
    }
}
