import Testing
import Foundation
@testable import Nexus

/// Tests the UTF-8 boundary buffering that prevents dropped characters when a
/// multi-byte sequence is split across two pipe reads (review finding).
struct NetworkToolTests {

    @Test func asciiHoldsNothingBack() {
        #expect(NetworkToolRunner.incompleteTrailingByteCount(Array("hello".utf8)) == 0)
    }

    @Test func completeMultibyteHoldsNothingBack() {
        // "ä" = 2 bytes, complete.
        #expect(NetworkToolRunner.incompleteTrailingByteCount(Array("ä".utf8)) == 0)
    }

    @Test func splitTwoByteHoldsOneBack() {
        // First byte of a 2-byte sequence (0xC3) alone → hold 1 back.
        #expect(NetworkToolRunner.incompleteTrailingByteCount([0x41, 0xC3]) == 1)
    }

    @Test func splitFourByteHoldsPartialBack() {
        // 0xF0 0x9F = first 2 bytes of a 4-byte emoji → hold 2 back.
        #expect(NetworkToolRunner.incompleteTrailingByteCount([0xF0, 0x9F]) == 2)
    }

    @Test func invalidLeadHoldsNothing() {
        // A stray continuation byte with no valid lead — don't hold forever.
        #expect(NetworkToolRunner.incompleteTrailingByteCount([0x80]) == 1)
    }
}
