import { app, BrowserWindow, screen } from 'electron';
import * as path from 'node:path';

let floatingWindow: BrowserWindow | null = null;

export const createFloatingWindow = () => {
  if (floatingWindow) return floatingWindow;

  // Position at the bottom center of the screen
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;
  const winWidth = 240;
  const winHeight = 70;

  floatingWindow = new BrowserWindow({
    width: winWidth,
    height: winHeight,
    x: Math.round(width / 2 - winWidth / 2),
    y: Math.round(height - winHeight - 60), // 60px from bottom edge
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    resizable: false,
    hasShadow: false,
    hiddenInMissionControl: true,
    show: false, // Hidden until globally triggered
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });

  // Ensure it floats aggressively over even fullscreen apps
  floatingWindow.setAlwaysOnTop(true, 'floating');
  floatingWindow.setVisibleOnAllWorkspaces(true);
  floatingWindow.fullScreenable = false;

  floatingWindow.loadFile(path.join(__dirname, 'index.html'));

  return floatingWindow;
};

export const getFloatingWindow = () => floatingWindow;
