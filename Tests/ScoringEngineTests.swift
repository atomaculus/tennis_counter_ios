import XCTest

final class ScoringEngineTests: XCTestCase {
    func testPointProgressionFollowsZeroFifteenThirtyForty() {
        var score = MatchSnapshot()
        var labels: [String] = []

        for _ in 0..<3 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
            labels.append(score.pointLabel(for: .a))
        }

        XCTAssertEqual(labels, ["15", "30", "40"])
    }

    func testWinningFourPointsWinsGame() {
        var score = MatchSnapshot()
        for _ in 0..<4 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
        }

        XCTAssertEqual(score.playerA.points, 0)
        XCTAssertEqual(score.playerA.games, 1)
    }

    func testDeuceShowsFortyForty() {
        let score = scoreToDeuce()

        XCTAssertEqual(score.pointLabel(for: .a), "40")
        XCTAssertEqual(score.pointLabel(for: .b), "40")
    }

    func testAdvantageShowsADForLeadingPlayer() {
        var score = scoreToDeuce()
        score = ScoringEngine.scorePoint(score, isPlayerA: true)

        XCTAssertEqual(score.pointLabel(for: .a), "AD")
        XCTAssertEqual(score.pointLabel(for: .b), "40")
    }

    func testAdvantageLostReturnsToDeuce() {
        var score = scoreToDeuce()
        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        score = ScoringEngine.scorePoint(score, isPlayerA: false)

        XCTAssertEqual(score.pointLabel(for: .a), "40")
        XCTAssertEqual(score.pointLabel(for: .b), "40")
    }

    func testGameWonFromAdvantage() {
        var score = scoreToDeuce()
        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        score = ScoringEngine.scorePoint(score, isPlayerA: true)

        XCTAssertEqual(score.playerA.games, 1)
        XCTAssertEqual(score.playerA.points, 0)
    }

    func testNoAdDeucePointWinsGameImmediately() {
        let format = MatchFormat(noAdScoring: true)
        var score = MatchSnapshot(format: format)
        for _ in 0..<3 { score = ScoringEngine.scorePoint(score, isPlayerA: true) }
        for _ in 0..<3 { score = ScoringEngine.scorePoint(score, isPlayerA: false) }

        score = ScoringEngine.scorePoint(score, isPlayerA: true)

        XCTAssertEqual(score.playerA.games, 1)
    }

    func testWinningSixGamesWithTwoGameLeadWinsSet() {
        var score = MatchSnapshot()
        for _ in 0..<6 {
            score = winGame(for: score, isPlayerA: true)
        }

        XCTAssertEqual(score.playerA.sets, 1)
        XCTAssertEqual(score.completedSets.count, 1)
        XCTAssertEqual(score.completedSets[0], SetScore(a: 6, b: 0))
    }

    func testFiveAllRequiresTwoMoreGamesToWinSet() {
        var score = MatchSnapshot()
        for _ in 0..<5 {
            score = winGame(for: score, isPlayerA: true)
            score = winGame(for: score, isPlayerA: false)
        }

        XCTAssertEqual(score.playerA.games, 5)
        XCTAssertEqual(score.playerB.games, 5)

        score = winGame(for: score, isPlayerA: true)
        XCTAssertEqual(score.playerA.sets, 0)

        score = winGame(for: score, isPlayerA: true)
        XCTAssertEqual(score.playerA.sets, 1)
        XCTAssertEqual(score.completedSets.last, SetScore(a: 7, b: 5))
    }

    func testTiebreakStartsAtSixAll() {
        let score = scoreToSixAll()

        XCTAssertTrue(score.isTiebreak)
    }

    func testTiebreakPointLabelsAreNumeric() {
        var score = scoreToSixAll()
        score = ScoringEngine.scorePoint(score, isPlayerA: true)

        XCTAssertEqual(score.pointLabel(for: .a), "1")
        XCTAssertEqual(score.pointLabel(for: .b), "0")
    }

    func testTiebreakWonAtSevenPointsWithTwoPointLead() {
        var score = scoreToSixAll()
        for _ in 0..<7 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
        }

        XCTAssertEqual(score.playerA.sets, 1)
        XCTAssertEqual(score.completedSets.last, SetScore(a: 7, b: 6))
        XCTAssertFalse(score.isTiebreak)
    }

    func testTiebreakRequiresTwoPointLead() {
        var score = scoreToSixAll()
        for _ in 0..<6 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
            score = ScoringEngine.scorePoint(score, isPlayerA: false)
        }

        XCTAssertEqual(score.playerA.points, 6)
        XCTAssertEqual(score.playerB.points, 6)
        XCTAssertTrue(score.isTiebreak)

        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertTrue(score.isTiebreak)
        XCTAssertEqual(score.playerA.sets, 0)

        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertEqual(score.playerA.sets, 1)
    }

    func testTiebreakDisabledMeansNoTiebreakAtSixAll() {
        let format = MatchFormat(tiebreakAtSixAll: false)
        var score = MatchSnapshot(format: format)
        for _ in 0..<6 {
            score = winGame(for: score, isPlayerA: true)
            score = winGame(for: score, isPlayerA: false)
        }

        XCTAssertFalse(score.isTiebreak)
        XCTAssertEqual(score.playerA.games, 6)
        XCTAssertEqual(score.playerB.games, 6)
    }

    func testMatchEndsWhenSetsToWinReachedBestOfThree() {
        var score = MatchSnapshot(format: MatchFormat(setsToWin: 2))
        for _ in 0..<2 {
            for _ in 0..<6 {
                score = winGame(for: score, isPlayerA: true)
            }
        }

        XCTAssertTrue(score.isMatchOver)
        XCTAssertEqual(score.playerA.sets, 2)
    }

    func testMatchEndsWhenSetsToWinReachedBestOfFive() {
        var score = MatchSnapshot(format: .grandSlam)
        for _ in 0..<3 {
            for _ in 0..<6 {
                score = winGame(for: score, isPlayerA: true)
            }
        }

        XCTAssertTrue(score.isMatchOver)
    }

    func testNoPointsAfterMatchIsOver() {
        var score = MatchSnapshot()
        for _ in 0..<2 {
            for _ in 0..<6 {
                score = winGame(for: score, isPlayerA: true)
            }
        }

        XCTAssertTrue(score.isMatchOver)
        let before = score
        score = ScoringEngine.scorePoint(score, isPlayerA: true)

        XCTAssertEqual(score, before)
    }

    func testSuperTiebreakInFinalSetAtOneSetAll() {
        let format = MatchFormat(superTiebreakInFinalSet: true)
        var score = MatchSnapshot(format: format)

        for _ in 0..<6 { score = winGame(for: score, isPlayerA: true) }
        for _ in 0..<6 { score = winGame(for: score, isPlayerA: false) }

        XCTAssertEqual(score.playerA.sets, 1)
        XCTAssertEqual(score.playerB.sets, 1)

        for _ in 0..<6 {
            score = winGame(for: score, isPlayerA: true)
            score = winGame(for: score, isPlayerA: false)
        }

        XCTAssertTrue(score.isTiebreak)

        for _ in 0..<10 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
        }

        XCTAssertTrue(score.isMatchOver)
        XCTAssertEqual(score.playerA.sets, 2)
    }

    func testServerAlternatesEachGame() {
        var score = MatchSnapshot(initialServerIsPlayerA: true)

        XCTAssertTrue(score.currentServerIsPlayerA)

        score = winGame(for: score, isPlayerA: true)
        XCTAssertFalse(score.currentServerIsPlayerA)

        score = winGame(for: score, isPlayerA: true)
        XCTAssertTrue(score.currentServerIsPlayerA)
    }

    func testServeStartsOnRightThenAlternates() {
        var score = MatchSnapshot()

        XCTAssertFalse(score.serveStartsOnLeftSide)

        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertTrue(score.serveStartsOnLeftSide)

        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertFalse(score.serveStartsOnLeftSide)
    }

    func testReplayRecreatesExactScore() {
        let points: [PlayerSide] = [.a, .a, .a, .a, .b, .b, .b, .b]
        let score = ScoringEngine.replay(points)

        XCTAssertEqual(score.playerA.games, 1)
        XCTAssertEqual(score.playerB.games, 1)
    }

    func testReplayWithEmptyListGivesFreshScore() {
        let score = ScoringEngine.replay([])

        XCTAssertEqual(score.playerA, PlayerScore())
        XCTAssertEqual(score.playerB, PlayerScore())
    }

    private func scoreToDeuce() -> MatchSnapshot {
        var score = MatchSnapshot()
        for _ in 0..<3 { score = ScoringEngine.scorePoint(score, isPlayerA: true) }
        for _ in 0..<3 { score = ScoringEngine.scorePoint(score, isPlayerA: false) }
        return score
    }

    private func scoreToSixAll() -> MatchSnapshot {
        var score = MatchSnapshot()
        for _ in 0..<6 {
            score = winGame(for: score, isPlayerA: true)
            score = winGame(for: score, isPlayerA: false)
        }
        return score
    }

    private func winGame(for score: MatchSnapshot, isPlayerA: Bool) -> MatchSnapshot {
        var current = score
        for _ in 0..<4 {
            current = ScoringEngine.scorePoint(current, isPlayerA: isPlayerA)
        }
        return current
    }
}
