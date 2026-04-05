import record from 'node-record-lpcm16';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { app, systemPreferences } from 'electron';

export class AudioRecorder {
  private fileStream: fs.WriteStream | null = null;
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
    
    // Save to temp file
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    this.currentFilePath = path.join(app.getPath('temp'), `momentum-capture-${timestamp}.wav`);
    this.fileStream = fs.createWriteStream(this.currentFilePath);
    
    console.log(`[AudioRecorder] Starting microphone capture...`);
    
    // Initialize recording process via `rec` or `sox`
    // Ensure you have `sox` or standard recorder installed locally or fallback
    record.record({
      sampleRate: 16000,
      channels: 1,
      threshold: 0,
      // On macOS, 'rec' bindings usually rely heavily on system sox
      // but 'node-record-lpcm16' takes care of platform fallbacks generally
    }).stream().pipe(this.fileStream);
    
    this.recording = true;
    console.log(`[AudioRecorder] Audio stream streaming to ${this.currentFilePath}`);
  }

  stopCapture(): Promise<string> {
    return new Promise((resolve, reject) => {
      if (!this.recording) return reject(new Error('Not recording'));
      
      record.stop();
      this.recording = false;
      
      if (this.fileStream) {
        this.fileStream.end(() => {
          console.log(`[AudioRecorder] Stopped recording. Successfully saved to ${this.currentFilePath}`);
          resolve(this.currentFilePath);
        });
      } else {
        resolve(this.currentFilePath);
      }
    });
  }
}

export const recorder = new AudioRecorder();
