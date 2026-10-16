import ModularArithmetic

/// The public input that packs a transact proof's dummy-input policy and each input's tree,
/// `pack_input_flags`.
///
/// Bit 0 allows padding inputs; this module always sets it, as zolana's clients do. Input i's tree
/// position occupies the three bits from bit `1 + 3i`. The value is a big-endian field element
/// below 2^148, since a proof has at most 49 inputs.
///
/// The program sets bit 0 itself from the trees' room for padding nullifiers. If a tree runs low,
/// the program clears the bit and rejects a proof that padding inputs need.
enum InputFlags {
    /// The most inputs that a transact proof has.
    private static let maximumInputs = 49

    /// The number of tree slots that a proof publishes, which three bits address.
    private static let treeSlots = 5

    /// Packs the input trees of a proof that allows padding inputs.
    ///
    /// - Parameter treeIndexes: Each input slot's position among the declared input trees, in slot
    ///   order.
    /// - Returns: The packed flags.
    /// - Precondition: There are at most 49 inputs, and each position is below 5.
    static func pack(treeIndexes: [UInt8]) -> Poseidon.Element {
        precondition(treeIndexes.count <= maximumInputs, "A transact proof has at most 49 inputs.")
        var bytes = [UInt8](repeating: 0, count: 32)
        setBits(UInt16(1), at: 0, in: &bytes)
        for (index, treeIndex) in treeIndexes.enumerated() {
            precondition(Int(treeIndex) < treeSlots, "A tree position addresses one of the 5 tree slots.")
            setBits(UInt16(treeIndex), at: 1 + 3 * index, in: &bytes)
        }
        return Poseidon.Element(reducing: bytes)
    }

    /// Sets the bits of a small value at a bit position of a big-endian integer.
    ///
    /// - Parameters:
    ///   - value: A value of at most three bits.
    ///   - shift: The position of the value's lowest bit; bit b is bit `b % 8` of byte `31 - b / 8`.
    ///   - bytes: The 32-byte big-endian integer.
    private static func setBits(_ value: UInt16, at shift: Int, in bytes: inout [UInt8]) {
        let shifted = value << (shift % 8)
        let low = bytes.count - 1 - shift / 8
        bytes[low] |= UInt8(truncatingIfNeeded: shifted)
        if shifted > 0xff { bytes[low - 1] |= UInt8(truncatingIfNeeded: shifted >> 8) }
    }
}
