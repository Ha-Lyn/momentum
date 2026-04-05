export {}; // Mark as module to allow global augmentation

interface ElectronAPI {
  onRecordingState: (callback: (state: { active: boolean }) => void) => void;
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}

// Listen for global shortcut triggers from main process
window.electronAPI.onRecordingState((state) => {
  const pill = document.getElementById('record-pill');
  if (state.active) {
    pill?.classList.add('active');
  } else {
    pill?.classList.remove('active');
  }
});
