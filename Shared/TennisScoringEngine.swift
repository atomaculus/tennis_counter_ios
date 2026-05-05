import Foundation
import Combine

enum ScoringEngine {
    static func scorePoint(_ score: MatchSnapshot, isPlayerA: Bool) -> MatchSnapshot {
        guard !score.isMatchOver else { return score }

        let winner = isPlayerA ? score.playerA : score.playerB
        let loser = isPlayerA ? score.playerB : score.playerA
        let result: PointResult

        if score.isTiebreak || isSuperTiebreak(score) {
            result = resolveTiebreakPoint(winner: winner, loser: loser, score: score, format: score.format)
        } else {
            result = resolveRegularPoint(winner: winner, loser: loser, score: score, format: score.format)
        }

        let newA = isPlayerA ? result.newWinner : result.newLoser
        let newB = isPlayerA ? result.newLoser : result.newWinner
        var completedSets = score.completedSets
        if let completed = result.completedSet {
            completedSets.append(isPlayerA ? SetScore(a: completed.winner, b: completed.loser) : SetScore(a: completed.loser, b: completed.winner))
        }

        let winnerSets = isPlayerA ? newA.sets : newB.sets
        let matchOver = result.completedSet != nil && winnerSets >= score.format.setsToWin
        let nowInTiebreak: Bool
        if matchOver || result.completedSet != nil {
            nowInTiebreak = false
        } else if result.enteredTiebreak || score.isTiebreak {
            nowInTiebreak = true
        } else {
            nowInTiebreak = false
        }

        var updated = score
        updated.playerA = newA
        updated.playerB = newB
        updated.completedSets = completedSets
        updated.isTiebreak = nowInTiebreak
        updated.isMatchOver = matchOver
        return updated
    }

    static func replay(
        _ points: [PlayerSide],
        format: MatchFormat = .standard,
        initialServerIsPlayerA: Bool = true
    ) -> MatchSnapshot {
        var score = MatchSnapshot(format: format, initialServerIsPlayerA: initialServerIsPlayerA)
        points.forEach { side in
            score = scorePoint(score, isPlayerA: side == .a)
        }
        return score
    }

    private struct PointResult {
        var newWinner: PlayerScore
        var newLoser: PlayerScore
        var completedSet: (winner: Int, loser: Int)?
        var enteredTiebreak: Bool = false
    }

    private static func isSuperTiebreak(_ score: MatchSnapshot) -> Bool {
        guard score.format.superTiebreakInFinalSet else { return false }
        let maxSets = score.format.setsToWin
        return score.playerA.sets == maxSets - 1 &&
            score.playerB.sets == maxSets - 1 &&
            score.isTiebreak
    }

    private static func resolveRegularPoint(
        winner: PlayerScore,
        loser: PlayerScore,
        score: MatchSnapshot,
        format: MatchFormat
    ) -> PointResult {
        let winnerPoints = winner.points + 1
        let loserPoints = loser.points
        let takesGame = format.noAdScoring
            ? winnerPoints >= 4 && winnerPoints - loserPoints >= 1
            : winnerPoints >= 4 && winnerPoints - loserPoints >= 2

        guard takesGame else {
            var updatedWinner = winner
            updatedWinner.points = winnerPoints
            return PointResult(newWinner: updatedWinner, newLoser: loser)
        }

        return resolveGameWon(winner: winner, loser: loser, score: score, format: format)
    }

    private static func resolveGameWon(
        winner: PlayerScore,
        loser: PlayerScore,
        score: MatchSnapshot,
        format: MatchFormat
    ) -> PointResult {
        let winnerGames = winner.games + 1
        let loserGames = loser.games

        if format.tiebreakAtSixAll && winnerGames == 6 && loserGames == 6 {
            var updatedWinner = winner
            updatedWinner.points = 0
            updatedWinner.games = winnerGames

            var updatedLoser = loser
            updatedLoser.points = 0

            return PointResult(
                newWinner: updatedWinner,
                newLoser: updatedLoser,
                enteredTiebreak: true
            )
        }

        let takesSet = winnerGames >= 6 && winnerGames - loserGames >= 2
        if takesSet {
            var updatedWinner = winner
            updatedWinner.points = 0
            updatedWinner.games = 0
            updatedWinner.sets += 1

            var updatedLoser = loser
            updatedLoser.points = 0
            updatedLoser.games = 0

            return PointResult(
                newWinner: updatedWinner,
                newLoser: updatedLoser,
                completedSet: (winnerGames, loserGames)
            )
        }

        var updatedWinner = winner
        updatedWinner.points = 0
        updatedWinner.games = winnerGames

        var updatedLoser = loser
        updatedLoser.points = 0

        return PointResult(newWinner: updatedWinner, newLoser: updatedLoser)
    }

    private static func resolveTiebreakPoint(
        winner: PlayerScore,
        loser: PlayerScore,
        score: MatchSnapshot,
        format: MatchFormat
    ) -> PointResult {
        let winnerPoints = winner.points + 1
        let loserPoints = loser.points
        let targetPoints = isSuperTiebreak(score) ? 10 : format.tiebreakPoints
        let takesTiebreak = winnerPoints >= targetPoints && winnerPoints - loserPoints >= 2

        guard takesTiebreak else {
            var updatedWinner = winner
            updatedWinner.points = winnerPoints
            return PointResult(newWinner: updatedWinner, newLoser: loser)
        }

        let setGamesWinner = winner.games + 1
        let setGamesLoser = loser.games

        var updatedWinner = winner
        updatedWinner.points = 0
        updatedWinner.games = 0
        updatedWinner.sets += 1

        var updatedLoser = loser
        updatedLoser.points = 0
        updatedLoser.games = 0

        return PointResult(
            newWinner: updatedWinner,
            newLoser: updatedLoser,
            completedSet: (setGamesWinner, setGamesLoser)
        )
    }
}

@MainActor
final class ScoreboardController: ObservableObject {
    @Published private(set) var state: MatchSnapshot = .init()
    @Published private(set) var playerAName = "Player A"
    @Published private(set) var playerBName = "Player B"
    @Published private(set) var finishedSummary: MobileFinishedSummary?

    private var pointHistory: [PlayerSide] = []
    private var baseline = MatchSnapshot()
    private var timer: Timer?
    private var timerAnchor = Date()
    private var elapsedBase = 0
    private var finishedIdempotencyKey = UUID().uuidString

    init() {
        startTicker()
    }

    func addPoint(to side: PlayerSide) {
        guard !state.isMatchOver else { return }
        pointHistory.append(side)
        state = ScoringEngine.scorePoint(state, isPlayerA: side == .a)
        if state.isMatchOver {
            finishMatch()
        }
    }

    @discardableResult
    func undoLastPoint(for side: PlayerSide) -> Bool {
        guard let index = pointHistory.lastIndex(of: side) else {
            return false
        }
        pointHistory.remove(at: index)
        rebuildFromHistory()
        return true
    }

    func resetGame() {
        pointHistory.removeAll()
        baseline = state
        baseline.playerA.points = 0
        baseline.playerB.points = 0
        state.playerA.points = 0
        state.playerB.points = 0
        state.isTiebreak = false
    }

    func resetMatch() {
        let format = state.format
        pointHistory.removeAll()
        baseline = MatchSnapshot(format: format)
        elapsedBase = 0
        timerAnchor = Date()
        state = MatchSnapshot(format: format)
        playerAName = "Player A"
        playerBName = "Player B"
        finishedSummary = nil
        finishedIdempotencyKey = UUID().uuidString
    }

    func setPlayerNames(_ playerAName: String, _ playerBName: String) {
        self.playerAName = Self.normalizedPlayerName(playerAName, fallback: "Player A")
        self.playerBName = Self.normalizedPlayerName(playerBName, fallback: "Player B")
    }

    func setMatchFormat(_ format: MatchFormat) {
        guard pointHistory.isEmpty, finishedSummary == nil else { return }
        state.format = format
        baseline.format = format
    }

    func toggleTimer() {
        guard finishedSummary == nil else { return }
        if state.isTimerRunning {
            elapsedBase = state.elapsedSeconds
            state.isTimerRunning = false
        } else {
            timerAnchor = Date()
            state.isTimerRunning = true
            state.hasTimerStarted = true
        }
    }

    func finishMatch() {
        let current = state
        if current.isTimerRunning {
            elapsedBase = current.elapsedSeconds
        }

        let hasSets = current.playerA.sets > 0 || current.playerB.sets > 0
        let setsScore = hasSets
            ? "\(current.playerA.sets)-\(current.playerB.sets)"
            : "\(current.playerA.games)-\(current.playerB.games)"
        let completed = current.completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: " ")
        let detail: String
        if completed.isEmpty && !hasSets {
            detail = "Games: \(current.playerA.games)-\(current.playerB.games)"
        } else if completed.isEmpty {
            detail = "G \(current.playerA.games)-\(current.playerB.games)"
        } else {
            detail = "\(completed) | G \(current.playerA.games)-\(current.playerB.games)"
        }

        state.isTimerRunning = false
        state.hasTimerStarted = true
        finishedSummary = MobileFinishedSummary(
            createdAt: Date(),
            durationSeconds: current.elapsedSeconds,
            setsScore: setsScore,
            setsDetail: detail,
            playerAName: playerAName,
            playerBName: playerBName
        )
    }

    func finishMatchRecord(source: String) -> FinishedMatchRecord {
        let detailText: String
        if let finishedSummary {
            detailText = "\(finishedSummary.playerAName) vs \(finishedSummary.playerBName) | \(finishedSummary.setsDetail)"
        } else {
            detailText = "\(playerAName) vs \(playerBName) | \(state.setDetailLine)"
        }

        return FinishedMatchRecord(
            createdAt: finishedSummary?.createdAt ?? Date(),
            durationSeconds: finishedSummary?.durationSeconds ?? state.elapsedSeconds,
            finalScoreText: finishedSummary?.setsScore ?? state.finalSetsScore,
            setScoresText: state.completedSets.isEmpty ? nil : state.completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: " "),
            detailText: detailText,
            photoBookmark: nil,
            source: source,
            idempotencyKey: finishedIdempotencyKey
        )
    }

    private func startTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state.isTimerRunning else { return }
        let elapsed = elapsedBase + Int(Date().timeIntervalSince(timerAnchor))
        if elapsed != state.elapsedSeconds {
            state.elapsedSeconds = elapsed
        }
    }

    private func rebuildFromHistory() {
        var rebuilt = baseline
        rebuilt.elapsedSeconds = state.elapsedSeconds
        rebuilt.isTimerRunning = state.isTimerRunning
        rebuilt.hasTimerStarted = state.hasTimerStarted
        state = pointHistory.reduce(rebuilt) { score, winner in
            ScoringEngine.scorePoint(score, isPlayerA: winner == .a)
        }
    }

    private static func normalizedPlayerName(_ rawValue: String, fallback: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(12))
    }
}
