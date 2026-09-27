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
    /// A failure reported by the system's secure random number generator.
    enum Failure: Error, Equatable {
        /// The system couldn't generate random bytes.
        case unavailable(status: Int32)
    }

    /// Generates bytes with the system's cryptographically secure random number generator.
    ///
    /// - Parameter count: The number of bytes to generate.
    /// - Returns: Exactly `count` random bytes.
    /// - Throws: ``Failure/unavailable(status:)`` if the system reports a failure.
    func bytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw Failure.unavailable(status: status) }
        return bytes
    }
}
