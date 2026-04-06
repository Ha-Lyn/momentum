import { app, Tray, Menu, nativeImage } from 'electron';
import * as path from 'node:path';
import * as fs from 'node:fs';

let tray: Tray | null = null;

export interface TrayCallbacks {
  onToggleRecording: () => void;
}

export const setupTray = (callbacks: TrayCallbacks) => {
  // Load the P1.png icon and resize it for the menu bar (16x16 is standard)
  const iconPath = path.join(app.getAppPath(), 'P1.png');
  let icon: Electron.NativeImage;

  if (fs.existsSync(iconPath)) {
    icon = nativeImage.createFromPath(iconPath).resize({ width: 18, height: 18 });
    // Mark as template so macOS applies proper dark/light mode styling
    icon.setTemplateImage(true);
  } else {
    console.warn('[Tray] P1.png not found, falling back to text-only tray');
    icon = nativeImage.createEmpty();
  }

  tray = new Tray(icon);
  tray.setToolTip('Momentum - Flow state capture');

  updateTrayMenu(false, callbacks);

  return tray;
};

export const updateTrayMenu = (isRecording: boolean, callbacks: TrayCallbacks) => {
  if (!tray) return;

  const contextMenu = Menu.buildFromTemplate([
    { label: 'Momentum', enabled: false },
    { type: 'separator' },
    {
      label: isRecording ? '⏹ Stop Recording' : '🎙 Start Recording',
      click: () => callbacks.onToggleRecording(),
    },
    { type: 'separator' },
    { label: 'Quit Momentum', click: () => app.quit() },
  ]);

  tray.setContextMenu(contextMenu);
};
