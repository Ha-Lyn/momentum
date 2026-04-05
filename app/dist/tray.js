"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupTray = void 0;
const electron_1 = require("electron");
let tray = null;
const setupTray = () => {
    // Create an empty image for the tray icon until we have a real icon
    const icon = electron_1.nativeImage.createEmpty();
    tray = new electron_1.Tray(icon);
    tray.setTitle('M'); // Represents Momentum
    const contextMenu = electron_1.Menu.buildFromTemplate([
        { label: 'Momentum', enabled: false },
        { type: 'separator' },
        { label: 'Record (Coming Soon)', enabled: false },
        { type: 'separator' },
        { label: 'Quit Momentum', click: () => electron_1.app.quit() }
    ]);
    tray.setToolTip('Momentum - Flow state capture');
    tray.setContextMenu(contextMenu);
    return tray;
};
exports.setupTray = setupTray;
