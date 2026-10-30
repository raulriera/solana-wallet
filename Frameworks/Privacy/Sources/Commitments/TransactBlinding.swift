import ModularArithmetic

/// The blindings that a transact proof derives from its blinding seed.
enum TransactBlinding {
    /// The domain tag of the output blinding seed, ASCII TXOS.
    private static let outputBlindingSeedTag = Poseidon.Element(0x5458_4f53)

    /// The domain tag of an output blinding, ASCII TXOB.
    private static let outputBlindingTag = Poseidon.Element(0x5458_4f42)

    /// The domain tag of the private transaction blinding, ASCII TXPB.
    private static let privateTransactionBlindingTag = Poseidon.Element(0x5458_5042)

    /// Derives the seed of a proof's output blindings.
    ///
    /// - Parameters:
    ///   - firstNullifier: The nullifier of input slot 0.
    ///   - blindingSeed: The proof's private blinding seed.
    /// - Returns: `Poseidon("TXOS", firstNullifier, blindingSeed)`.
    static func outputBlindingSeed(firstNullifier: Poseidon.Element, blindingSeed: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(outputBlindingSeedTag, firstNullifier, blindingSeed)
    }

    /// Derives the blinding of one output slot.
    ///
    /// - Parameters:
    ///   - firstNullifier: The nullifier of input slot 0.
    ///   - outputBlindingSeed: The proof's output blinding seed.
    ///   - index: The zero-based output slot.
    /// - Returns: `Poseidon("TXOB", firstNullifier, outputBlindingSeed, index)`.
    static func outputBlinding(
        firstNullifier: Poseidon.Element,
        outputBlindingSeed: Poseidon.Element,
        index: UInt32
    ) -> Poseidon.Element {
        Poseidon.hash(outputBlindingTag, firstNullifier, outputBlindingSeed, Poseidon.Element(UInt64(index)))
    }

    /// Derives the blinding of a proof's private transaction hash.
    ///
    /// - Parameters:
    ///   - firstNullifier: The nullifier of input slot 0.
    ///   - blindingSeed: The proof's private blinding seed.
    /// - Returns: `Poseidon("TXPB", firstNullifier, blindingSeed)`.
    static func privateTransactionBlinding(firstNullifier: Poseidon.Element, blindingSeed: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(privateTransactionBlindingTag, firstNullifier, blindingSeed)
    }
}
