/// A value kept in memory that's also saved to another storage when that storage works.
///
/// A read or a save that the other storage can't do never fails the item: the item starts without a value, and it
/// keeps every change in memory.
public actor MemoryItem<Value: Equatable & Sendable>: ValueStoring {
    private let copy: any ValueStoring<Value>
    private var value: Value?
    private var isRead = false

    /// Creates an item that saves its value to another storage.
    ///
    /// - Parameter copy: The storage that keeps the value between launches.
    public init(savingTo copy: any ValueStoring<Value>) {
        self.copy = copy
    }

    public func load() async -> Value? {
        if !isRead {
            value = try? await copy.load()
            isRead = true
        }
        return value
    }

    public func save(_ value: Value) async {
        self.value = value
        isRead = true
        try? await copy.save(value)
    }

    public func delete() async throws {
        value = nil
        isRead = true
        try await copy.delete()
    }

    public func update<Result: Sendable>(
        _ change: @escaping @Sendable (inout Value?) throws -> Result
    ) async throws -> Result {
        var changed = await load()
        let result = try change(&changed)
        if let changed {
            await save(changed)
        } else {
            try? await delete()
        }
        return result
    }
}
