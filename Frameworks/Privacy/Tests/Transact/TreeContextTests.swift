@testable import Privacy
import Testing

/// Verifies the encoding of tree contexts.
struct TreeContextTests {
    /// Verifies that both root positions are written as little-endian 16-bit integers, UTXO tree
    /// first.
    @Test
    func `Contexts write both root positions little-endian`() {
        var writer = WincodeWriter()
        TreeContext(utxoTreeRootIndex: 0x0102, nullifierTreeRootIndex: 0xfffe).write(to: &writer)

        #expect(writer.bytes == [0x02, 0x01, 0xfe, 0xff])
    }
}
