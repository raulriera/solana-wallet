/// The fee and resource requests of a V1 message.
public struct Configuration: Sendable {
    /// The total priority fee, excluding the base transaction fee.
    public let priorityFeeLamports: UInt64
    public let computeUnitLimit: UInt32
    /// The maximum loaded account data size, in bytes.
    public let loadedAccountsDataSizeLimit: UInt32
    /// The heap size in bytes, or `nil` for the 32 KiB default.
    public let heapSize: UInt32?

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - priorityFeeLamports: The total priority fee in lamports.
    ///   - computeUnitLimit: A value from 1 through 1,400,000.
    ///   - loadedAccountsDataSizeLimit: A value from 1 through 67,108,864 bytes.
    ///   - heapSize: A multiple of 1,024 from 32,768 through 262,144, or `nil`.
    /// - Throws: A ``ValidationError`` for an out-of-range request.
    public init(
        priorityFeeLamports: UInt64,
        computeUnitLimit: UInt32,
        loadedAccountsDataSizeLimit: UInt32,
        heapSize: UInt32? = nil
    ) throws {
        guard (1...1_400_000).contains(computeUnitLimit) else {
            throw ValidationError.invalidComputeUnitLimit
        }
        guard (1...67_108_864).contains(loadedAccountsDataSizeLimit) else {
            throw ValidationError.invalidLoadedAccountsDataSizeLimit
        }
        try Self.validateHeapSize(heapSize)
        self.priorityFeeLamports = priorityFeeLamports
        self.computeUnitLimit = computeUnitLimit
        self.loadedAccountsDataSizeLimit = loadedAccountsDataSizeLimit
        self.heapSize = heapSize
    }

    /// Validates a heap size.
    ///
    /// - Parameter heapSize: The heap size in bytes, or `nil` for the default.
    /// - Throws: ``ValidationError/invalidHeapSize`` for an out-of-range or unaligned value.
    static func validateHeapSize(_ heapSize: UInt32?) throws {
        if let heapSize, !(32_768...262_144).contains(heapSize) || heapSize % 1_024 != 0 {
            throw ValidationError.invalidHeapSize
        }
    }
}
