import Testing
import Vault

struct RecoveryTests {
    @Test
    func `Recovery descriptions omit the phrase and passphrase`() throws {
        let recovery = try Fixtures.recovery()

        #expect(String(describing: recovery) == "Recovery")
        #expect(String(reflecting: recovery) == "Recovery")
        #expect(Mirror(reflecting: recovery).children.isEmpty)
    }
}
