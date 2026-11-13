/// An on-chain program with a fixed address.
public protocol Program {
    /// The program's address as Base58 text.
    static var id: String { get }
}

extension Program {
    /// The program's address, decoded from ``id``.
    ///
    /// - Throws: ``ValidationError/invalidAddress`` if ``id`` doesn't encode 32 bytes.
    public static var address: Address {
        get throws { try Address(id) }
    }
}
