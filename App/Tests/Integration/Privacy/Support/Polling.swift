func poll<Value>(_ read: () async throws -> Value?) async throws -> Value? {
    for _ in 0..<30 {
        if let value = try await read() { return value }
        try await Task.sleep(for: .seconds(2))
    }
    return nil
}
