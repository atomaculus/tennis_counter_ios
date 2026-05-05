import XCTest

final class MatchShareCardDataTests: XCTestCase {
    func testShareCardDataFormatsDurationAndSets() {
        let record = FinishedMatchRecord(
            createdAt: Date(timeIntervalSince1970: 1_772_000_400),
            durationSeconds: 4_921,
            finalScoreText: "6-4 / 3-6 / 6-3",
            setScoresText: "6-4 3-6 6-3",
            detailText: "Player A vs Player B | 6-4 3-6 6-3",
            photoBookmark: nil,
            source: "ios",
            idempotencyKey: "share-1"
        )

        let data = MatchShareCardData(record: record)

        XCTAssertEqual(data.durationText, "1:22:01")
        XCTAssertEqual(data.displaySetScores, "6-4  ·  3-6  ·  6-3")
        XCTAssertEqual(data.brandText, "Tracked with PLAYCE")
    }

    func testShareCardDataFormatsShortDuration() {
        XCTAssertEqual(MatchShareCardData.formatDuration(739), "12:19")
    }
}
