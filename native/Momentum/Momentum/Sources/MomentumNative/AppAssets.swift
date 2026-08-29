import AppKit
import Foundation

enum AppAssets {
    static func appIcon() -> NSImage? {
        if let bundledURL = Bundle.main.resourceURL?.appendingPathComponent("P1.png"),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let nativeRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = nativeRoot.deletingLastPathComponent()
        let fallbackURL = repoRoot.appendingPathComponent("app/P1.png")

        return NSImage(contentsOf: fallbackURL)
    }
}
