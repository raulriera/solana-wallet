import CryptoKit
import Foundation

/// A validated English BIP-39 recovery phrase.
///
/// Access ``words`` explicitly for backup. Descriptions and reflection omit the phrase.
/// The value is held in memory; it doesn't provide persistence or guaranteed memory erasure.
public struct RecoveryPhrase: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A supported BIP-39 phrase length.
    public enum WordCount: Int, CaseIterable, Sendable {
        /// Twelve words representing 128 bits of entropy.
        case twelve = 12
        /// Fifteen words representing 160 bits of entropy.
        case fifteen = 15
        /// Eighteen words representing 192 bits of entropy.
        case eighteen = 18
        /// Twenty-one words representing 224 bits of entropy.
        case twentyOne = 21
        /// Twenty-four words representing 256 bits of entropy.
        case twentyFour = 24

        /// The number of entropy bytes represented by this phrase length.
        var entropyByteCount: Int { rawValue / 3 * 4 }
    }

    /// A recovery phrase validation failure that never contains supplied words.
    public enum ValidationError: Error, Equatable {
        /// The phrase doesn't contain a supported number of words.
        case invalidWordCount
        /// A word isn't in the English word list, at the specified zero-based position.
        case unknownWord(position: Int)
        /// The phrase's checksum doesn't match its entropy.
        case invalidChecksum
        /// The entropy doesn't contain a supported number of bytes.
        case invalidEntropy
    }

    /// The validated words, exposed explicitly for backup.
    public let words: [String]

    /// A description that omits the recovery words.
    public var description: String { "RecoveryPhrase" }

    /// A debugging description that omits the recovery words.
    public var debugDescription: String { description }

    /// A reflection view that omits the recovery words.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Validates and normalizes an imported recovery phrase.
    ///
    /// Normalization accepts uppercase English words and repeated whitespace.
    /// Words must match the BIP-39 English list and contain a valid checksum.
    ///
    /// - Parameter phrase: The recovery words separated by whitespace.
    /// - Throws: ``ValidationError`` if the length, words, or checksum are invalid.
    public init(_ phrase: String) throws {
        let words = phrase.decomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard let count = WordCount(rawValue: words.count) else {
            throw ValidationError.invalidWordCount
        }
        let indices = try words.enumerated().map { position, word in
            guard let index = English.indices[word] else {
                throw ValidationError.unknownWord(position: position)
            }
            return index
        }
        let bits = indices.flatMap { index in
            (0..<11).reversed().map { (index >> $0) & 1 }
        }
        var entropy = [UInt8](repeating: 0, count: count.entropyByteCount)
        for bit in 0..<(entropy.count * 8) {
            entropy[bit / 8] |= UInt8(bits[bit] << (7 - bit % 8))
        }
        let expected = try Self(entropy: entropy)
        guard words == expected.words else { throw ValidationError.invalidChecksum }
        self.words = words
    }

    /// Encodes entropy and its SHA-256 checksum as English recovery words.
    ///
    /// - Parameter entropy: Between 16 and 32 bytes, in increments of four.
    /// - Throws: ``ValidationError/invalidEntropy`` if the byte count is unsupported.
    init(entropy: [UInt8]) throws {
        guard let count = WordCount.allCases.first(where: { $0.entropyByteCount == entropy.count }) else {
            throw ValidationError.invalidEntropy
        }
        let checksum = Array(SHA256.hash(data: entropy))[0]
        let bytes = entropy + [checksum]
        words = (0..<count.rawValue).map { word in
            var index = 0
            for bit in (word * 11)..<(word * 11 + 11) {
                index = (index << 1) | Int((bytes[bit / 8] >> (7 - bit % 8)) & 1)
            }
            return English.words[index]
        }
    }
}
