import Foundation
import Storage

actor StoredValue<Value: Equatable & Sendable> {
    private(set) var value: Value?
    private(set) var deletions = 0
    private(set) var loads = 0
    private var failsLoading: Bool
    private var failsSaving: Bool
    private var failsDeleting: Bool
    private var isUnreadable: Bool
    private let gate: Suspension?
    private var readGate: Suspension?

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

    func failSaving(_ fails: Bool = true) {
        failsSaving = fails
    }

    func makeUnreadable() {
        isUnreadable = true
    }

    func save(_ value: Value) async throws {
        if failsSaving { throw CocoaError(.fileWriteUnknown) }
        self.value = value
        isUnreadable = false
        await gate?.suspend()
    }

    func delete() throws {
        if failsDeleting {
            failsDeleting = false
            throw CocoaError(.fileWriteUnknown)
        }
        value = nil
        isUnreadable = false
        deletions += 1
    }

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

extension StoredValue: ValueStoring {}
