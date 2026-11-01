import AppKit
import Foundation
import Testing
@testable import MomentumNative

@Suite("PasteboardSnapshot")
@MainActor
struct PasteboardSnapshotTests {
    private static let customType = NSPasteboard.PasteboardType("com.momentum.tests.custom")

    /// Runs `body` with a private named pasteboard and releases it afterwards.
    private func withPrivatePasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("momentum.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    private func representations(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var result: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                result[type] = item.data(forType: type)
            }
            return result
        }
    }

    @Test func roundTripPreservesMultipleItemsAndTypes() {
        withPrivatePasteboard { pasteboard in
            let first = NSPasteboardItem()
            first.setString("hello", forType: .string)
            first.setData(Data("<b>hello</b>".utf8), forType: .html)
            first.setData(Data([0x00, 0x01, 0xFF]), forType: Self.customType)

            let second = NSPasteboardItem()
            second.setString("https://example.com", forType: .URL)
            second.setString("second", forType: .string)

            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([first, second]))

            let original = representations(of: pasteboard)
            #expect(original.count == 2)

            let snapshot = PasteboardSnapshot(capturing: pasteboard)
            #expect(snapshot.items.count == 2)
            #expect(!snapshot.isEmpty)

            // Overwrite with something else, then restore.
            pasteboard.clearContents()
            pasteboard.setString("transcript", forType: .string)
            #expect(pasteboard.string(forType: .string) == "transcript")

            snapshot.restore(to: pasteboard)

            let restored = representations(of: pasteboard)
            #expect(restored == original)
            #expect(pasteboard.pasteboardItems?.first?.string(forType: .string) == "hello")
            #expect(pasteboard.pasteboardItems?.first?.data(forType: Self.customType) == Data([0x00, 0x01, 0xFF]))
            #expect(pasteboard.pasteboardItems?.last?.string(forType: .URL) == "https://example.com")
        }
    }

    @Test func emptyPasteboardSnapshotRestoresToEmpty() {
        withPrivatePasteboard { pasteboard in
            pasteboard.clearContents()

            let snapshot = PasteboardSnapshot(capturing: pasteboard)
            #expect(snapshot.isEmpty)

            pasteboard.setString("transcript", forType: .string)
            snapshot.restore(to: pasteboard)

            #expect((pasteboard.pasteboardItems ?? []).isEmpty)
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test func restoreSkipsItemsWithoutRepresentations() {
        withPrivatePasteboard { pasteboard in
            let snapshot = PasteboardSnapshot(items: [
                .init(representations: []),
                .init(representations: [(type: .string, data: Data("kept".utf8))]),
            ])
            #expect(!snapshot.isEmpty)

            snapshot.restore(to: pasteboard)

            #expect(pasteboard.pasteboardItems?.count == 1)
            #expect(pasteboard.string(forType: .string) == "kept")
        }
    }

    @Test func snapshotWithOnlyEmptyItemsIsEmpty() {
        let snapshot = PasteboardSnapshot(items: [.init(representations: []), .init(representations: [])])
        #expect(snapshot.isEmpty)
        #expect(PasteboardSnapshot(items: []).isEmpty)
    }
}
