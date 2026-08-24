import Foundation

enum AnalysisError: LocalizedError, Sendable {
    case missingKey
    case invalidResponse(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "No API key is configured."
        case .invalidResponse(let detail):
            "The analysis response did not match the expected format. \(detail)"
        case .server(let message):
            message
        }
    }
}

private enum ResponseSchema {
    case metadata
    case tradeRecommendation

    var name: String {
        switch self {
        case .metadata:
            "chart_metadata"
        case .tradeRecommendation:
            "trade_recommendation"
        }
    }

    var schema: [String: Any] {
        switch self {
        case .metadata:
            [
                "type": "object",
                "properties": [
                    "symbol": ["type": "string"],
                    "timeframe": ["type": "string"]
                ],
                "required": ["symbol", "timeframe"],
                "additionalProperties": false
            ]
        case .tradeRecommendation:
            [
                "type": "object",
                "properties": [
                    "bias": ["type": "string", "enum": ["bullish", "bearish"]],
                    "confidence": ["type": "integer", "minimum": 0, "maximum": 100],
                    "entryLow": ["type": "number"],
                    "entryHigh": ["type": "number"],
                    "stop": ["type": "number"],
                    "target1": ["type": "number"],
                    "target2": ["type": "number"],
                    "keyLevels": [
                        "type": "array",
                        "minItems": 1,
                        "items": [
                            "type": "object",
                            "properties": [
                                "label": ["type": "string", "enum": ["support", "resistance", "pivot"]],
                                "price": ["type": "number"]
                            ],
                            "required": ["label", "price"],
                            "additionalProperties": false
                        ]
                    ],
                    "pattern": ["type": "string"],
                    "rationale": ["type": "string"],
                    "invalidation": ["type": "string"]
                ],
                "required": [
                    "bias", "confidence", "entryLow", "entryHigh", "stop",
                    "target1", "target2", "keyLevels", "pattern", "rationale", "invalidation"
                ],
                "additionalProperties": false
            ]
        }
    }
}

struct VisionAnalysisService: Sendable {
    let apiKey: String
    let model: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func readMetadata(imageData: Data) async throws -> ChartMetadata {
        let text = "Read the visible futures chart. Return JSON only: {\"symbol\":\"exact contract/ticker or UNKNOWN\",\"timeframe\":\"exact interval or UNKNOWN\"}. Do not guess if unreadable."
        let content = try await request(imageData: imageData, prompt: text, responseSchema: .metadata)
        let result: MetadataResponse = try decode(content)
        return .init(symbol: result.symbol, timeframe: result.timeframe)
    }

    func analyze(imageData: Data, metadata: ChartMetadata) async throws -> TradeRecommendation {
        let prompt = """
        You are a disciplined, advisory-only futures market-structure analyst. Analyze the supplied \(metadata.symbol) chart on \(metadata.timeframe) to create a conditional NY AM trade plan. The chart is the source of truth: do not invent levels, sessions, price action, confirmations, or timestamps that are not visible. Read visible price labels precisely. Do not present a trade as active unless its entry conditions are already confirmed.

        TRADING PRINCIPLES
        - Location before direction: do not short directly into reclaimed support or long directly into resistance.
        - Liquidity first: identify visible prior-day, prior-week, Asia, London, overnight, and obvious swing highs/lows when they are labeled or unambiguous.
        - Confirmation only: a point of interest alone is not an entry. Require a sweep or clear rejection, displacement, and a 1m/3m market-structure shift. If those lower timeframes are not visible, make them conditions for entry; do not claim that they occurred.
        - Be conditional when structure and location conflict.
        - Explicitly name no-trade conditions.
        - Stops must be structural, beyond the sweep wick or pullback swing. Targets must be meaningful opposing liquidity or range objectives.
        - Never recommend order execution, position size, or guarantee an outcome.

        ANALYSIS WORKFLOW
        1. Determine whether market structure is bullish, bearish, mixed, or balanced. Distinguish the directional structure from the quality of the current entry location.
        2. Map visible key liquidity and reference levels: PDH, PDL, PWH, PWL, Asia high/low, London high/low, overnight range/equilibrium, FVGs, shelves, and meaningful swing pools. For each visible level, state internally whether it was swept, reclaimed, held, or remains untaken.
        3. Explain the current auction: identify stacked highs/lows, recent sweeps and reclaims, the nearest valid downside draw, and the nearest valid upside draw. Never chase price into a level.
        4. Identify any decision zone or pinch: nearby levels that control whether the upside or downside draw is live. Holding/reclaiming a pinch supports rotation back into the range; losing it with displacement supports continuation toward the next draw.
        5. Select the single best conditional setup visible now. It may be continuation or reversal. Its trigger must state the required sweep/rejection, displacement, and structure shift, with an FVG retrace where applicable.
        6. If the chart is inside a range without a clean sweep and displacement, mark the plan as no-trade until confirmation. Use low confidence and clearly state the condition in rationale and invalidation rather than manufacturing certainty.

        OUTPUT MAPPING
        - bias: the direction of the selected conditional setup: "bullish" or "bearish".
        - confidence: 0-100. Reduce it materially when the setup is unconfirmed, price is in a pinch/chop zone, or important session data is unreadable.
        - entryLow and entryHigh: the exact POI or FVG-retrace zone; use the same value for a single-price POI.
        - stop: structural stop beyond the applicable sweep wick or pullback swing.
        - target1 and target2: the first and second opposing liquidity/range objectives.
        - keyLevels: include the most important visible support, resistance, and pivot levels.
        - pattern: concise sub-model and trigger, for example "Continuation short — pullback rejection, displacement, then 1m/3m shift down" or "Reversal long — sell-side sweep, reclaim, displacement, then shift up".
        - rationale: one concise sentence covering structure, location, liquidity draw, and any no-trade requirement.
        - invalidation: the exact break-and-hold or failed-reclaim condition that kills the thesis.

        Return JSON only with this exact schema:
        {"bias":"bullish|bearish","confidence":0-100,"entryLow":number,"entryHigh":number,"stop":number,"target1":number,"target2":number,"keyLevels":[{"label":"support|resistance|pivot","price":number}],"pattern":"short pattern/context","rationale":"one sentence","invalidation":"short condition"}
        """
        let content = try await request(imageData: imageData, prompt: prompt, responseSchema: .tradeRecommendation)
        return try decode(content)
    }

    private func request(
        imageData: Data,
        prompt: String,
        responseSchema: ResponseSchema
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AnalysisError.missingKey }

        let image = imageData.base64EncodedString()
        let body: [String: Any] = [
            "model": model,
            "reasoning_effort": "medium",
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": responseSchema.name,
                    "strict": true,
                    "schema": responseSchema.schema
                ]
            ],
            "messages": [["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(image)", "detail": "high"]]
            ]]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse("The server did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            throw AnalysisError.server(detail?["message"] as? String ?? "Analysis service returned HTTP \(http.statusCode).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            throw AnalysisError.invalidResponse("The server response was missing its message.")
        }
        if choice["finish_reason"] as? String == "length" {
            throw AnalysisError.invalidResponse("The model reached its output limit. Please retry.")
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            throw AnalysisError.server(refusal)
        }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw AnalysisError.invalidResponse("The server returned an empty message.")
        }
        return content
    }

    private func decode<Value: Decodable>(_ content: String) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(content.utf8))
        } catch {
            throw AnalysisError.invalidResponse(error.localizedDescription)
        }
    }
}
