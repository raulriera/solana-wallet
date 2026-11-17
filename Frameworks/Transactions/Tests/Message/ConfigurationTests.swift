import Testing
import Transactions

struct ConfigurationTests {
    @Test(arguments: [
        (UInt32(0), UInt32(65_536), UInt32?.none, ValidationError.invalidComputeUnitLimit),
        (1_400_001, 65_536, nil, .invalidComputeUnitLimit),
        (20_000, 0, nil, .invalidLoadedAccountsDataSizeLimit),
        (20_000, 67_108_865, nil, .invalidLoadedAccountsDataSizeLimit),
        (20_000, 65_536, 31_744, .invalidHeapSize),
        (20_000, 65_536, 32_769, .invalidHeapSize),
        (20_000, 65_536, 263_168, .invalidHeapSize),
    ])
    func `Configuration rejects resource requests outside their supported ranges`(
        computeUnitLimit: UInt32, loadedAccountsDataSizeLimit: UInt32, heapSize: UInt32?, error: ValidationError
    ) {
        #expect(throws: error) {
            try Configuration(priorityFeeLamports: 0, computeUnitLimit: computeUnitLimit,
                              loadedAccountsDataSizeLimit: loadedAccountsDataSizeLimit, heapSize: heapSize)
        }
    }
}
