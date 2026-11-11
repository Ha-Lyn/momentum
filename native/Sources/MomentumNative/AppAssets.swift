import AppKit
import Foundation

enum AppAssets {
    /// Dock icon override for unbundled runs (`swift run`). A built `.app`
    /// declares `CFBundleIconFile`, so macOS already shows the bundled icon in
    /// the Dock and Finder and no override is needed.
    static func appIcon() -> NSImage? {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil {
            return nil
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let nativeRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fallbackURL = nativeRoot.appendingPathComponent("Resources/AppIcon.png")

        return NSImage(contentsOf: fallbackURL)
    }

    /// Monochrome template glyph for the menu bar; AppKit tints it to match
    /// the light/dark menu bar.
    static func menuBarIcon() -> NSImage? {
        let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "tiff")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/MenuBarIcon.tiff")
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        image.accessibilityDescription = "Momentum"
        return image
    }
}
