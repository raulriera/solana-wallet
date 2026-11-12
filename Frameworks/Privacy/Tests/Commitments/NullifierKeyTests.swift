import CryptoKit
import ModularArithmetic
import Testing
@testable import Privacy

struct NullifierKeyTests {
    @Test
    func `The public key matches the published nullifier public key`() throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        let key = try rail.nullifierKey()

        #expect(key.publicKey.bigEndianBytes == (try fixtureBytes(rail.nullifierPubkey)))
    }

    @Test(arguments: [
        (
            "03409e610c10c6e82bead86f12d0f79872c66e8ca3a51d796de1726aeed137ab", 1,
            "0a4a91cd454e7f8acb5bc0df7bc826570caa1d22914a0cc8aa62db94a978af6d"
        ),
        (
            "0e5cc81efe63454ebd769c706d697141626499d60889f5207cd823a0dc23a461", 3,
            "03440de6febefc54740d90e51412d74ee76abd757d713ac3636d33e8b34068f2"
        ),
    ] as [(String, UInt64, String)])
    func `Nullifiers of the zero secret match the published values`(utxoHash: String, blinding: UInt64, nullifier: String) throws {
        let key = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 0, count: 31)))

        let derived = key.nullifier(utxoHash: try Poseidon.Element(hex: utxoHash), blinding: Poseidon.Element(blinding))

        #expect(derived.bigEndianBytes == (try fixtureBytes(nullifier)))
    }

    @Test(arguments: TransferVectors.spentInputs)
    func `Nullifiers of the rail secret match the published transfers`(_ input: TransferVectors.Input) throws {
        let key = try CommitmentVectors.load().ed25519Rail.nullifierKey()

        let derived = key.nullifier(utxoHash: try Poseidon.Element(hex: input.hash), blinding: TransferVectors.blinding(input.blindingByte))

        #expect(derived.bigEndianBytes == (try fixtureBytes(input.nullifier)))
    }

    @Test(arguments: TransferVectors.paddingInputs)
    func `Nullifiers of padding inputs match the published transfers`(_ input: TransferVectors.Input) throws {
        let key = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 0, count: 31)))

        let derived = key.nullifier(utxoHash: try Poseidon.Element(hex: input.hash), blinding: TransferVectors.blinding(input.blindingByte))

        #expect(derived.bigEndianBytes == (try fixtureBytes(input.nullifier)))
    }

    @Test(arguments: [
        (
            "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
            try Poseidon.Element(hex: CommitmentVectors.load().dummyUTXOHash.hash),
            Poseidon.Element(7),
            "219b4c7cb8c5c108ef488dc65ae712b90b0e47410ac96c448cd34639d041bf9e"
        ),
        (
            "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            -Poseidon.Element.one,
            -Poseidon.Element.one,
            "0f7c900b8ad8fe1bf4bf96274d475b9fc41a01aa4c289af6014ebd3be809a5a9"
        ),
    ] as [(String, Poseidon.Element, Poseidon.Element, String)])
    func `Nullifiers match independently derived values`(
        secret: String,
        utxoHash: Poseidon.Element,
        blinding: Poseidon.Element,
        nullifier: String
    ) throws {
        let key = try NullifierKey(secret: SymmetricKey(data: fixtureBytes(secret)))

        let derived = key.nullifier(utxoHash: utxoHash, blinding: blinding)

        #expect(derived.bigEndianBytes == (try fixtureBytes(nullifier)))
    }

    @Test(arguments: [0, 30, 32])
    func `Secrets of other lengths are rejected`(length: Int) {
        #expect(throws: NullifierKey.ValidationError.invalidSecretLength) {
            try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 1, count: length)))
        }
    }

    @Test
    func `Nullifier key diagnostics omit the secret`() throws {
        let key = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 1, count: 31)))
        var output = ""
        dump(key, to: &output)

        #expect(key.description == "NullifierKey")
        #expect(key.debugDescription == "NullifierKey")
        #expect(String(reflecting: key) == "NullifierKey")
        #expect(output == "- NullifierKey\n")
        #expect(Mirror(reflecting: key).children.isEmpty)
    }
}
