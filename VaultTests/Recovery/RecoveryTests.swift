import Testing
import Vault

/// Verifies the recovery value from outside the framework's access boundary.
struct RecoveryTests {
    /// Verifies that ordinary descriptions and reflection don't reveal backup secrets.
    @Test("recovery descriptions omit the phrase and passphrase")
    func recoveryDescriptionsOmitThePhraseAndPassphrase() throws {
        let recovery = try Fixtures.recovery()

        #expect(String(describing: recovery) == "Recovery")
        #expect(String(reflecting: recovery) == "Recovery")
        #expect(Mirror(reflecting: recovery).children.isEmpty)
    }
}
