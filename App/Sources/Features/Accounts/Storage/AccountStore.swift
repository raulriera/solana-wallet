import Foundation
import Synchronization
import Transactions
import Wallet

/// Serializes local account metadata reads and atomic writes across app windows.
nonisolated struct AccountStore: AccountStoring {
    /// Filesystem work that can check cancellation before committing a write.
    private typealias Operation<Value: Sendable> = @Sendable (_ checkCancellation: () throws -> Void) throws -> Value

    /// A storage location or account identity that cannot be accepted.
    enum Failure: Error {
        /// Storage isn't a local regular file or its configured directory isn't local.
        case invalidStorage
        /// An account ID, public address, or recovery-and-path pair occurs more than once.
        case duplicateAccount
    }

    private let directory: URL
    private var file: URL { directory.appendingPathComponent("accounts.json") }
    private static let queue = DispatchQueue(label: "AccountStore.IO", qos: .utility)

    /// Configures local storage without creating directories or reading account data.
    /// - Parameter directory: The app-private directory containing account metadata.
    /// - Throws: ``Failure/invalidStorage`` if the directory isn't a file URL.
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Accounts", isDirectory: true)) throws {
        guard directory.isFileURL else { throw Failure.invalidStorage }
        self.directory = directory
    }

    /// Loads validated public metadata without accessing Vault.
    /// - Returns: The saved accounts, or an empty list when the file doesn't exist.
    /// - Throws: A storage, decoding, validation, or cancellation error.
    func load() async throws -> [Account] {
        try await perform { checkCancellation in
            let accounts = try read()
            try checkCancellation()
            return accounts
        }
    }

    /// Reads the latest list and commits one addition on the shared I/O queue.
    /// - Parameter account: Public metadata with a retained recovery identifier.
    /// - Returns: The committed list, including when cancellation follows the write.
    /// - Throws: A duplicate, storage, validation, or pre-commit cancellation error.
    func add(_ account: Account) async throws -> [Account] {
        try await perform { checkCancellation in
            let accounts = try read() + [account]
            try Self.validate(accounts)
            let data = try JSONEncoder().encode(accounts.map(Record.init))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try checkCancellation()
            try data.write(to: file, options: .atomic)
            return accounts
        }
    }

    /// Deletes the account file on the shared I/O queue; a missing file is already deleted.
    /// - Throws: A filesystem or pre-commit cancellation error.
    func removeAll() async throws {
        try await perform { checkCancellation in
            try checkCancellation()
            do {
                try FileManager.default.removeItem(at: file)
            } catch CocoaError.fileNoSuchFile {}
        }
    }

    /// Reads one complete file; malformed data and nonregular files are never reset.
    /// - Returns: The decoded and validated accounts.
    /// - Throws: A filesystem, decoding, or account validation error.
    private func read() throws -> [Account] {
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalidStorage }
        } catch CocoaError.fileReadNoSuchFile { return [] }
        let accounts = try JSONDecoder().decode([Record].self, from: Data(contentsOf: file)).map { try $0.account() }
        try Self.validate(accounts)
        return accounts
    }

    /// Checks unique identities before accepting a complete list.
    /// - Parameter accounts: The full loaded or proposed list.
    /// - Throws: ``Failure/duplicateAccount``.
    private static func validate(_ accounts: [Account]) throws {
        var ids: Set<UUID> = []
        var addresses: Set<Address> = []
        var paths: [UUID: Set<String>] = [:]
        for account in accounts {
            guard ids.insert(account.id).inserted,
                  addresses.insert(account.address).inserted,
                  paths[account.recoveryID, default: []].insert(account.path.description).inserted else {
                throw Failure.duplicateAccount
            }
        }
    }

    /// Suspends while the serial queue performs a complete filesystem operation.
    /// - Parameter operation: Synchronous work that checks cancellation before committing.
    /// - Returns: The operation's result without discarding an already committed write.
    /// - Throws: The operation's error or cancellation before its commit point.
    private func perform<Value: Sendable>(
        _ operation: @escaping Operation<Value>
    ) async throws -> Value {
        let cancelled = Mutex(false)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    let result = autoreleasepool {
                        Result {
                            let check = { if cancelled.withLock({ $0 }) { throw CancellationError() } }
                            try check()
                            return try operation(check)
                        }
                    }
                    continuation.resume(with: result)
                }
            }
        } onCancel: { cancelled.withLock { $0 = true } }
    }

    /// The public metadata fields written to disk; recovery secrets have no representation here.
    private struct Record: Codable {
        let id: UUID
        let recoveryID: UUID
        let address: String
        let path: String

        /// Copies public account metadata into its storage representation.
        /// - Parameter account: The validated account to encode.
        init(_ account: Account) {
            id = account.id
            recoveryID = account.recoveryID
            address = account.address.value
            path = account.path.description
        }

        /// Reconstructs an account through the address validation boundary.
        /// - Returns: Typed account metadata for subsequent list validation.
        /// - Throws: An address or derivation-path validation error.
        func account() throws -> Account {
            Account(id: id, recoveryID: recoveryID, address: try Address(address), path: try DerivationPath(path))
        }
    }
}
