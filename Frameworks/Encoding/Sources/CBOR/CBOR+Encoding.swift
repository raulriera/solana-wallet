extension CBOR {
    /// The item's deterministic encoding.
    ///
    /// Every argument takes its shortest form, every array, map, and string has a definite length, and map keys
    /// follow the bytewise order of their encodings, as RFC 8949's core deterministic encoding requires.
    public var encoded: [UInt8] {
        var bytes: [UInt8] = []
        append(to: &bytes)
        return bytes
    }

    /// Appends the item's deterministic encoding.
    ///
    /// - Parameter bytes: The bytes to append the encoding to.
    private func append(to bytes: inout [UInt8]) {
        switch self {
        case .integer(let value) where value >= 0:
            bytes.appendHead(majorType: 0, argument: UInt64(value))
        case .integer(let value):
            bytes.appendHead(majorType: 1, argument: UInt64(-1 - value))
        case .bytes(let value):
            bytes.appendHead(majorType: 2, argument: UInt64(value.count))
            bytes.append(contentsOf: value)
        case .text(let value):
            bytes.appendHead(majorType: 3, argument: UInt64(value.utf8.count))
            bytes.append(contentsOf: value.utf8)
        case .array(let items):
            bytes.appendHead(majorType: 4, argument: UInt64(items.count))
            for item in items {
                item.append(to: &bytes)
            }
        case .map(let entries):
            bytes.appendHead(majorType: 5, argument: UInt64(entries.count))
            let sorted = entries.map { (key: $0.key.item.encoded, value: $0.value) }
                .sorted { $0.key.lexicographicallyPrecedes($1.key) }
            for entry in sorted {
                bytes.append(contentsOf: entry.key)
                entry.value.append(to: &bytes)
            }
        case .boolean(let value):
            bytes.append(value ? 0xf5 : 0xf4)
        case .null:
            bytes.append(0xf6)
        }
    }
}

private extension CBOR.Key {
    /// The key as a data item.
    var item: CBOR {
        switch self {
        case .integer(let value): .integer(value)
        case .text(let value): .text(value)
        }
    }
}

private extension [UInt8] {
    /// Appends the initial byte of a CBOR data item and the shortest form of its argument.
    ///
    /// - Parameters:
    ///   - majorType: The item's major type.
    ///   - argument: The item's value or length.
    mutating func appendHead(majorType: UInt8, argument: UInt64) {
        let additional: UInt8 =
            switch argument {
            case ..<24: UInt8(argument)
            case ...0xff: 24
            case ...0xffff: 25
            case ...0xffff_ffff: 26
            default: 27
            }
        append(majorType << 5 | additional)
        guard additional >= 24 else { return }
        let byteCount = 1 << (additional - 24)
        append(contentsOf: (0..<byteCount).reversed().map { UInt8(truncatingIfNeeded: argument >> ($0 * 8)) })
    }
}
