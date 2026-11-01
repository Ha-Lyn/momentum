import Testing
@testable import MomentumNative

@Suite("TextInsertionDecision")
struct TextInsertionDecisionTests {
    private static let range = AXTextRange(location: 5, length: 0)

    // MARK: didChange

    @Test func didChangeIsFalseWhenNothingChanged() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(!TextInsertionDecision.didChange(before: reading, after: reading))
    }

    @Test func didChangeDetectsCountChange() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 15, selectedRange: Self.range)
        #expect(TextInsertionDecision.didChange(before: before, after: after))
    }

    @Test func didChangeDetectsCountDecrease() {
        let before = AXTextReading(characterCount: 20, selectedRange: AXTextRange(location: 0, length: 20))
        let after = AXTextReading(characterCount: 5, selectedRange: AXTextRange(location: 0, length: 20))
        #expect(TextInsertionDecision.didChange(before: before, after: after))
    }

    @Test func didChangeDetectsRangeChange() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 9, length: 0))
        #expect(TextInsertionDecision.didChange(before: before, after: after))
    }

    @Test func didChangeDetectsRangeLengthChange() {
        let before = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 5, length: 3))
        let after = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 5, length: 0))
        #expect(TextInsertionDecision.didChange(before: before, after: after))
    }

    @Test func didChangeIgnoresAttributesUnreadableOnOneSide() {
        // Count only before, range only after: nothing comparable.
        let before = AXTextReading(characterCount: 10, selectedRange: nil)
        let after = AXTextReading(characterCount: nil, selectedRange: Self.range)
        #expect(!TextInsertionDecision.didChange(before: before, after: after))
    }

    @Test func didChangeIsFalseWhenAfterIsUnreadable() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(!TextInsertionDecision.didChange(before: before, after: .unreadable))
    }

    // MARK: verificationResult

    @Test(arguments: [false, true])
    func unreadableBeforeIsUnknown(timedOut: Bool) {
        let after = AXTextReading(characterCount: 42, selectedRange: Self.range)
        #expect(
            TextInsertionDecision.verificationResult(before: .unreadable, after: after, timedOut: timedOut)
                == .unknown
        )
    }

    @Test(arguments: [false, true])
    func countChangedIsConfirmed(timedOut: Bool) {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 25, selectedRange: Self.range)
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: after, timedOut: timedOut)
                == .confirmed
        )
    }

    @Test func rangeChangedIsConfirmed() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 20, length: 0))
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: after, timedOut: false)
                == .confirmed
        )
    }

    @Test func pasteOverSelectionShrinkingTextIsConfirmed() {
        let before = AXTextReading(characterCount: 100, selectedRange: AXTextRange(location: 0, length: 100))
        let after = AXTextReading(characterCount: 12, selectedRange: AXTextRange(location: 12, length: 0))
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: after, timedOut: false)
                == .confirmed
        )
    }

    @Test func unchangedAndNotTimedOutKeepsPolling() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(
            TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: false) == nil
        )
    }

    @Test func unchangedAndTimedOutFails() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(
            TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: true)
                == .failed(.pasteNotDetected)
        )
    }

    @Test func onlyCountReadableAndChangedIsConfirmed() {
        let before = AXTextReading(characterCount: 3, selectedRange: nil)
        let after = AXTextReading(characterCount: 8, selectedRange: nil)
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: after, timedOut: false)
                == .confirmed
        )
    }

    @Test func onlyRangeReadableAndChangedIsConfirmed() {
        let before = AXTextReading(characterCount: nil, selectedRange: Self.range)
        let after = AXTextReading(characterCount: nil, selectedRange: AXTextRange(location: 11, length: 0))
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: after, timedOut: false)
                == .confirmed
        )
    }

    @Test func onlyCountReadableAndUnchangedFailsOnTimeout() {
        let reading = AXTextReading(characterCount: 3, selectedRange: nil)
        #expect(TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: false) == nil)
        #expect(
            TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: true)
                == .failed(.pasteNotDetected)
        )
    }

    @Test func onlyRangeReadableAndUnchangedFailsOnTimeout() {
        let reading = AXTextReading(characterCount: nil, selectedRange: Self.range)
        #expect(TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: false) == nil)
        #expect(
            TextInsertionDecision.verificationResult(before: reading, after: reading, timedOut: true)
                == .failed(.pasteNotDetected)
        )
    }

    @Test func readableBeforeButUnreadableAfterFailsOnTimeout() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(TextInsertionDecision.verificationResult(before: before, after: .unreadable, timedOut: false) == nil)
        #expect(
            TextInsertionDecision.verificationResult(before: before, after: .unreadable, timedOut: true)
                == .failed(.pasteNotDetected)
        )
    }

    // MARK: AXTextReading

    @Test func readabilityRequiresAtLeastOneAttribute() {
        #expect(!AXTextReading.unreadable.isReadable)
        #expect(AXTextReading(characterCount: 0, selectedRange: nil).isReadable)
        #expect(AXTextReading(characterCount: nil, selectedRange: AXTextRange(location: 0, length: 0)).isReadable)
    }

    // MARK: clipboardAction

    @Test func confirmedRestoresSnapshot() {
        #expect(
            TextInsertionDecision.clipboardAction(for: .confirmed, currentChangeCount: 7, writtenChangeCount: 7)
                == .restoreSnapshot
        )
    }

    @Test(arguments: [
        InsertResult.unknown,
        .failed(.pasteNotDetected),
        .failed(.eventPostFailed),
        .failed(.noAccessibilityPermission),
        .failed(.secureInputActive),
        .failed(.targetAppTerminated),
        .failed(.targetActivationFailed),
    ])
    func failedOrUnknownKeepsTranscript(result: InsertResult) {
        #expect(
            TextInsertionDecision.clipboardAction(for: result, currentChangeCount: 7, writtenChangeCount: 7)
                == .keepTranscript
        )
    }

    @Test(arguments: [InsertResult.confirmed, .unknown, .failed(.pasteNotDetected)])
    func changeCountMismatchLeavesClipboardAlone(result: InsertResult) {
        #expect(
            TextInsertionDecision.clipboardAction(for: result, currentChangeCount: 8, writtenChangeCount: 7)
                == .leaveAlone
        )
    }
}
