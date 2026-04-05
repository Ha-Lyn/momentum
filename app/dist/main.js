"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const tray_1 = require("./tray");
// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (require('electron-squirrel-startup')) {
    electron_1.app.quit();
}
let tray = null;
electron_1.app.whenReady().then(() => {
    // Phase 1: Hide from macOS Dock
    if (electron_1.app.dock) {
        electron_1.app.dock.hide();
    }
    // Phase 1: Implement System Tray
    tray = (0, tray_1.setupTray)();
    // NOTE: Phase 2 will implement the Floating Record Button UI here.
    // We keep the app running through the Tray and do not spawn a default window.
});
// For a menubar-only background app, we typically don't quit when windows close,
// since we want it running in the background until the user explicitly quits via Tray.
electron_1.app.on('window-all-closed', () => {
    // No-op
});
