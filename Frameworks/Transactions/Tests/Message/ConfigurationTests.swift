import Testing
import Transactions

/// Verifies invalid resource requests are rejected rather than clamped.
struct ConfigurationTests {
    /// Verifies the message must request a supported, nonzero compute budget.
    ///
    /// - Parameter limit: A zero or excessive compute unit limit.
    @Test(arguments: [UInt32(0), 1_400_001])
    func `Configuration rejects compute limits outside one through 1400000`(_ limit: UInt32) {
        #expect(throws: ValidationError.invalidComputeUnitLimit) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: limit, loadedAccountsDataSizeLimit: 65_536)
        }
    }

    /// Verifies loaded account data requests stay within the current runtime bounds.
    ///
    /// - Parameter limit: A zero or excessive byte limit.
    @Test(arguments: [UInt32(0), 67_108_865])
    func `Configuration rejects account data limits outside one byte through 64 MiB`(_ limit: UInt32) {
        #expect(throws: ValidationError.invalidLoadedAccountsDataSizeLimit) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: limit)
        }
    }

    /// Verifies heap requests respect both alignment and size constraints.
    ///
    /// - Parameter size: A misaligned or out-of-range heap size in bytes.
    @Test(arguments: [UInt32(31_744), 32_769, 263_168])
    func `Configuration rejects misaligned or out-of-range heap sizes`(_ size: UInt32) {
        #expect(throws: ValidationError.invalidHeapSize) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000,
                              loadedAccountsDataSizeLimit: 65_536, heapSize: size)
        }
    }
}
