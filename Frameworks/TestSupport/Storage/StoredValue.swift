import Foundation
import Storage

/// Keeps one value in memory in place of device storage, optionally failing each read or save or the first deletion,
/// keeping unreadable bytes, or suspending a save or an unreadable read.
actor StoredValue<Value: Equatable & Sendable> {
    private(set) var value: Value?
    /// How many times the value was deleted.
    private(set) var deletions = 0
    /// How many times the value was read, including the reads of updates.
    private(set) var loads = 0
    private var failsLoading: Bool
    private var failsSaving: Bool
    private var failsDeleting: Bool
    private var isUnreadable: Bool
    private let gate: Suspension?
    private var readGate: Suspension?

    /// Creates storage for one test.
    /// - Parameters:
    ///   - value: The value saved before the test starts, if any.
    ///   - failsLoading: Whether reads throw instead of returning the value.
    ///   - failsSaving: Whether saves throw instead of recording the value.
    ///   - failsFirstDeletion: Whether the first deletion throws and keeps the value and any unreadable bytes.
    ///   - unreadable: Whether the kept bytes are unreadable, as a damaged Keychain item's are, until a save or
    ///     deletion replaces them.
    ///   - gate: An optional suspension after a save records its value, for cancellation checks.
    ///   - readGate: An optional suspension before the first unreadable read throws, for overlap checks.
    init(_ value: Value? = nil, failsLoading: Bool = false, failsSaving: Bool = false, failsFirstDeletion: Bool = false,
         unreadable: Bool = false, gate: Suspension? = nil, readGate: Suspension? = nil) {
        self.value = value
        self.failsLoading = failsLoading
        self.failsSaving = failsSaving
        failsDeleting = failsFirstDeletion
        isUnreadable = unreadable
        self.gate = gate
        self.readGate = readGate
    }

    /// Returns the recorded value, or throws when this storage is configured to fail reads or keeps unreadable bytes.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: A read error when `failsLoading` is set, or ``KeychainItemError/unreadable`` for unreadable bytes,
    ///   even if they're replaced while the first unreadable read is suspended.
    func load() async throws -> Value? {
        loads += 1
        if failsLoading { throw CocoaError(.fileReadUnknown) }
        if isUnreadable {
            if let readGate {
                self.readGate = nil
                await readGate.suspend()
            }
            throw KeychainItemError.unreadable
        }
        return value
    }

    /// Makes later saves throw, as storage that stops accepting writes does, or succeed again.
    /// - Parameter fails: Whether later saves throw.
    func failSaving(_ fails: Bool = true) {
        failsSaving = fails
    }

    /// Makes the kept bytes unreadable, as a damaged Keychain item's are, until a save or deletion replaces them.
    func makeUnreadable() {
        isUnreadable = true
    }

    /// Records the value, or throws when this storage is configured to fail.
    /// - Parameter value: The value to save.
    /// - Throws: A write error when `failsSaving` is set.
    func save(_ value: Value) async throws {
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        self.value = value
        isUnreadable = false
        await gate?.suspend()
    }

    /// Forgets the recorded value and any unreadable bytes, and counts the deletion, or throws once when configured to
    /// fail the first deletion.
    /// - Throws: A write error for the first deletion when `failsFirstDeletion` is set.
    func delete() throws {
        if failsDeleting {
            failsDeleting = false
            throw CocoaError(.fileWriteUnknown)
        }
        value = nil
        isUnreadable = false
        deletions += 1
    }

    /// Changes the recorded value in one step, or throws when this storage is configured to fail.
    /// - Parameter change: Changes the recorded value; an unchanged value isn't saved again.
    /// - Returns: The change's result.
    /// - Throws: The change's error, a read error when `failsLoading` is set, ``KeychainItemError/unreadable`` for
    ///   unreadable bytes, or a write error when `failsSaving` is set and the value changed.
    func update<Result: Sendable>(_ change: @Sendable (inout Value?) throws -> Result) async throws -> Result {
        var changed = try await load()
        let result = try change(&changed)
        guard changed != value else { return result }
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        value = changed
        await gate?.suspend()
        return result
    }
}

/// The conformance sits in an extension so the compiler doesn't infer isolation for the actor from the protocol, which
/// fails some builds with a misleading "'nonisolated' modifier cannot be applied" error on this actor.
extension StoredValue: ValueStoring {}
