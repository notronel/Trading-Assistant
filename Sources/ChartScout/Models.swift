import Foundation

struct ChartMetadata: Codable, Equatable {
    var symbol: String
    var timeframe: String
}

enum MarketBias: String, Codable, CaseIterable {
    case bullish, bearish

    var title: String { rawValue.capitalized }
}

struct KeyLevel: Codable, Identifiable, Equatable {
    let label: String
    let price: Double
    var id: String { "\(label)-\(price)" }
}

struct TradeRecommendation: Codable, Equatable {
    let bias: MarketBias
    let confidence: Int
    let entryLow: Double
    let entryHigh: Double
    let stop: Double
    let target1: Double
    let target2: Double
    let keyLevels: [KeyLevel]
    let pattern: String
    let rationale: String
    let invalidation: String

    var isLowConfidence: Bool { confidence < 60 }
    var entryText: String {
        entryLow == entryHigh ? PriceFormatter.string(entryLow) : "\(PriceFormatter.string(entryLow)) – \(PriceFormatter.string(entryHigh))"
    }
}

enum PriceFormatter {
    static func string(_ price: Double) -> String {
        price.formatted(.number.precision(.fractionLength(0...4)))
    }
}

struct JournalEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let metadata: ChartMetadata
    let recommendation: TradeRecommendation
    let imageData: Data
    var outcomeNote: String
}

struct MetadataResponse: Codable, Equatable {
    let symbol: String
    let timeframe: String
}
