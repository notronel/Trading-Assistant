import XCTest
@testable import ChartScout

final class ChartScoutTests: XCTestCase {
    func testTradeRecommendationDecodesAndIdentifiesLowConfidence() throws {
        let json = """
        {"bias":"bullish","confidence":55,"entryLow":21000.25,"entryHigh":21002.0,"stop":20990.0,"target1":21012.0,"target2":21022.0,"keyLevels":[{"label":"support","price":21000.0}],"pattern":"breakout retest","rationale":"Buyers held the prior breakout level.","invalidation":"Close below support."}
        """
        let recommendation = try JSONDecoder().decode(TradeRecommendation.self, from: Data(json.utf8))
        XCTAssertTrue(recommendation.isLowConfidence)
        XCTAssertEqual(recommendation.entryText, "21,000.25 – 21,002")
    }

    func testMetadataDecodes() throws {
        let result = try JSONDecoder().decode(MetadataResponse.self, from: Data("{\"symbol\":\"NQ1!\",\"timeframe\":\"5m\"}".utf8))
        XCTAssertEqual(ChartMetadata(symbol: result.symbol, timeframe: result.timeframe), .init(symbol: "NQ1!", timeframe: "5m"))
    }
}
