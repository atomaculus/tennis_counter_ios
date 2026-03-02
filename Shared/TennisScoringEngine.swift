import Foundation
import Combine

@MainActor
final class ScoreboardController: ObservableObject {
    @Published private(set) var state: MatchSnapshot = .init()

    private var pointHistory: [PlayerSide] = []
    private var baseline = MatchSnapshot()
    private var timer: Timer?
    private var timerAnchor = Date()
    private var elapsedBase = 0

    init() {
        startTicker()
    }

    func addPoint(to side: PlayerSide) {
        pointHistory.append(side)
        applyPointWon(by: side)
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
    }

    func resetMatch() {
        pointHistory.removeAll()
        baseline = MatchSnapshot()
        elapsedBase = 0
        timerAnchor = Date()
        state = MatchSnapshot()
    }

    func toggleTimer() {
        if state.isTimerRunning {
            elapsedBase = state.elapsedSeconds
            state.isTimerRunning = false
        } else {
            timerAnchor = Date()
            state.isTimerRunning = true
        }
    }

    func finishMatchRecord(source: String) -> FinishedMatchRecord {
        FinishedMatchRecord(
            createdAt: Date(),
            durationSeconds: state.elapsedSeconds,
            finalScoreText: state.finalSetsScore,
            setScoresText: state.completedSets.isEmpty ? nil : state.completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: " "),
            detailText: state.setDetailLine,
            photoBookmark: nil,
            source: source,
            idempotencyKey: UUID().uuidString
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

        let history = pointHistory
        pointHistory.removeAll()
        state = rebuilt
        history.forEach { winner in
            pointHistory.append(winner)
            applyPointWon(by: winner)
        }
    }

    private func applyPointWon(by side: PlayerSide) {
        var updated = state
        switch side {
        case .a:
            let result = resolvePoint(winner: updated.playerA, loser: updated.playerB)
            updated.playerA = result.winner
            updated.playerB = result.loser
            if let completed = result.completedSet {
                updated.completedSets.append(SetScore(a: completed.0, b: completed.1))
            }
        case .b:
            let result = resolvePoint(winner: updated.playerB, loser: updated.playerA)
            updated.playerB = result.winner
            updated.playerA = result.loser
            if let completed = result.completedSet {
                updated.completedSets.append(SetScore(a: completed.1, b: completed.0))
            }
        }
        state = updated
    }

    private func resolvePoint(
        winner: PlayerScore,
        loser: PlayerScore
    ) -> (winner: PlayerScore, loser: PlayerScore, completedSet: (Int, Int)?) {
        let winnerPoints = winner.points + 1
        let loserPoints = loser.points
        let winnerTakesGame = winnerPoints >= 4 && winnerPoints - loserPoints >= 2

        if !winnerTakesGame {
            var updatedWinner = winner
            updatedWinner.points = winnerPoints
            return (updatedWinner, loser, nil)
        }

        let winnerGames = winner.games + 1
        let loserGames = loser.games
        let winnerTakesSet = winnerGames >= 6 && winnerGames - loserGames >= 2

        if winnerTakesSet {
            var updatedWinner = winner
            updatedWinner.points = 0
            updatedWinner.games = 0
            updatedWinner.sets += 1

            var updatedLoser = loser
            updatedLoser.points = 0
            updatedLoser.games = 0
            return (updatedWinner, updatedLoser, (winnerGames, loserGames))
        }

        var updatedWinner = winner
        updatedWinner.points = 0
        updatedWinner.games = winnerGames

        var updatedLoser = loser
        updatedLoser.points = 0
        return (updatedWinner, updatedLoser, nil)
    }
}
