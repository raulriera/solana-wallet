/// A request for the current epoch, absolute slot, and block height at finalized commitment.
public struct GetEpochInfo: RPCRequest {
    /// The provider-neutral JSON-RPC method name.
    public static let method = "getEpochInfo"

    /// An epoch observation with the absolute slot and block height at which it was read.
    public struct Response: Decodable, Sendable {
        /// The current epoch number.
        public let epoch: UInt64
        /// The absolute ledger slot corresponding to the observation.
        public let absoluteSlot: UInt64
        /// The block height corresponding to the observation, which is distinct from the slot.
        ///
        /// Compare this value with `GetLatestBlockhash.Value.lastValidBlockHeight`.
        public let blockHeight: UInt64

        /// Creates an epoch observation with its slot and block height.
        ///
        /// - Parameters:
        ///   - epoch: The current ledger epoch.
        ///   - absoluteSlot: The corresponding absolute slot.
        ///   - blockHeight: The corresponding block height.
        public init(epoch: UInt64, absoluteSlot: UInt64, blockHeight: UInt64) {
            self.epoch = epoch
            self.absoluteSlot = absoluteSlot
            self.blockHeight = blockHeight
        }
    }

    private let configuration: LedgerConfiguration

    /// Creates an epoch request at finalized commitment.
    ///
    /// - Parameter minContextSlot: The earliest acceptable observation slot, or `nil`.
    public init(minContextSlot: UInt64? = nil) {
        configuration = LedgerConfiguration(minContextSlot: minContextSlot)
    }

    /// Encodes the ledger constraints as a single positional configuration.
    ///
    /// - Parameter encoder: The encoder receiving the parameter array.
    /// - Throws: An encoding error if the configuration cannot be represented.
    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(configuration)
    }
}
