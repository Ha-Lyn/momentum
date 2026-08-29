import Foundation

enum TranscriptionLanguage: String, CaseIterable {
    case automatic
    case portuguese
    case english

    private static let defaultsKey = "momentum.transcriptionLanguage"

    var menuTitle: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .portuguese:
            return "Portuguese"
        case .english:
            return "English"
        }
    }

    var apiValue: String? {
        switch self {
        case .automatic:
            return nil
        case .portuguese:
            return "pt"
        case .english:
            return "en"
        }
    }

    static func load() -> TranscriptionLanguage {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey)
        return rawValue.flatMap(Self.init(rawValue:)) ?? .automatic
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
