import Foundation

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Set OPENAI_API_KEY or create ~/Library/Application Support/Momentum/config.json before launching Momentum."
        case .invalidResponse:
            return "The transcription API returned an invalid response."
        case .apiError(let message):
            return message
        }
    }
}

private struct WhisperResponse: Decodable {
    let text: String
}

private struct MomentumConfiguration: Decodable {
    let openAIAPIKey: String?
    let openAPIKey: String?
}

struct TranscriptionService: Sendable {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(audioURL: URL) async throws -> String {
        let apiKey = try resolveAPIKey()
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeBody(audioURL: audioURL, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Transcription request failed."
            throw TranscriptionError.apiError(message)
        }

        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }

    private func resolveAPIKey() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        let apiKey = environment["OPENAI_API_KEY"]
            ?? environment["OPEN_API_KEY"]
            ?? loadAPIKeyFromConfigurationFile()

        guard let apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        return apiKey
    }

    private func loadAPIKeyFromConfigurationFile() -> String? {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let configURL = applicationSupportDirectory
            .appendingPathComponent("Momentum", isDirectory: true)
            .appendingPathComponent("config.json")

        guard
            let data = try? Data(contentsOf: configURL),
            let configuration = try? JSONDecoder().decode(MomentumConfiguration.self, from: data)
        else {
            return nil
        }

        return configuration.openAIAPIKey ?? configuration.openAPIKey
    }

    private func makeBody(audioURL: URL, boundary: String) throws -> Data {
        let lineBreak = "\r\n"
        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)")
        body.append("whisper-1\(lineBreak)")

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"language\"\(lineBreak)\(lineBreak)")
        body.append("pt\(lineBreak)")

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(lineBreak)")
        body.append("Content-Type: audio/mp4\(lineBreak)\(lineBreak)")
        body.append(audioData)
        body.append(lineBreak)

        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
