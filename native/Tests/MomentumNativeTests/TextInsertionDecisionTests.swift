import Testing
@testable import MomentumNative

@Suite("TextInsertionDecision")
struct TextInsertionDecisionTests {
    private static let range = AXTextRange(location: 5, length: 0)

    // MARK: countChanged / rangeChanged

    @Test func nothingChangedReportsNoChange() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(!TextInsertionDecision.countChanged(before: reading, after: reading))
        #expect(!TextInsertionDecision.rangeChanged(before: reading, after: reading))
    }

    @Test func countChangedDetectsIncreaseAndDecrease() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(TextInsertionDecision.countChanged(before: before, after: AXTextReading(characterCount: 15, selectedRange: Self.range)))
        #expect(TextInsertionDecision.countChanged(before: before, after: AXTextReading(characterCount: 5, selectedRange: Self.range)))
    }

    @Test func rangeChangedDetectsLocationAndLengthChange() {
        let before = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 5, length: 3))
        #expect(TextInsertionDecision.rangeChanged(before: before, after: AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 9, length: 3))))
        #expect(TextInsertionDecision.rangeChanged(before: before, after: AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 5, length: 0))))
    }

    @Test func changesIgnoreAttributesUnreadableOnOneSide() {
        // Count only before, range only after: nothing comparable.
        let before = AXTextReading(characterCount: 10, selectedRange: nil)
        let after = AXTextReading(characterCount: nil, selectedRange: Self.range)
        #expect(!TextInsertionDecision.countChanged(before: before, after: after))
        #expect(!TextInsertionDecision.rangeChanged(before: before, after: after))
        #expect(!TextInsertionDecision.countChanged(before: before, after: .unreadable))
    }

    // MARK: verificationResult

    private static func verify(
        _ before: AXTextReading,
        _ after: AXTextReading,
        inserted: Int = 15,
        focus: FocusObservation = .same,
        timedOut: Bool
    ) -> InsertResult? {
        TextInsertionDecision.verificationResult(
            before: before,
            after: after,
            insertedLength: inserted,
            focus: focus,
            timedOut: timedOut
        )
    }

    @Test(arguments: [false, true])
    func unreadableBeforeIsUnknown(timedOut: Bool) {
        let after = AXTextReading(characterCount: 42, selectedRange: Self.range)
        #expect(Self.verify(.unreadable, after, timedOut: timedOut) == .unknown)
    }

    @Test(arguments: [false, true])
    func countDeltaMatchingPasteIsConfirmed(timedOut: Bool) {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 25, selectedRange: AXTextRange(location: 20, length: 0))
        #expect(Self.verify(before, after, inserted: 15, timedOut: timedOut) == .confirmed)
    }

    @Test func pasteOverSelectionIsConfirmedWhenDeltaAccountsForSelection() {
        // 100 chars fully selected, 12 pasted → 12 chars (delta -88).
        let before = AXTextReading(characterCount: 100, selectedRange: AXTextRange(location: 0, length: 100))
        let after = AXTextReading(characterCount: 12, selectedRange: AXTextRange(location: 12, length: 0))
        #expect(Self.verify(before, after, inserted: 12, timedOut: false) == .confirmed)
    }

    @Test func unrelatedCountChangeIsNeverConfirmed() {
        // The count changed, but not by the pasted length (e.g. live text).
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 25, selectedRange: Self.range)
        #expect(Self.verify(before, after, inserted: 7, timedOut: false) == nil)
        #expect(Self.verify(before, after, inserted: 7, timedOut: true) == .unknown)
    }

    @Test(arguments: [false, true])
    func focusChangeIsUnknownEvenWithMatchingDelta(timedOut: Bool) {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 25, selectedRange: Self.range)
        #expect(Self.verify(before, after, inserted: 15, focus: .changed, timedOut: timedOut) == .unknown)
    }

    @Test func unreadableFocusKeepsPollingAndCanStillConfirm() {
        // A nil focus read (target busy with ⌘V, AX timeout) is not a focus change.
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(Self.verify(before, before, focus: .unreadable, timedOut: false) == nil)
        let after = AXTextReading(characterCount: 25, selectedRange: AXTextRange(location: 20, length: 0))
        #expect(Self.verify(before, after, inserted: 15, focus: .unreadable, timedOut: false) == .confirmed)
    }

    @Test func unreadableFocusAtDeadlineIsUnknown() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(Self.verify(before, before, focus: .unreadable, timedOut: true) == .unknown)
    }

    @Test func focusObservationMapsNilToUnreadable() {
        #expect(FocusObservation.from(currentFocusMatches: nil) == .unreadable)
        #expect(FocusObservation.from(currentFocusMatches: true) == .same)
        #expect(FocusObservation.from(currentFocusMatches: false) == .changed)
    }

    @Test func rangeOnlyChangeIsNeverConfirmed() {
        // A caret move without a text change must not restore the clipboard
        // (that would drop the only copy of the transcript).
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        let after = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 20, length: 0))
        #expect(Self.verify(before, after, timedOut: false) == nil)
        #expect(Self.verify(before, after, timedOut: true) == .unknown)
    }

    @Test func unchangedAndNotTimedOutKeepsPolling() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(Self.verify(reading, reading, timedOut: false) == nil)
    }

    @Test func unchangedAndTimedOutFails() {
        let reading = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(Self.verify(reading, reading, timedOut: true) == .failed(.pasteNotDetected))
    }

    @Test func onlyCountReadableAndMatchingDeltaIsConfirmed() {
        let before = AXTextReading(characterCount: 3, selectedRange: nil)
        let after = AXTextReading(characterCount: 8, selectedRange: nil)
        #expect(Self.verify(before, after, inserted: 5, timedOut: false) == .confirmed)
    }

    @Test func onlyRangeReadableAndChangedIsUnknownOnTimeout() {
        let before = AXTextReading(characterCount: nil, selectedRange: Self.range)
        let after = AXTextReading(characterCount: nil, selectedRange: AXTextRange(location: 11, length: 0))
        #expect(Self.verify(before, after, timedOut: false) == nil)
        #expect(Self.verify(before, after, timedOut: true) == .unknown)
    }

    @Test func onlyCountReadableAndUnchangedIsUnknownOnTimeout() {
        // Without a selected range a same-length replacement looks like no
        // paste at all, so it cannot be reported as a failure.
        let reading = AXTextReading(characterCount: 3, selectedRange: nil)
        #expect(Self.verify(reading, reading, timedOut: false) == nil)
        #expect(Self.verify(reading, reading, timedOut: true) == .unknown)
    }

    @Test func onlyRangeReadableAndUnchangedFailsOnTimeout() {
        let reading = AXTextReading(characterCount: nil, selectedRange: Self.range)
        #expect(Self.verify(reading, reading, timedOut: false) == nil)
        #expect(Self.verify(reading, reading, timedOut: true) == .failed(.pasteNotDetected))
    }

    @Test func readableBeforeButUnreadableAfterFailsOnTimeout() {
        let before = AXTextReading(characterCount: 10, selectedRange: Self.range)
        #expect(Self.verify(before, .unreadable, timedOut: false) == nil)
        #expect(Self.verify(before, .unreadable, timedOut: true) == .failed(.pasteNotDetected))
    }

    @Test func expectedDeltaSubtractsSelection() {
        let withSelection = AXTextReading(characterCount: 10, selectedRange: AXTextRange(location: 2, length: 4))
        #expect(TextInsertionDecision.expectedCountDelta(insertedLength: 6, before: withSelection) == 2)
        let noRange = AXTextReading(characterCount: 10, selectedRange: nil)
        #expect(TextInsertionDecision.expectedCountDelta(insertedLength: 6, before: noRange) == 6)
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
