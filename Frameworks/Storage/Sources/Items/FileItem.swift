import Dispatch
public import Foundation

/// A value saved on this device as one file.
public struct FileItem<Coding: ValueCoding>: BlockingValueStoring {
    public typealias Value = Coding.Value

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

    static var queue: DispatchQueue { FileQueue.shared }

    /// Reads the saved value.
    ///
    /// - Returns: The value, or `nil` before one is saved.
    /// - Throws: ``FileItemError/unreadable`` or a filesystem error.
    func read() throws -> Coding.Value? {
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
    func write(_ value: Coding.Value) throws {
        let data = try coding.encode(value)
        guard coding.decode(data) == value else { throw FileItemError.unencodable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, Data.WritingOptions(protection)])
    }

    /// Deletes the file if it exists.
    ///
    /// - Throws: A filesystem error.
    func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
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
