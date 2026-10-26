import Dispatch
public import Foundation

/// A value saved on this device as one file, such as the saved contacts.
///
/// By default, the file is readable only while the device is unlocked. A file that can't be read is reported, never
/// deleted or replaced with an empty value.
public struct FileItem<Coding: ValueCoding>: ValueStoring {
    /// Blocking file work that runs only on the file queue.
    private typealias Operation<Result: Sendable> = @Sendable () throws -> Result

    /// The file that keeps the value.
    public let url: URL
    /// How the value is kept as bytes.
    public let coding: Coding
    /// When the file can be read and written, which each save applies.
    let protection: FileProtectionType

    /// Names the file without creating or reading it.
    /// - Parameters:
    ///   - url: The file that keeps the value, inside a directory the app owns.
    ///   - coding: How the value is kept as bytes, such as `.json([String].self)`.
    ///   - protection: When the file can be read and written; by default, only while the device is unlocked. Use
    ///     `.completeUntilFirstUserAuthentication` for a file that work in the background saves while the device is
    ///     locked.
    public init(url: URL, coding: Coding, protection: FileProtectionType = .complete) {
        self.url = url
        self.coding = coding
        self.protection = protection
    }

    /// Reads the saved value.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``FileItemError/unreadable`` for bytes that aren't a value, a filesystem error, or
    ///   `CancellationError`.
    public func load() async throws -> Coding.Value? {
        try await perform { [self] in try read() }
    }

    /// Saves a value, replacing any value already saved, in one atomic write.
    ///
    /// A value whose bytes don't decode back to an equal value isn't saved. Cancellation doesn't roll back a save
    /// that has already been written.
    /// - Parameter value: The new value.
    /// - Throws: ``FileItemError/unencodable``, an encoding or filesystem error, or `CancellationError`.
    public func save(_ value: Coding.Value) async throws {
        try await perform { [self] in try write(value) }
    }

    /// Deletes the file; a missing file is already deleted.
    /// - Throws: A filesystem error or `CancellationError`.
    public func delete() async throws {
        try await perform { [self] in try remove() }
    }

    /// Reads, changes, and saves the value in one step on the file queue, so changes from several windows don't
    /// overwrite each other.
    ///
    /// Cancellation doesn't roll back a change that has already been written.
    /// - Parameter change: Changes the saved value, or `nil` before one is saved; setting `nil` deletes the file,
    ///   and an unchanged value isn't saved again.
    /// - Returns: The change's result.
    /// - Throws: The change's error, which keeps the saved value, ``FileItemError``, an encoding or filesystem error,
    ///   or `CancellationError`.
    public func update<Result: Sendable>(
        _ change: @escaping @Sendable (inout Coding.Value?) throws -> Result
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

    /// Reads the saved value on the file queue.
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``FileItemError/unreadable`` or a filesystem error.
    private func read() throws -> Coding.Value? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        guard let value = coding.decode(data) else { throw FileItemError.unreadable }
        return value
    }

    /// Saves a value on the file queue once its bytes decode back to it.
    /// - Parameter value: The new value.
    /// - Throws: ``FileItemError/unencodable`` before writing bytes that don't decode back to the value, or an
    ///   encoding or filesystem error.
    private func write(_ value: Coding.Value) throws {
        let data = try coding.encode(value)
        guard coding.decode(data) == value else { throw FileItemError.unencodable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, Data.WritingOptions(protection)])
    }

    /// Deletes the file on the file queue; a missing file is already deleted.
    /// - Throws: A filesystem error.
    private func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
    }

    /// Runs blocking file work outside Swift's cooperative executor.
    /// - Parameter operation: File work that stays on the file queue.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error, or `CancellationError` if canceled before it's scheduled.
    private func perform<Result: Sendable>(_ operation: @escaping Operation<Result>) async throws -> Result {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            FileQueue.shared.async { continuation.resume(with: Swift.Result(catching: operation)) }
        }
    }
}

extension Data.WritingOptions {
    /// The write option that gives a file a protection class.
    /// - Parameter protection: When the file can be read and written; an unknown class gets complete protection.
    init(_ protection: FileProtectionType) {
        self = switch protection {
        case .none: .noFileProtection
        case .completeUnlessOpen: .completeFileProtectionUnlessOpen
        case .completeUntilFirstUserAuthentication: .completeFileProtectionUntilFirstUserAuthentication
        case .completeWhenUserInactive: .completeFileProtectionWhenUserInactive
        default: .completeFileProtection
        }
    }
}

/// The serial queue that every file item shares, so each save and each read-change-save runs atomically.
private enum FileQueue {
    static let shared = DispatchQueue(label: "FileItem.Files", qos: .userInitiated)
}
