import Security

/// A source of cryptographically secure entropy.
protocol EntropyProviding: Sendable {
    /// Returns the requested number of random bytes.
    ///
    /// - Parameter count: The number of bytes to generate.
    /// - Returns: Exactly `count` random bytes.
    /// - Throws: An error if secure randomness is unavailable.
    func bytes(count: Int) throws -> [UInt8]
}

/// An entropy source backed by Apple's Security framework.
struct SystemEntropy: EntropyProviding {
    /// Generates bytes with the system's cryptographically secure random number generator.
    ///
    /// - Parameter count: The number of bytes to generate.
    /// - Returns: Exactly `count` random bytes.
    /// - Throws: ``SystemEntropyError/unavailable(status:)`` if the system reports a failure.
    func bytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SystemEntropyError.unavailable(status: status) }
        return bytes
    }
}
