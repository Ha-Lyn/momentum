import { app, globalShortcut } from 'electron';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { setupTray, updateTrayMenu, TrayCallbacks } from './tray';
import { createFloatingWindow } from './ui';
import { recorder } from './recorder';

// Set App Name to Momentum
app.setName('Momentum');

if (require('electron-squirrel-startup')) {
  app.quit();
}

let tray = null;
let isRecording = false;

app.whenReady().then(async () => {
  // Set the dock icon from the bundled P1.png
  const iconPath = path.join(app.getAppPath(), 'P1.png');
  if (app.dock && fs.existsSync(iconPath)) {
    app.dock.setIcon(iconPath);
  }

  // Hardware Microphone Permissions Check
  try {
    await recorder.requestMicrophoneAccess();
  } catch (e) {
    console.warn("Microphone access not granted.", e);
  }

  // Floating Record Indicator
  const floatingWin = createFloatingWindow();

  // Shared recording toggle logic (used by both shortcut and tray menu)
  const toggleRecording = () => {
    isRecording = !isRecording;

    if (isRecording) {
      floatingWin.showInactive();
      floatingWin.webContents.send('recording-state', { active: true });
      recorder.startCapture();
    } else {
      floatingWin.webContents.send('recording-state', { active: false });

      recorder.stopCapture().then((wavFilePath) => {
        console.log('[App] Capture saved at:', wavFilePath);
      }).catch(console.error);

      // Wait for UI animation duration then hide
      setTimeout(() => floatingWin.hide(), 400);
    }

    // Update tray menu to reflect current state
    updateTrayMenu(isRecording, trayCallbacks);
  };

  const trayCallbacks: TrayCallbacks = {
    onToggleRecording: toggleRecording,
  };

  // System Tray (with working recording toggle)
  tray = setupTray(trayCallbacks);

  // Global Shortcut for Audio Capture
  globalShortcut.register('CommandOrControl+Shift+Space', toggleRecording);
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  // No-op for menubar
});
