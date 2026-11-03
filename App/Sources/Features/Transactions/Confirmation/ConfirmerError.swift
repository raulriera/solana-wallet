/// An error that leaves a sent transaction's outcome unknown.
nonisolated enum ConfirmerError: Error, Sendable, Equatable {
    case invalidResponse
}
