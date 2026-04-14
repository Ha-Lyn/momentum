import { ChildProcess, spawn } from 'node:child_process';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { app, systemPreferences } from 'electron';

export class AudioRecorder {
  private ffmpegProcess: ChildProcess | null = null;
  private recording = false;
  private currentFilePath: string = '';

  constructor() {}

  async requestMicrophoneAccess() {
    if (process.platform === 'darwin') {
      const status = systemPreferences.getMediaAccessStatus('microphone');
      if (status !== 'granted') {
        const granted = await systemPreferences.askForMediaAccess('microphone');
        if (!granted) {
          throw new Error('Microphone access denied by user');
        }
      }
    }
  }

  startCapture() {
    if (this.recording) return;

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const dirPath = path.join(app.getPath('documents'), 'Momentum Eigenvalues');
    if (!fs.existsSync(dirPath)) {
      fs.mkdirSync(dirPath, { recursive: true });
    }
    this.currentFilePath = path.join(dirPath, `momentum-capture-${timestamp}.wav`);
    //Testing on dev mode
    //this.currentFilePath = path.join(dirPath, 'test.wav');

    console.log(`[AudioRecorder] Starting microphone capture via ffmpeg...`);

    // Use ffmpeg to record from the default macOS audio input device
    // -f avfoundation: macOS audio/video capture framework
    // -i ":0": default audio input device (colon prefix = audio-only)
    // -ar 16000: 16kHz sample rate (ideal for speech recognition)
    // -ac 1: mono channel
    // -y: overwrite output without asking
    const ffmpegPath = app.isPackaged
      ? path.join(process.resourcesPath, 'bin', 'ffmpeg')
      : path.join(app.getAppPath(), 'bin', 'ffmpeg');

    this.ffmpegProcess = spawn(ffmpegPath, [
      '-f', 'avfoundation',
      '-i', ':0',
      '-ar', '16000',
      '-ac', '1',
      '-y',
      this.currentFilePath,
    ]);

    this.ffmpegProcess.stderr?.on('data', (data: Buffer) => {
      // ffmpeg writes all status output to stderr — this is normal
      console.log(`[ffmpeg] ${data.toString().trim()}`);
    });

    this.ffmpegProcess.on('error', (err) => {
      console.error('[AudioRecorder] Failed to start ffmpeg:', err.message);
      this.recording = false;
    });

    this.ffmpegProcess.on('close', (code) => {
      console.log(`[AudioRecorder] ffmpeg process exited with code ${code}`);
      this.ffmpegProcess = null;
    });

    this.recording = true;
    console.log(`[AudioRecorder] Recording to ${this.currentFilePath}`);
  }

  stopCapture(): Promise<string> {
    return new Promise((resolve, reject) => {
      if (!this.recording || !this.ffmpegProcess) {
        return reject(new Error('Not recording'));
      }

      this.recording = false;

      // Send 'q' to ffmpeg's stdin to gracefully stop recording
      // This allows ffmpeg to finalize the WAV file headers properly
      this.ffmpegProcess.stdin?.write('q');

      this.ffmpegProcess.on('close', () => {
        console.log(`[AudioRecorder] Stopped recording. Saved to ${this.currentFilePath}`);
        
        console.log(`[Transcription] Starting transcription...`);
        const pythonProcess = spawn('uv run', [
          path.join(app.getAppPath(), 'scripts', 'transcribe.py'),
          this.currentFilePath
        ]);

        let transcriptText = '';

        pythonProcess.stdout.on('data', (data) => {
          const text = data.toString();
          console.log(`[Transcription] ${text.trim()}`);
          transcriptText += text;
        });

        pythonProcess.stderr.on('data', (data) => {
          console.error(`[Transcription Error] ${data.toString().trim()}`);
        });

        pythonProcess.on('close', (code) => {
          if (code !== 0) {
            console.log(`[Transcription] Process exited with code ${code}`);
          } else {
            console.log(`[Transcription] Completed successfully.`);
          }
          // Resolve with the file path once transcription is completed
          resolve(this.currentFilePath);
        });
      });

      // Safety timeout — force kill if ffmpeg hangs
      setTimeout(() => {
        if (this.ffmpegProcess) {
          this.ffmpegProcess.kill('SIGKILL');
          this.ffmpegProcess = null;
        }
      }, 5000);
    });
  }
}

export const recorder = new AudioRecorder();
