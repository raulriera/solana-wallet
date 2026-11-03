import Encoding

extension DER {
    /// A reader of the values in a constructed value, in order.
    struct FieldReader {
        private var values: ArraySlice<DER>

        /// Creates a reader.
        ///
        /// - Parameter values: The values to read.
        fileprivate init(_ values: [DER]) {
            self.values = values[...]
        }

        /// Reads the next value.
        ///
        /// - Returns: The value.
        /// - Throws: ``NitroCertificate/ValidationError/malformed`` when no value remains.
        mutating func next() throws -> DER {
            guard let value = values.popFirst() else { throw NitroCertificate.ValidationError.malformed }
            return value
        }

        /// Reads the next value when it has an identifier.
        ///
        /// - Parameter identifier: The identifier of the optional field.
        /// - Returns: The value, or `nil` when the next value has another identifier or no value remains.
        mutating func next(_ identifier: DER.Identifier) -> DER? {
            guard values.first?.identifier == identifier else { return nil }
            return values.popFirst()
        }

        /// Reads the next value when it has an explicit tag.
        ///
        /// - Parameter tag: The identifier of the optional, explicitly tagged field.
        /// - Returns: The one value inside the tag, or `nil` when the next value has another identifier or no value
        ///   remains.
        /// - Throws: ``NitroCertificate/ValidationError/malformed`` for a tag that is primitive or doesn't hold
        ///   exactly one value.
        mutating func next(explicitlyTagged tag: DER.Identifier) throws -> DER? {
            guard let tagged = next(tag) else { return nil }
            let inner = try tagged.values(tag)
            guard inner.count == 1 else { throw NitroCertificate.ValidationError.malformed }
            return inner[0]
        }

        /// Reads an optional BOOLEAN whose default is FALSE.
        ///
        /// - Returns: `true` when the field is present.
        /// - Throws: ``NitroCertificate/ValidationError/invalidBoolean`` for a BOOLEAN other than TRUE.
        mutating func booleanDefaultingToFalse() throws -> Bool {
            guard let value = next(.boolean) else { return false }
            guard value.content == .primitive([0xff]) else { throw NitroCertificate.ValidationError.invalidBoolean }
            return true
        }

        /// Checks that every value was read.
        ///
        /// - Throws: ``NitroCertificate/ValidationError/malformed`` when a value remains.
        func finish() throws {
            guard values.isEmpty else { throw NitroCertificate.ValidationError.malformed }
        }
    }

    /// Reads the values of a constructed value.
    ///
    /// - Parameter identifier: The identifier the value must have.
    /// - Returns: The values, in order.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for a value with another identifier or a primitive
    ///   value.
    func values(_ identifier: Identifier = .sequence) throws -> [DER] {
        guard self.identifier == identifier, case .constructed(let values) = content else {
            throw NitroCertificate.ValidationError.malformed
        }
        return values
    }

    /// Creates a reader of the values of a SEQUENCE.
    ///
    /// - Returns: A reader at the first value.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for a value other than a SEQUENCE.
    func fields() throws -> FieldReader {
        FieldReader(try values())
    }

    /// Reads the contents of a primitive value.
    ///
    /// - Parameter identifier: The identifier the value must have.
    /// - Returns: The contents.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for a value with another identifier or a
    ///   constructed value.
    func primitive(_ identifier: Identifier) throws -> [UInt8] {
        guard self.identifier == identifier, case .primitive(let bytes) = content else {
            throw NitroCertificate.ValidationError.malformed
        }
        return bytes
    }

    /// Reads a non-negative INTEGER.
    ///
    /// - Returns: The integer's big-endian magnitude without leading zero octets, which is empty for zero.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for another type, or
    ///   ``NitroCertificate/ValidationError/invalidInteger`` for an INTEGER that is negative, empty, or not in its
    ///   shortest form.
    func nonNegativeInteger() throws -> ArraySlice<UInt8> {
        let bytes = try primitive(.integer)
        guard let first = bytes.first, first & 0x80 == 0, bytes.count == 1 || first != 0 || bytes[1] & 0x80 != 0 else {
            throw NitroCertificate.ValidationError.invalidInteger
        }
        return first == 0 ? bytes.dropFirst() : bytes[...]
    }

    /// Reads a non-negative INTEGER that `Int` can represent.
    ///
    /// - Returns: The integer.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for another type, or
    ///   ``NitroCertificate/ValidationError/invalidInteger`` for an INTEGER that isn't in its shortest form or that
    ///   `Int` can't represent.
    func intValue() throws -> Int {
        let magnitude = try nonNegativeInteger()
        guard magnitude.count <= 8, let value = Int(exactly: magnitude.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        else { throw NitroCertificate.ValidationError.invalidInteger }
        return value
    }

    /// Reads a BIT STRING.
    ///
    /// - Returns: The octets that hold the bits, and the number of unused bits at the end of the last octet.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for another type, or
    ///   ``NitroCertificate/ValidationError/invalidBitString`` for a missing or out-of-range count of unused bits,
    ///   or unused bits that aren't zero.
    func bitString() throws -> (octets: ArraySlice<UInt8>, unusedBitCount: Int) {
        let bytes = try primitive(.bitString)
        guard let unusedBitCount = bytes.first, unusedBitCount < 8 else {
            throw NitroCertificate.ValidationError.invalidBitString
        }
        let octets = bytes.dropFirst()
        guard octets.last.map({ $0 & ((1 << unusedBitCount) - 1) == 0 }) ?? (unusedBitCount == 0) else {
            throw NitroCertificate.ValidationError.invalidBitString
        }
        return (octets, Int(unusedBitCount))
    }

    /// Reads a BIT STRING of whole octets.
    ///
    /// - Returns: The octets.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for another type, or
    ///   ``NitroCertificate/ValidationError/invalidBitString`` for a BIT STRING with unused bits.
    func octetAlignedBitString() throws -> [UInt8] {
        let (octets, unusedBitCount) = try bitString()
        guard unusedBitCount == 0 else { throw NitroCertificate.ValidationError.invalidBitString }
        return Array(octets)
    }

    /// Reads an OBJECT IDENTIFIER.
    ///
    /// - Returns: The contents, which encode the subidentifiers.
    /// - Throws: ``NitroCertificate/ValidationError/malformed`` for another type, or
    ///   ``NitroCertificate/ValidationError/invalidObjectIdentifier`` for empty contents, a subidentifier with a
    ///   leading `0x80` octet, or a last subidentifier that doesn't end.
    func objectIdentifier() throws -> [UInt8] {
        let bytes = try primitive(.objectIdentifier)
        guard let last = bytes.last, last & 0x80 == 0,
            zip([0] + bytes, bytes).allSatisfy({ previous, octet in previous & 0x80 != 0 || octet != 0x80 })
        else { throw NitroCertificate.ValidationError.invalidObjectIdentifier }
        return bytes
    }
}
