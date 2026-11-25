import Testing
@testable import Wallet

struct SeedDerivationTests {
    private static let trezorSeed = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

    private static let cafeSeed = "af8bbd2566df7b69d926f2b09dfdbd75db6c994a3399b2cc65f928d63e3fd4e61218ee0d15f8c810be4d45e66d47b43c15a5cc753976b1666912377ff7ae9818"

    @Test(arguments: try BIP39Vector.examples())
    func `Recovery phrases derive the BIP-39 reference seeds`(vector: BIP39Vector) throws {
        let phrase = try RecoveryPhrase(vector.phrase)
        let seed = try SeedDerivation.seed(for: phrase, passphrase: "TREZOR")

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

    @Test(arguments: [
        ("", "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"),
        (" TREZOR ", "c3e2744f57e3f6e362753a4a240fa209988f367d09b2d77b05b62ced64c7f175ebebd7bfa2d424260697eafa26991241992d6627d64f4b4eba2d178db20a0275"),
        ("\u{FF34}\u{FF32}\u{FF25}\u{FF3A}\u{FF2F}\u{FF32}", trezorSeed),
        ("caf\u{E9}", cafeSeed),
        ("cafe\u{301}", cafeSeed),
        ("e\u{301}\u{FF9E}", "4cc068dffe2722269e66068443038c746348bc352c3c170c02e449391237916db874e1edb772066e46d99be080470b65409fcb4fab1a77f9dde9536d88c72c3f"),
        ("\u{1FFD}\u{316}", "ee7e529e7af997b923caed336dfbae577b44de351617ab5bd65bf14050259b0742c79143d92ec7243c086047d5462b427fd96420b75b104b43869c0eabe09fbc"),
        ("e\u{301}\u{F73}", "563d43dc9596a90edeecaea668eae16af98c3cac0f9b1d1dd63b22a5c13fba279a0e4cc8c0ca62d452a6d1541dc93b7adfb8f1679806594a8c468e8426906063"),
    ])
    func `Passphrases derive the seed of their NFKD form`(passphrase: String, seed: String) throws {
        let derived = try SeedDerivation.seed(for: ThrowawayRecovery.phrase(), passphrase: passphrase)

        #expect(derived == (try fixtureBytes(seed)))
    }

    @Test
    func `A cancelled task derives no seed`() async throws {
        let phrase = try ThrowawayRecovery.phrase()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SeedDerivation.seed(for: phrase, passphrase: "")
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
