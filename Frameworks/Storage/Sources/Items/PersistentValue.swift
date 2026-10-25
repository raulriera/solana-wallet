public import Observation

/// A saved value that views observe, such as the saved contacts, read once and shared by every window.
///
/// The value reads nothing until ``load()``. A change shows in ``value`` at once and saves after the changes made before
/// it; a change that can't be saved is undone, and the changes made after it stay.
///
/// ```swift
/// let bookmarks = PersistentValue(storage: FileItem(url: url, coding: .json([String].self)), empty: [])
/// await bookmarks.load()
/// try await bookmarks.update { $0.append("https://example.com") }
/// ```
@MainActor
@Observable
public final class PersistentValue<Value: Equatable & Sendable> {
    /// The value with every change made so far, or the empty value before one is read or saved.
    public private(set) var value: Value
    /// Whether the saved value was read.
    public private(set) var phase = PersistentValuePhase.unloaded
    @ObservationIgnored private let storage: any ValueStoring<Value>
    @ObservationIgnored private let empty: Value
    /// The value as saved, as far as this object knows, without the changes still being saved.
    @ObservationIgnored private var saved: Value
    /// The changes still being saved, in the order they were made, which is the order they finish.
    @ObservationIgnored private var pending: [@Sendable (inout Value) -> Void] = []
    /// The latest read, save, or deletion, which runs after the ones before it.
    @ObservationIgnored private var latest: Task<Void, any Error>?

    /// Connects to the storage without reading it.
    /// - Parameters:
    ///   - storage: The storage that keeps the value.
    ///   - empty: The value before one is saved, such as an empty list.
    public init(storage: any ValueStoring<Value>, empty: Value) {
        self.storage = storage
        self.empty = empty
        value = empty
        saved = empty
    }

    /// Reads the saved value, unless it was already read, and returns once every change made before this call is saved
    /// or undone.
    ///
    /// A call during a read joins it. A read that fails sets ``phase`` to ``PersistentValuePhase/unreadable`` and keeps
    /// ``value``; nothing saved is deleted or replaced, so calling this method again reads again.
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
    /// The change also runs on the saved value, which may differ from ``value``, so it must give the same result each
    /// time it runs on the same value. Cancellation doesn't stop or undo the save.
    /// - Parameter change: Changes the value.
    /// - Throws: A storage error after undoing the change; the changes made after it stay.
    public func update(_ change: @escaping @Sendable (inout Value) -> Void) async throws {
        pending.append(change)
        change(&value)
        try await enqueue { [storage, empty] in
            do {
                let saved = try await storage.update { stored in
                    var value = stored ?? empty
                    change(&value)
                    stored = value
                    return value
                }
                self.finishChange(saved: saved)
            } catch {
                self.finishChange(saved: nil)
                throw error
            }
        }.value
    }

    /// Deletes the saved value after the changes made before it are saved, and returns to the empty value.
    ///
    /// Cancellation doesn't stop the deletion.
    /// - Throws: A storage error, which keeps ``value``.
    public func erase() async throws {
        try await enqueue { [storage, empty] in
            try await storage.delete()
            self.settle(empty)
        }.value
    }

    /// Runs an operation after every operation queued before it.
    /// - Parameter operation: Reads, saves, or deletes the value.
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

    /// Records the outcome of the oldest change still being saved, which is the one that finished, since changes
    /// save in order.
    /// - Parameter saved: The value saved with the change, or `nil` when the change couldn't be saved.
    private func finishChange(saved: Value?) {
        pending.removeFirst()
        if let saved { settle(saved) } else { showPending() }
    }

    /// Records the value that's saved and shows it with the changes still being saved.
    /// - Parameter saved: The value that's saved.
    private func settle(_ saved: Value) {
        self.saved = saved
        phase = .loaded
        showPending()
    }

    /// Shows the saved value with the changes still being saved applied in order.
    private func showPending() {
        value = pending.reduce(into: saved) { value, change in change(&value) }
    }
}

/// Whether a ``PersistentValue`` read its saved value.
public enum PersistentValuePhase: Equatable, Sendable {
    /// Nothing was read yet.
    case unloaded
    /// The saved value is being read.
    case loading
    /// The value shows what's saved.
    case loaded
    /// The saved value can't be read; nothing saved is deleted or replaced.
    case unreadable
}
