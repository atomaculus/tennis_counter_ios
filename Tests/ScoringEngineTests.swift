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

    // ---- Deciding tiebreak ----

    func testDecidingTiebreakCannotBeOfferedAtMatchStartOrMidSet() {
        var score = MatchSnapshot()
        XCTAssertFalse(ScoringEngine.canOfferDecidingTiebreak(score))

        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertFalse(ScoringEngine.canOfferDecidingTiebreak(score))

        var oneSet = MatchSnapshot()
        for _ in 0..<6 { oneSet = winGame(for: oneSet, isPlayerA: true) }
        XCTAssertFalse(ScoringEngine.canOfferDecidingTiebreak(oneSet))
    }

    func testDecidingTiebreakOfferedOnAnySetTieRegardlessOfBestOf() {
        XCTAssertTrue(ScoringEngine.canOfferDecidingTiebreak(scoreToTiedSets(setsEach: 1)))
        XCTAssertTrue(ScoringEngine.canOfferDecidingTiebreak(scoreToTiedSets(setsEach: 1, format: .grandSlam)))
        XCTAssertTrue(ScoringEngine.canOfferDecidingTiebreak(scoreToTiedSets(setsEach: 2, format: .grandSlam)))
    }

    func testDecidingTiebreakNotOfferedOnceNextSetStarted() {
        var score = scoreToTiedSets(setsEach: 1)
        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertFalse(ScoringEngine.canOfferDecidingTiebreak(score))
    }

    func testStartDecidingTiebreakIsNoOpWhenNotOfferable() {
        let fresh = MatchSnapshot()
        XCTAssertEqual(ScoringEngine.startDecidingTiebreak(fresh, targetPoints: 10), fresh)
    }

    func testDecidingTiebreakToSevenWinsTheMatchInBestOfThree() {
        var score = ScoringEngine.startDecidingTiebreak(scoreToTiedSets(setsEach: 1), targetPoints: 7)
        XCTAssertTrue(score.isTiebreak)
        XCTAssertEqual(score.pointLabel(for: .a), "0")

        for _ in 0..<7 { score = ScoringEngine.scorePoint(score, isPlayerA: true) }
        XCTAssertTrue(score.isMatchOver)
        XCTAssertEqual(score.playerA.sets, 2)
        XCTAssertEqual(score.completedSets.last, SetScore(a: 7, b: 0))
    }

    func testDecidingTiebreakToTenAtOneAllInBestOfFiveEndsTheWholeMatch() {
        var score = ScoringEngine.startDecidingTiebreak(scoreToTiedSets(setsEach: 1, format: .grandSlam), targetPoints: 10)

        for _ in 0..<9 { score = ScoringEngine.scorePoint(score, isPlayerA: false) }
        XCTAssertFalse(score.isMatchOver)

        score = ScoringEngine.scorePoint(score, isPlayerA: false)
        XCTAssertTrue(score.isMatchOver)
        XCTAssertEqual(score.playerB.sets, 2) // fewer than setsToWin, still over
        XCTAssertEqual(score.completedSets.last, SetScore(a: 0, b: 10))
    }

    func testDecidingTiebreakRequiresTwoPointLead() {
        var score = ScoringEngine.startDecidingTiebreak(scoreToTiedSets(setsEach: 1), targetPoints: 10)
        for _ in 0..<9 {
            score = ScoringEngine.scorePoint(score, isPlayerA: true)
            score = ScoringEngine.scorePoint(score, isPlayerA: false)
        }
        // 10-9 not enough
        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertFalse(score.isMatchOver)
        // 11-9 wins
        score = ScoringEngine.scorePoint(score, isPlayerA: true)
        XCTAssertTrue(score.isMatchOver)
        XCTAssertEqual(score.completedSets.last, SetScore(a: 11, b: 9))
    }

    // ---- Event replay ----

    func testReplayEventsRebuildsDecidingTiebreakState() {
        var events: [ScoringEngine.MatchEvent] = []
        for _ in 0..<24 { events.append(.point(isPlayerA: true, timestampMillis: 0)) }  // A wins set 6-0
        for _ in 0..<24 { events.append(.point(isPlayerA: false, timestampMillis: 0)) } // B wins set 6-0
        events.append(.decidingTiebreakStarted(targetPoints: 10, timestampMillis: 0))
        for _ in 0..<3 { events.append(.point(isPlayerA: true, timestampMillis: 0)) }

        let score = ScoringEngine.replayEvents(events)
        XCTAssertTrue(score.isTiebreak)
        XCTAssertEqual(score.decidingTiebreakTarget, 10)
        XCTAssertEqual(score.playerA.points, 3)
        XCTAssertFalse(score.isMatchOver)
    }

    func testDroppingLastEventUndoesTheDecidingTiebreakChoice() {
        var events: [ScoringEngine.MatchEvent] = []
        for _ in 0..<24 { events.append(.point(isPlayerA: true, timestampMillis: 0)) }
        for _ in 0..<24 { events.append(.point(isPlayerA: false, timestampMillis: 0)) }
        events.append(.decidingTiebreakStarted(targetPoints: 10, timestampMillis: 0))

        let undone = ScoringEngine.replayEvents(Array(events.dropLast()))
        XCTAssertFalse(undone.isTiebreak)
        XCTAssertNil(undone.decidingTiebreakTarget)
        XCTAssertTrue(ScoringEngine.canOfferDecidingTiebreak(undone)) // question re-arms
    }

    func testReplayEventsIgnoresTimestampsWhenComputingScore() {
        var eventsWithRealTimestamps: [ScoringEngine.MatchEvent] = []
        var eventsWithZeroTimestamps: [ScoringEngine.MatchEvent] = []
        var millis: Int64 = 1_700_000_000_000
        for isPlayerA in [true, true, true, true, false, false, false] {
            eventsWithRealTimestamps.append(.point(isPlayerA: isPlayerA, timestampMillis: millis))
            eventsWithZeroTimestamps.append(.point(isPlayerA: isPlayerA, timestampMillis: 0))
            millis += 1_000
        }
        eventsWithRealTimestamps.append(.decidingTiebreakStarted(targetPoints: 10, timestampMillis: millis))
        eventsWithZeroTimestamps.append(.decidingTiebreakStarted(targetPoints: 10, timestampMillis: 0))

        let scoreWithRealTimestamps = ScoringEngine.replayEvents(eventsWithRealTimestamps)
        let scoreWithZeroTimestamps = ScoringEngine.replayEvents(eventsWithZeroTimestamps)
        XCTAssertEqual(scoreWithRealTimestamps, scoreWithZeroTimestamps)
    }

    // ---- Event -> PointEventRecord mapping ----

    func testPointEventRecordMappingForPointEvent() {
        let events: [ScoringEngine.MatchEvent] = [.point(isPlayerA: true, timestampMillis: 1_234)]
        let records = PointEventRecord.from(events)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].type, PointEventRecord.pointType)
        XCTAssertEqual(records[0].isPlayerA, true)
        XCTAssertNil(records[0].targetPoints)
        XCTAssertEqual(records[0].t, 1_234)
    }

    func testPointEventRecordMappingForDecidingTiebreakEvent() {
        let events: [ScoringEngine.MatchEvent] = [.decidingTiebreakStarted(targetPoints: 10, timestampMillis: 5_678)]
        let records = PointEventRecord.from(events)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].type, PointEventRecord.decidingTiebreakType)
        XCTAssertNil(records[0].isPlayerA)
        XCTAssertEqual(records[0].targetPoints, 10)
        XCTAssertEqual(records[0].t, 5_678)
    }

    private func scoreToTiedSets(setsEach: Int, format: MatchFormat = .standard) -> MatchSnapshot {
        var score = MatchSnapshot(format: format)
        for _ in 0..<setsEach {
            for _ in 0..<6 { score = winGame(for: score, isPlayerA: true) }
            for _ in 0..<6 { score = winGame(for: score, isPlayerA: false) }
        }
        return score
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
