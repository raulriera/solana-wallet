import Testing
import Transactions

struct ConfigurationTests {
    @Test(arguments: [UInt32(0), 1_400_001])
    func `Configuration rejects compute limits outside one through 1400000`(_ limit: UInt32) {
        #expect(throws: ValidationError.invalidComputeUnitLimit) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: limit, loadedAccountsDataSizeLimit: 65_536)
        }
    }

    @Test(arguments: [UInt32(0), 67_108_865])
    func `Configuration rejects account data limits outside one byte through 64 MiB`(_ limit: UInt32) {
        #expect(throws: ValidationError.invalidLoadedAccountsDataSizeLimit) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: limit)
        }
    }

    @Test(arguments: [UInt32(31_744), 32_769, 263_168])
    func `Configuration rejects misaligned or out-of-range heap sizes`(_ size: UInt32) {
        #expect(throws: ValidationError.invalidHeapSize) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000,
                              loadedAccountsDataSizeLimit: 65_536, heapSize: size)
        }
    }
}
