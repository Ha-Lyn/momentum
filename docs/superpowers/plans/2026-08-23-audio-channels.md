# Audio Channels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture microphone input and all system output as separate local audio files and independently transcribe both selected channels.

**Architecture:** Keep microphone capture in `AVAudioRecorder`, add a native `SCStream` output-audio recorder, and let `CaptureCoordinator` manage both through channel-specific capture sessions. Persist independently selectable channels in `UserDefaults`; each channel produces a prefixed audio file and matching transcription sidecars.

**Tech Stack:** Swift 6, macOS 14+, AppKit, AVFoundation, ScreenCaptureKit, FluidAudio.

## Global Constraints

- Output capture uses native `SCStream`; no virtual audio driver or third-party capture dependency.
- Permission is requested during launch only, never when recording starts.
- New installations default to Input only; the last channel selection is persisted.
- Input and Output are always written and transcribed as separate files.
- A channel failure must not discard a successful channel's recording or transcript.
- Audio files use `input-momentum-capture-<timestamp>.m4a` and `output-momentum-capture-<timestamp>.m4a`.

---

## File Map

- Create: `native/Sources/MomentumNative/AudioChannel.swift` for channel identity and persisted selection.
- Create: `native/Sources/MomentumNative/OutputAudioRecorder.swift` for ScreenCaptureKit lifecycle and AAC file writing.
- Modify: `native/Sources/MomentumNative/AudioRecorder.swift` to accept a channel and shared timestamp in filenames.
- Modify: `native/Sources/MomentumNative/CaptureCoordinator.swift` to start/stop selected channels and process results independently.
- Modify: `native/Sources/MomentumNative/AppDelegate.swift` to request output access at launch and add the Options > Audio Channels menu.
- Modify: `native/Info.plist` to declare system-audio capture usage text.
- Modify: `native/README.md` and root `README.md` to document output capture and permissions.

### Task 1: Channel Model And Input Naming

**Files:**
- Create: `native/Sources/MomentumNative/AudioChannel.swift`
- Modify: `native/Sources/MomentumNative/AudioRecorder.swift`

**Interfaces:**
- Produce `enum AudioChannel: String, CaseIterable, Codable` with `.input` and `.output`.
- Produce `AudioChannelSelection` methods that load and persist `[AudioChannel]` using `UserDefaults`, defaulting to `[.input]`.
- Change input start to `startCapture(timestamp: Date) throws` and derive `input-momentum-capture-<timestamp>.m4a`.

- [ ] Add the enum, display titles, and stable UserDefaults key.
- [ ] Implement load fallback to Input only and persist a sorted array of raw values.
- [ ] Add the timestamp parameter and input prefix to `AudioRecorder`.
- [ ] Run `swift build` and verify the existing input recorder still compiles.
- [ ] Commit with `feat: add persisted audio channel selection`.

### Task 2: ScreenCaptureKit Output Recorder

**Files:**
- Create: `native/Sources/MomentumNative/OutputAudioRecorder.swift`

**Interfaces:**
- Produce `@MainActor final class OutputAudioRecorder` with `requestAccess() async throws`, `startCapture(timestamp: Date) throws`, and `stopCapture() async throws -> URL`.
- Use `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` to obtain a display, create `SCContentFilter(display:excludingWindows:)`, enable `capturesAudio`, disable video dimensions, and add an `SCStreamOutput` for `.audio`.
- Write each audio sample buffer to an `AVAudioFile` at the stream's format, converting to the configured mono 16 kHz AAC file format when required.

- [ ] Define localized errors for permission denial, unavailable display content, stream setup failure, not recording, and invalid output.
- [ ] Implement launch-time access probing without prompting from `startCapture`.
- [ ] Implement an `SCStreamOutput` receiver that ignores video and writes audio sample buffers only.
- [ ] Ensure stop resumes exactly once, closes the file, stops the stream, removes the output, and clears references on success and failure.
- [ ] Run `swift build` and fix all Swift 6 concurrency diagnostics.
- [ ] Commit with `feat: capture system audio with ScreenCaptureKit`.

### Task 3: Coordinator Multi-Channel Lifecycle

**Files:**
- Modify: `native/Sources/MomentumNative/CaptureCoordinator.swift`

**Interfaces:**
- Add `selectedAudioChannels() -> Set<AudioChannel>` and `setAudioChannel(_:enabled:)`.
- Change `startCapture() throws` to start all selected recorders with one timestamp.
- Change `stopCapture() async -> [CaptureResult]` or an equivalent result structure that records per-channel success and error without aborting the batch.

- [ ] Validate at least one channel before starting.
- [ ] Start selected input and output recorders, rolling back any recorder already started if another selected recorder cannot start.
- [ ] Stop all active recorders concurrently and retain every successful URL.
- [ ] Transcribe each successful URL independently using the existing language snapshot.
- [ ] Write a transcription-error sidecar for each failed transcription and return/log successful channel results.
- [ ] Run `swift build` and verify input-only behavior remains unchanged.
- [ ] Commit with `feat: coordinate independent audio channel captures`.

### Task 4: Options Menu And Permission Initialization

**Files:**
- Modify: `native/Sources/MomentumNative/AppDelegate.swift`
- Modify: `native/Info.plist`

**Interfaces:**
- Add `Options > Audio Channels > Input/Output` with checkmarks backed by the coordinator selection.
- Add launch initialization for microphone and ScreenCaptureKit access; do not request either permission from the record toggle.

- [ ] Add menu item references and channel submenu construction.
- [ ] Disable channel menu items while recording and refresh their checkmarks/title after changes.
- [ ] Reject a zero-channel selection with a user-facing alert and restore the previous valid selection.
- [ ] Keep Input usable when Output access is denied; show the output error in the launch alert/menu state.
- [ ] Add the required Screen Recording/system-audio usage declaration without changing the existing microphone declaration's purpose.
- [ ] Run `swift build` and build the `.app` bundle.
- [ ] Commit with `feat: add audio channel options`.

### Task 5: Documentation And Verification

**Files:**
- Modify: `native/README.md`
- Modify: `README.md`

- [ ] Document Input and Output channel selection, persisted defaults, separate filenames, and the launch permission requirement.
- [ ] Run `swift build`.
- [ ] Run `./scripts/build-app.sh` from `native`.
- [ ] Manually verify Input-only, Output-only, and combined recordings, including a playing video in Output.
- [ ] Verify matching `.md` filenames and independent transcription-error sidecars.
- [ ] Verify that changing channels while recording is disabled and that selection survives relaunch.
- [ ] Commit with `docs: document audio channel capture`.
