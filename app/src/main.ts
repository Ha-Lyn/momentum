import { app, globalShortcut, BrowserWindow, systemPreferences } from 'electron';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { setupTray } from './tray';
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
  // Phase 3 Minor: Allow user to alter the Icon and name on dock by overriding default.
  // It only triggers if icon.svg is present in the parent directory.
  const iconPath = path.join(app.getAppPath(), 'icon.svg');
  if (app.dock && fs.existsSync(iconPath)) {
    // Note: dock.setIcon usually expects png/icns, but will attempt to map the svg or bypass if compatible
    app.dock.setIcon(iconPath);
  }

  // Phase 1: Hide from macOS Dock 
  // (Left intact based on 'leave the electron icon only if icon.svg does not exist' request,
  // meaning we might show the dock in dev/usage or leave it running headless as designed).
  if (app.dock) {
    app.dock.hide();
  }

  // Phase 3: Hardware Microphone Permissions Check
  try {
    await recorder.requestMicrophoneAccess();
  } catch (e) {
    console.warn("Microphone access not granted.", e);
  }

  // Phase 1: Implement System Tray
  tray = setupTray();
  
  // Phase 2: Implement Floating Record Feature
  const floatingWin = createFloatingWindow();

  // Phase 2/3: Register Global Shortcut mapping to the Audio Buffer pipeline
  globalShortcut.register('CommandOrControl+Shift+Space', () => {
    isRecording = !isRecording;
    
    if (isRecording) {
      floatingWin.showInactive(); 
      floatingWin.webContents.send('recording-state', { active: true });
      
      // Phase 3: Start Node Record Audio capture
      recorder.startCapture();
    } else {
      floatingWin.webContents.send('recording-state', { active: false });
      
      // Phase 3: Stop Audio Buffer
      recorder.stopCapture().then((wavFilePath) => {
        console.log('Capture finished, ready for pipeline:', wavFilePath);
        // Phase 4+ will pick up this file
      }).catch(console.error);

      // Wait for UI animation duration then hide
      setTimeout(() => floatingWin.hide(), 400); 
    }
  });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  // No-op for menubar
});
