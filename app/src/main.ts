import { app, globalShortcut, BrowserWindow } from 'electron';
import * as path from 'node:path';
import { setupTray } from './tray';
import { createFloatingWindow } from './ui';

if (require('electron-squirrel-startup')) {
  app.quit();
}

let tray = null;
let isRecording = false;

app.whenReady().then(() => {
  // Phase 1: Hide from macOS Dock
  if (app.dock) {
    app.dock.hide();
  }

  // Phase 1: Implement System Tray
  tray = setupTray();
  
  // Phase 2: Implement Floating Record Feature
  const floatingWin = createFloatingWindow();

  // Phase 2: Register Global Shortcut (Cmd+Shift+Space)
  globalShortcut.register('CommandOrControl+Shift+Space', () => {
    isRecording = !isRecording;
    
    if (isRecording) {
      floatingWin.showInactive(); // Show without taking user focus away from their current task!
      floatingWin.webContents.send('recording-state', { active: true });
      // TODO (Phase 3): Start Audio Recording Buffer
    } else {
      floatingWin.webContents.send('recording-state', { active: false });
      // Wait for UI animation duration then hide
      setTimeout(() => floatingWin.hide(), 400); 
      // TODO (Phase 3): Stop Audio Recording Buffer and pass to Pipeline
    }
  });
});

app.on('will-quit', () => {
  // Unregister shortcuts cleanly when app shuts down
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {
  // No-op for menubar
});
