import { app, BrowserWindow } from 'electron';
import * as path from 'node:path';
import { setupTray } from './tray';

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (require('electron-squirrel-startup')) {
  app.quit();
}

let tray = null;

app.whenReady().then(() => {
  // Phase 1: Hide from macOS Dock
  if (app.dock) {
    app.dock.hide();
  }

  // Phase 1: Implement System Tray
  tray = setupTray();
  
  // NOTE: Phase 2 will implement the Floating Record Button UI here.
  // We keep the app running through the Tray and do not spawn a default window.
});

// For a menubar-only background app, we typically don't quit when windows close,
// since we want it running in the background until the user explicitly quits via Tray.
app.on('window-all-closed', () => {
  // No-op
});
