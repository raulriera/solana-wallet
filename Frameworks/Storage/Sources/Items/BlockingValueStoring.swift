import Dispatch

/// A saved value whose blocking read, write, and remove steps run one at a time on a serial queue.
protocol BlockingValueStoring: ValueStoring {
    /// The serial queue that runs every item's blocking work.
    static var queue: DispatchQueue { get }

    /// Reads the saved value.
    ///
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: A storage error.
    func read() throws -> Value?

    /// Writes a value, replacing any value already saved.
    ///
    /// - Parameter value: The new value.
    /// - Throws: A storage error.
    func write(_ value: Value) throws

    /// Deletes the saved value if it exists.
    ///
    /// - Throws: A storage error.
    func remove() throws
}

extension BlockingValueStoring {
    public func load() async throws -> Value? {
        try await perform { [self] in try read() }
    }

    public func save(_ value: Value) async throws {
        try await perform { [self] in try write(value) }
    }

    public func delete() async throws {
        try await perform { [self] in try remove() }
    }

    public func update<Result: Sendable>(
        _ change: @escaping @Sendable (inout Value?) throws -> Result
    ) async throws -> Result {
        try await perform { [self] in
            let saved = try read()
            var value = saved
            let result = try change(&value)
            guard value != saved else { return result }
            if let value { try write(value) } else { try remove() }
            return result
        }
    }

    /// Runs blocking work on the queue.
    ///
    /// - Parameter operation: The blocking work.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error or `CancellationError`.
    private func perform<Result: Sendable>(_ operation: @escaping @Sendable () throws -> Result) async throws -> Result {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { continuation.resume(with: Swift.Result(catching: operation)) }
        }
    }
}
