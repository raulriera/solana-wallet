import Foundation
import Testing
@testable import Wallet

/// Tests BIP-39 encoding, import validation, and recovery phrase diagnostics.
struct RecoveryPhraseTests {
    /// Verifies generation and import against reference phrases from known entropy.
    ///
    /// - Parameter vector: A public reference phrase and its entropy.
    @Test(arguments: try BIP39Vector.examples())
    func `Known entropy produces the BIP-39 recovery words`(vector: BIP39Vector) throws {
        let entropy = try fixtureBytes(vector.entropy)
        let count = try #require(RecoveryPhrase.WordCount(rawValue: vector.phrase.split(separator: " ").count))
        let wallet = Wallet(entropy: FixedEntropy(value: entropy))

        let generated = try wallet.recoveryPhrase(wordCount: count)
        let imported = try RecoveryPhrase(vector.phrase)

        #expect(generated.words.joined(separator: " ") == vector.phrase)
        #expect(imported.words == generated.words)
    }

    /// Verifies that invalid lengths are rejected before word or checksum processing.
    ///
    /// - Parameter count: An unsupported number of recovery words.
    @Test(arguments: [0, 1, 11, 13, 25])
    func `Recovery phrases reject unsupported word counts`(count: Int) {
        let phrase = Array(repeating: "abandon", count: count).joined(separator: " ")
        #expect(throws: RecoveryPhrase.ValidationError.invalidWordCount) {
            try RecoveryPhrase(phrase)
        }
    }

    /// Verifies that an unknown word reports its position without reproducing the word.
    @Test
    func `Unknown recovery words report their position`() {
        let phrase = Array(repeating: "abandon", count: 11).joined(separator: " ") + " not-a-bip39-word"
        #expect(throws: RecoveryPhrase.ValidationError.unknownWord(position: 11)) {
            try RecoveryPhrase(phrase)
        }
    }

    /// Verifies that known words with an incorrect checksum can't be imported.
    @Test
    func `Recovery phrases reject an incorrect checksum`() {
        #expect(throws: RecoveryPhrase.ValidationError.invalidChecksum) {
            try RecoveryPhrase(Array(repeating: "abandon", count: 12).joined(separator: " "))
        }
    }

    /// Verifies that printing and reflecting a phrase omit the words and their storage.
    @Test
    func `Recovery phrase diagnostics omit recovery words`() throws {
        let phrase = try RecoveryPhrase(Array(repeating: "abandon", count: 11).joined(separator: " ") + " about")
        var output = ""
        dump(phrase, to: &output)

        #expect(String(describing: phrase) == "RecoveryPhrase")
        #expect(String(reflecting: phrase) == "RecoveryPhrase")
        #expect(Mirror(reflecting: phrase).children.isEmpty)
        #expect(!output.contains("abandon"))
        #expect(!output.contains("about"))
    }

    /// Verifies that generation fails when secure randomness can't be obtained.
    @Test
    func `Unavailable secure randomness prevents phrase creation`() {
        let wallet = Wallet(entropy: UnavailableEntropy())
        #expect(throws: UnavailableEntropyError.unavailable) {
            try wallet.recoveryPhrase()
        }
    }
}

/// Supplies only the fixed public entropy from a test vector.
private struct FixedEntropy: EntropyProviding {
    let value: [UInt8]

    /// Returns the injected entropy after checking the requested byte count.
    ///
    /// - Parameter count: The number of bytes requested by the wallet.
    /// - Returns: The reference entropy bytes.
    func bytes(count: Int) -> [UInt8] {
        #expect(count == value.count)
        return value
    }
}

/// The error an always-failing entropy source reports.
private enum UnavailableEntropyError: Error { case unavailable }

/// An entropy source that always fails.
private struct UnavailableEntropy: EntropyProviding {
    /// Reports an unavailable random number generator.
    ///
    /// - Parameter count: The requested entropy size.
    /// - Throws: ``UnavailableEntropyError/unavailable`` for every request.
    func bytes(count: Int) throws -> [UInt8] {
        throw UnavailableEntropyError.unavailable
    }
}
