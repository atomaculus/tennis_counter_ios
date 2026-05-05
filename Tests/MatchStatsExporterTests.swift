import XCTest

final class MatchStatsExporterTests: XCTestCase {
    func testStatsCalculateDurationsAndKnownWinners() {
        let matches = [
            makeRecord(score: "2-0", duration: 3600),
            makeRecord(score: "1-2", duration: 1800),
            makeRecord(score: "0-0", duration: 600)
        ]

        let stats = MatchStats.calculate(from: matches)

        XCTAssertEqual(stats.totalMatches, 3)
        XCTAssertEqual(stats.totalPlayTimeSeconds, 6000)
        XCTAssertEqual(stats.avgDurationSeconds, 2000)
        XCTAssertEqual(stats.longestMatchSeconds, 3600)
        XCTAssertEqual(stats.shortestMatchSeconds, 600)
        XCTAssertEqual(stats.playerAWins, 1)
        XCTAssertEqual(stats.playerBWins, 1)
    }

    func testCSVExporterMatchesAndroidHeaderAndEscapesCommas() {
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        let match = makeRecord(
            score: "2-0, retired",
            duration: 3660,
            createdAt: date,
            setScoresText: "6-3,6-4"
        )

        let csv = MatchCSVExporter.csvString(for: [match])

        XCTAssertTrue(csv.hasPrefix("Date,Score,Sets Detail,Duration (min)\n"))
        XCTAssertTrue(csv.contains("2-0; retired"))
        XCTAssertTrue(csv.contains("6-3;6-4"))
        XCTAssertTrue(csv.contains(",61.0\n"))
    }

    func testCSVExportReturnsNilForEmptyMatches() throws {
        let url = try MatchCSVExporter.export(matches: [])

        XCTAssertNil(url)
    }

    private func makeRecord(
        score: String,
        duration: Int,
        createdAt: Date = Date(),
        setScoresText: String? = "6-3"
    ) -> FinishedMatchRecord {
        FinishedMatchRecord(
            createdAt: createdAt,
            durationSeconds: duration,
            finalScoreText: score,
            setScoresText: setScoresText,
            detailText: "Player A vs Player B",
            photoBookmark: nil,
            source: "test",
            idempotencyKey: UUID().uuidString
        )
    }
}
