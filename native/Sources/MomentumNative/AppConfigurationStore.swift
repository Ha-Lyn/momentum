import Foundation

struct MomentumConfiguration: Codable {
    var openAIAPIKey: String?
    var openAPIKey: String?
}

enum AppConfigurationStore {
    static func load() throws -> MomentumConfiguration {
        let url = try configurationURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return MomentumConfiguration(openAIAPIKey: nil, openAPIKey: nil)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MomentumConfiguration.self, from: data)
    }

    static func save(apiKey: String) throws {
        var configuration = try load()
        configuration.openAIAPIKey = apiKey
        configuration.openAPIKey = nil

        let url = try configurationURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: url, options: .atomic)
    }

    static func storedAPIKey() -> String? {
        guard let configuration = try? load() else {
            return nil
        }

        return configuration.openAIAPIKey ?? configuration.openAPIKey
    }

    static func hasStoredAPIKey() -> Bool {
        guard let apiKey = storedAPIKey() else {
            return false
        }

        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func configurationURL() throws -> URL {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return applicationSupportDirectory
            .appendingPathComponent("Momentum", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}
