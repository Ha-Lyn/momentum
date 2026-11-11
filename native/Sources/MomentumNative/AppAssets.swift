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
}
