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

struct TranscriptionService: Sendable {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(audioURL: URL, language: TranscriptionLanguage) async throws -> String {
        let apiKey = try resolveAPIKey()
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeBody(audioURL: audioURL, boundary: boundary, language: language)

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
            ?? AppConfigurationStore.storedAPIKey()

        guard let apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        return apiKey
    }

    private func makeBody(audioURL: URL, boundary: String, language: TranscriptionLanguage) throws -> Data {
        let lineBreak = "\r\n"
        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)")
        body.append("whisper-1\(lineBreak)")

        if let languageCode = language.apiValue {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"language\"\(lineBreak)\(lineBreak)")
            body.append("\(languageCode)\(lineBreak)")
        }

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\(lineBreak)")
        body.append("Content-Type: audio/m4a\(lineBreak)\(lineBreak)")
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
