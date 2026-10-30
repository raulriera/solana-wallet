public import Observation

/// An observable saved value that loads once and saves changes in order.
@MainActor
@Observable
public final class PersistentValue<Value: Equatable & Sendable> {
    /// The value with every change made so far, including changes still being saved.
    public private(set) var value: Value
    public private(set) var phase = PersistentValuePhase.unloaded
    @ObservationIgnored private let storage: any ValueStoring<Value>
    @ObservationIgnored private let empty: Value
    /// The saved value, without the changes still being saved.
    @ObservationIgnored private var saved: Value
    /// The changes still being saved, oldest first.
    @ObservationIgnored private var pending: [@Sendable (inout Value) -> Void] = []
    /// The latest queued read, save, or deletion.
    @ObservationIgnored private var latest: Task<Void, any Error>?

    /// Creates a value that a storage keeps, without reading it.
    ///
    /// - Parameters:
    ///   - storage: The storage that keeps the value.
    ///   - empty: The value before one is saved, such as an empty list.
    public init(storage: any ValueStoring<Value>, empty: Value) {
        self.storage = storage
        self.empty = empty
        value = empty
        saved = empty
    }

    /// Reads the saved value unless it was already read.
    public func load() async {
        if phase == .unloaded || phase == .unreadable {
            phase = .loading
            enqueue { [storage, empty] in
                do {
                    self.settle(try await storage.load() ?? empty)
                } catch {
                    self.phase = .unreadable
                }
            }
        }
        _ = await latest?.result
    }

    /// Changes the value at once and saves the change after the changes made before it.
    ///
    /// - Parameter change: A closure that changes the value.
    /// - Throws: A storage error, after undoing the change.
    public func update(_ change: @escaping @Sendable (inout Value) -> Void) async throws {
        pending.append(change)
        var changed = value
        change(&changed)
        show(changed)
        try await enqueue { [storage, empty] in
            do {
                let saved = try await storage.update { stored in
                    var value = stored ?? empty
                    change(&value)
                    if stored != nil || value != empty { stored = value }
                    return value
                }
                self.finishChange(saved: saved)
            } catch {
                self.finishChange(saved: nil)
                throw error
            }
        }.value
    }

    /// Deletes the saved value and returns to the empty value.
    ///
    /// - Throws: A storage error.
    public func erase() async throws {
        try await enqueue { [storage, empty] in
            try await storage.delete()
            self.settle(empty)
        }.value
    }

    /// Runs an operation after every operation queued before it.
    ///
    /// - Parameter operation: The read, save, or deletion to run.
    /// - Returns: The operation's task.
    @discardableResult
    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, any Error> {
        let previous = latest
        let task = Task {
            _ = await previous?.result
            try await operation()
        }
        latest = task
        return task
    }

    /// Records the outcome of the oldest change still being saved.
    ///
    /// - Parameter saved: The value saved with the change, or `nil` when the change couldn't be saved.
    private func finishChange(saved: Value?) {
        pending.removeFirst()
        if let saved { settle(saved) } else { showPending() }
    }

    /// Records the value that's saved and shows it with the changes still being saved.
    ///
    /// - Parameter saved: The value that's saved.
    private func settle(_ saved: Value) {
        self.saved = saved
        if phase != .loaded { phase = .loaded }
        showPending()
    }

    /// Shows the saved value with the changes still being saved applied in order.
    private func showPending() {
        show(pending.reduce(into: saved) { value, change in change(&value) })
    }

    /// Shows a value unless it's already shown.
    ///
    /// - Parameter new: The value to show.
    private func show(_ new: Value) {
        if value != new { value = new }
    }
}

/// The loading phase of a ``PersistentValue``.
public enum PersistentValuePhase: Equatable, Sendable {
    case unloaded
    case loading
    case loaded
    case unreadable
}
