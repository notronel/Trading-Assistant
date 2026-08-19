import Foundation

enum AnalysisError: LocalizedError, Sendable {
    case missingKey, invalidResponse, server(String)
    var errorDescription: String? { switch self { case .missingKey: "No API key is configured."; case .invalidResponse: "The analysis response was incomplete. Please retry."; case .server(let message): message } }
}

struct VisionAnalysisService: Sendable {
    let apiKey: String
    let model: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func readMetadata(imageData: Data) async throws -> ChartMetadata {
        let text = "Read the visible futures chart. Return JSON only: {\"symbol\":\"exact contract/ticker or UNKNOWN\",\"timeframe\":\"exact interval or UNKNOWN\"}. Do not guess if unreadable."
        let content = try await request(imageData: imageData, prompt: text)
        guard let result = try? JSONDecoder().decode(MetadataResponse.self, from: Data(content.utf8)) else { throw AnalysisError.invalidResponse }
        return .init(symbol: result.symbol, timeframe: result.timeframe)
    }

    func analyze(imageData: Data, metadata: ChartMetadata) async throws -> TradeRecommendation {
        let prompt = """
        You are a conservative futures chart analyst. Analyze the supplied chart for \(metadata.symbol) on \(metadata.timeframe). This is advisory only; choose the single highest-probability bullish OR bearish trade setup visible now. Read visible price labels precisely. Stops must be structural invalidation; targets must be sensible 1R and 2R areas. If ambiguity is high, still choose the best direction but reduce confidence and state why.
        Return JSON only with this exact schema:
        {"bias":"bullish|bearish","confidence":0-100,"entryLow":number,"entryHigh":number,"stop":number,"target1":number,"target2":number,"keyLevels":[{"label":"support|resistance|pivot","price":number}],"pattern":"short pattern/context","rationale":"one sentence","invalidation":"short condition"}
        Never recommend order execution, position size, or guarantee an outcome.
        """
        let content = try await request(imageData: imageData, prompt: prompt)
        guard let result = try? JSONDecoder().decode(TradeRecommendation.self, from: Data(content.utf8)), (0...100).contains(result.confidence), !result.keyLevels.isEmpty else { throw AnalysisError.invalidResponse }
        return result
    }

    private func request(imageData: Data, prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AnalysisError.missingKey }
        let image = imageData.base64EncodedString()
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(image)", "detail": "high"]]
            ]]
        ]]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnalysisError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            throw AnalysisError.server(detail?["message"] as? String ?? "Analysis service returned HTTP \(http.statusCode).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw AnalysisError.invalidResponse }
        return content
    }
}
