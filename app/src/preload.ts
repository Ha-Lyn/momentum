import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  onRecordingState: (callback: (state: { active: boolean }) => void) => {
    ipcRenderer.on('recording-state', (_event, value) => callback(value));
  }
});
