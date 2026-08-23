# Audio Channels Design

## Goal

Allow Momentum to capture microphone input and all system output audio as
separate recordings, each independently transcribed by the local model.

## User Experience

The status-menu Options item contains an Audio Channels submenu with
independent Input and Output checkboxes. Preferences are persisted immediately;
new installations default to Input only. Channel changes are disabled while a
capture is active. The existing single recording action starts and stops every
selected channel.

Momentum requests microphone and ScreenCaptureKit access during launch, never
when recording starts. Output permission is requested once during launch. A
denied output permission does not prevent input capture, and the menu exposes
the resulting error clearly.

## Architecture

`AudioChannel` represents `.input` and `.output` and owns persistence of the
selected set through `UserDefaults`. `CaptureCoordinator` manages independent
recorders behind a common lifecycle instead of owning one recorder directly.

- Input uses the existing `AVAudioRecorder` implementation.
- Output uses a new native `SCStream` recorder with a display content filter
  and audio capture enabled. Video frames are ignored and never written.
- Output audio buffers are written to an AAC `.m4a` file suitable for the
  existing FluidAudio transcription service.

One capture operation uses one timestamp and creates independent files:

```text
input-momentum-capture-<timestamp>.m4a
output-momentum-capture-<timestamp>.m4a
```

Matching Markdown and transcription-error sidecars inherit the audio prefix.

## Lifecycle

At start, the coordinator validates that at least one channel is selected and
that selected recorders can initialize without prompting. Selected recorders
start as close together as their APIs allow. At stop, all active recorders are
stopped and awaited. Every completed file is transcribed independently. A
failure in one channel preserves the other channel's recording and result;
transcription failures write the existing error sidecar.

The output recorder must release its stream, delegate/output handler, file, and
continuations on both successful stop and failure. No channel selection change
is allowed while recording.

## Verification

- Swift package and app bundle build successfully.
- Input-only is the default and persists across launches.
- Input-only, output-only, and combined captures work.
- Audio and Markdown filenames have the correct channel prefixes.
- Independent transcription failures preserve successful channel output.
- Permission denial does not trigger a prompt during recording and does not
  block an independently permitted channel.
- Manual validation confirms a playing video is present in output audio and
  microphone speech is present in input audio.
