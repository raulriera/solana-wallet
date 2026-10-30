import Dispatch
public import Foundation

/// A value saved on this device as one file.
public struct FileItem<Coding: ValueCoding>: ValueStoring {
    /// Blocking work that runs on the file queue.
    private typealias Operation<Result: Sendable> = @Sendable () throws -> Result

    public let url: URL
    public let coding: Coding
    let protection: FileProtectionType

    /// Creates an item that keeps its value in a file.
    ///
    /// - Parameters:
    ///   - url: The file that keeps the value.
    ///   - coding: The coding that converts the value to bytes.
    ///   - protection: When the file can be read and written.
    public init(url: URL, coding: Coding, protection: FileProtectionType = .complete) {
        self.url = url
        self.coding = coding
        self.protection = protection
    }

    public func load() async throws -> Coding.Value? {
        try await perform { [self] in try read() }
    }

    public func save(_ value: Coding.Value) async throws {
        try await perform { [self] in try write(value) }
    }

    public func delete() async throws {
        try await perform { [self] in try remove() }
    }

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

    /// Reads the saved value.
    ///
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

    /// Writes a value after checking that its bytes decode back to it.
    ///
    /// - Parameter value: The new value.
    /// - Throws: ``FileItemError/unencodable``, or an encoding or filesystem error.
    private func write(_ value: Coding.Value) throws {
        let data = try coding.encode(value)
        guard coding.decode(data) == value else { throw FileItemError.unencodable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, Data.WritingOptions(protection)])
    }

    /// Deletes the file if it exists.
    ///
    /// - Throws: A filesystem error.
    private func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
    }

    /// Runs blocking file work on the file queue.
    ///
    /// - Parameter operation: The blocking file work.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error or `CancellationError`.
    private func perform<Result: Sendable>(_ operation: @escaping Operation<Result>) async throws -> Result {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            FileQueue.shared.async { continuation.resume(with: Swift.Result(catching: operation)) }
        }
    }
}

extension Data.WritingOptions {
    /// Creates the write option for a file protection class.
    ///
    /// - Parameter protection: The file protection class.
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

/// The serial queue that every file item shares.
private enum FileQueue {
    static let shared = DispatchQueue(label: "FileItem.Files", qos: .userInitiated)
}
