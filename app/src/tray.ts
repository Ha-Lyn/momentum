import { app, Tray, Menu, nativeImage } from 'electron';

let tray: Tray | null = null;

export const setupTray = () => {
  // Create an empty image for the tray icon until we have a real icon
  const icon = nativeImage.createEmpty();
  
  tray = new Tray(icon);
  tray.setTitle('M'); // Represents Momentum
  
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Momentum', enabled: false },
    { type: 'separator' },
    { label: 'Record (Coming Soon)', enabled: false },
    { type: 'separator' },
    { label: 'Quit Momentum', click: () => app.quit() }
  ]);
  
  tray.setToolTip('Momentum - Flow state capture');
  tray.setContextMenu(contextMenu);
  
  return tray;
};
