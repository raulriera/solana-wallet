import Testing
@testable import Privacy

struct TreeContextTests {
    @Test
    func `Contexts write both root positions little-endian`() {
        var writer = WincodeWriter()
        TreeContext(utxoTreeRootIndex: 0x0102, nullifierTreeRootIndex: 0xfffe).write(to: &writer)

        #expect(writer.bytes == [0x02, 0x01, 0xfe, 0xff])
    }
}
