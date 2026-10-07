import Foundation

enum HermesError: Error, Equatable, LocalizedError {
    case missingURL
    case invalidURL
    case apiError(Int, String)
    case streamParse

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "HERMES_API_URL is not set. Add it to ~/.sunlessrc or export it."
        case .invalidURL:
            return "HERMES_API_URL is not a valid URL."
        case .apiError(let status, let body):
            return "API error \(status): \(body.isEmpty ? "no response body" : body)"
        case .streamParse:
            return "Could not parse the API response stream."
        }
    }
}

actor HermesClient {
    func streamCompletion(
        messages: [[String: String]],
        onDelta: @escaping (String) -> Void
    ) async throws {
        guard let urlString = ProcessInfo.processInfo.environment["HERMES_API_URL"],
              !urlString.isEmpty else {
            throw HermesError.missingURL
        }
        guard let url = URL(string: urlString) else {
            throw HermesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = ProcessInfo.processInfo.environment["HERMES_API_KEY"], !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": "hermes-agent",
            "messages": messages,
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HermesError.apiError(0, "non-HTTP response")
        }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw HermesError.apiError(http.statusCode, bodyString)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }

            onDelta(content)
        }
    }
}
