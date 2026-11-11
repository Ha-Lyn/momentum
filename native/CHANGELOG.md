# Changelog

## Unreleased — Remove the Electron prototype

### Removed

- The Electron prototype in `app/` (sources, Forge config, npm manifests,
  ffmpeg download script and Python transcription helper). The native Swift
  app is the only implementation.
- Electron and Node.js entries in `.gitignore`, and the prototype references
  in the README.

## Unreleased — macOS app and menu bar icons

### Added

- `Resources/AppIcon.icns`, declared through `CFBundleIconFile`: a rounded
  tile with margin and shadow following the macOS icon grid, so Finder and
  `/Applications` show the app icon.
- Menu bar icon: a monochrome template version of the logo
  (`Resources/MenuBarIcon.tiff`) that adapts to light and dark menu bars.
  Recording still shows `stop.circle.fill`.
- `scripts/make-icon.py` and `scripts/make-menubar-icon.py` regenerate both
  icons from `Resources/P1.png`.

### Changed

- The Dock icon is no longer overridden at launch with the square `P1.png`;
  the bundled icon is used, and the override only applies to unbundled
  `swift run` builds.

## Unreleased — Quick Transcribe (push-to-talk dictation)

### Added

- Quick Transcribe: hold `Option + Shift` to record the microphone, release to
  transcribe locally and paste the text into the focused app. Audio is kept in
  memory (`MicrophoneBufferRecorder`, 16 kHz mono) and nothing is saved.
- Customizable push-to-talk shortcut (`PushToTalkShortcut`), persisted in
  user defaults. Modifier-only shortcuts are detected with NSEvent monitors
  and a 200 ms arm delay (a key press or click cancels, so normal
  `Option + Shift + key` shortcuts keep working); modifiers + key shortcuts
  use a Carbon hotkey with pressed/released events.
- "Quick Transcribe Shortcut" window (`ShortcutRecorderWindowController`)
  opened from the status menu: shows the current shortcut, records a new
  one (modifier-only or modifiers + key, Esc cancels) and restores the
  default. Global shortcuts are paused while recording so the keys do not
  trigger a dictation or a note recording.
- `TextInserter`: pastes through the clipboard with a synthesized
  `Command + V` and verifies the result through the focused element's
  Accessibility attributes. The previous clipboard is restored only when the
  paste is confirmed; otherwise the transcript stays on the clipboard and the
  pill asks the user to press `Command + V`.
- `AccessibilityPermission`: lazy Accessibility request (never at launch),
  a deep link to System Settings and polling so the shortcut starts working as
  soon as access is granted (and stops if it is revoked).
- Status menu items: "Quick Transcribe" toggle, "Quick Transcribe Shortcut…"
  and "Grant Accessibility Access…" (only while access is missing).
- Floating pill states for listening, transcribing and short auto-hiding
  messages. Quick Transcribe errors are shown there instead of alerts, so
  focus never leaves the target app.

### Changed

- A single `TranscriptionService` (one model instance) is shared by note
  capture and Quick Transcribe; model loading is deduplicated, prewarmed at
  launch and transcriptions are serialized. New
  `transcribe(samples:language:)` API for in-memory audio.
- `HotKeyManager` supports multiple hotkeys with press and release handlers.
- Note capture and Quick Transcribe are mutually exclusive: push-to-talk is
  ignored during a note recording, and Start Recording / `Command + Shift +
  Space` are ignored while a quick transcription is running.

## Unreleased — CoreAudio process taps replace Screen Recording

### Fixed

- The app is now signed with a `com.apple.security.device.audio-input`
  entitlement (`MomentumNative.entitlements`). The hardened runtime requires
  it for microphone and system audio access; without it TCC silently refused
  to even show the permission prompts.
- Fixed a crash (`EXC_BREAKPOINT` in `dispatch_assert_queue`) when starting a
  recording: the CoreAudio IO callback was created inside a `@MainActor`
  method, so Swift 6 tagged it main-actor-isolated and trapped when CoreAudio
  invoked it on its IO thread. The callback is now built in a nonisolated
  context.

### Changed

- System audio capture now uses CoreAudio process taps
  (`AudioHardwareCreateProcessTap` + aggregate device) instead of
  ScreenCaptureKit. The app now only needs the lightweight "System Audio
  Recording Only" permission (System Settings > Privacy & Security > Screen &
  System Audio Recording) instead of full Screen Recording, and no longer
  captures any video.
- The tap is a mono global mixdown of all processes, so no stereo-to-mono
  conversion is needed before transcription.
- Minimum macOS version raised from 14.0 to 15.0 (the dedicated system-audio
  permission requires macOS 14.4+).
- `Info.plist` uses `NSAudioCaptureUsageDescription` instead of
  `NSScreenCaptureUsageDescription`.
- Xcode user data (`xcuserdata/`, `.xcuserstate`), SwiftPM build output, and
  `native/dist/` are now git-ignored.

## 2026-08-29 — Output audio channel (system audio capture)

### Added

- Output audio channel: Momentum can now record the computer's output audio
  (videos, lectures, calls) alongside or instead of the microphone, using
  ScreenCaptureKit. Enable it under Options > Audio Channels.
- Channel selection is persisted between launches and defaults to Input only.
- Each channel is captured to its own file (`input-*` / `output-*`) and
  receives its own Markdown transcription.
- `CHANGELOG.md` (this file).

### Fixed

- Screen Recording permission no longer "resets" after every rebuild.
  `scripts/build-app.sh` now auto-detects a codesigning identity
  (Developer ID or Apple Development) when `CODESIGN_IDENTITY` is not set.
  Ad-hoc signed builds are identified by binary hash in macOS's TCC database,
  so each rebuild invalidated previously granted permissions; signing with a
  real certificate gives the app a stable identity (bundle ID + certificate).
- `OutputAudioRecorder` retains its `SCStreamOutput` receiver.
  `SCStream.addStreamOutput` only holds a weak reference, so the receiver was
  deallocated immediately and every audio frame was dropped
  ("streamOutput NOT found").
- Multi-channel PCM copy: `CMSampleBufferCopyPCMDataIntoAudioBufferList` now
  receives the `AVAudioPCMBuffer`'s own buffer-list pointer. The previous
  stack copy truncated the variable-length `AudioBufferList` to one
  `AudioBuffer`, which failed for the deinterleaved stereo buffers that
  system audio delivers.
- `AVAudioConverter` input block hands each buffer over exactly once and then
  reports `.noDataNow` instead of re-serving the same buffer.
- Screen Recording permission is re-checked at capture time instead of being
  cached at launch, so grants and revocations made while the app is running
  are respected (a relaunch is still required by macOS after granting).
- `stopCapture` fails with a clear error when no audio was captured instead
  of handing a nonexistent file to the transcription service.

### Changed

- Output captures are written as 16 kHz mono WAV (was AAC/m4a). Linear PCM
  writes land in the file immediately, with no encoder buffering or
  finalization step.
- Silent failure paths in the output audio pipeline now log publicly under
  the `com.momentum.native` subsystem (visible in Console.app / `log show`).
- Permission-denied errors explain that macOS applies Screen Recording
  grants only after the app is relaunched.
