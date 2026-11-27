import Foundation

/// Runs an operation that must finish within a time limit.
///
/// - Parameters:
///   - limit: The longest the operation may take.
///   - clock: The clock that times the limit.
///   - operation: The work to run.
/// - Returns: The operation's result.
/// - Throws: A timeout ``RPCError`` or the operation's error.
func withTimeout<Value: Sendable>(_ limit: Duration, clock: any Clock<Duration>,
                                  _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await clock.sleep(for: limit)
            throw RPCError.transport(.timedOut)
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw RPCError.transport(.timedOut) }
        return value
    }
}
