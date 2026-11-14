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
        let matchOver = result.completedSet != nil &&
            (score.decidingTiebreakTarget != nil || winnerSets >= score.format.setsToWin)
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

    /// A scorable match event. Match history must be kept as events (not bare
    /// points) so that undo can also rewind a deciding-tiebreak choice.
    enum MatchEvent: Hashable {
        case point(isPlayerA: Bool, timestampMillis: Int64)
        case decidingTiebreakStarted(targetPoints: Int, timestampMillis: Int64)
    }

    /// Replay a list of match events from a blank score to rebuild match state.
    static func replayEvents(
        _ events: [MatchEvent],
        format: MatchFormat = .standard,
        initialServerIsPlayerA: Bool = true
    ) -> MatchSnapshot {
        var score = MatchSnapshot(format: format, initialServerIsPlayerA: initialServerIsPlayerA)
        for event in events {
            switch event {
            case .point(let isPlayerA, _):
                score = scorePoint(score, isPlayerA: isPlayerA)
            case .decidingTiebreakStarted(let targetPoints, _):
                score = startDecidingTiebreak(score, targetPoints: targetPoints)
            }
        }
        return score
    }

    /// A deciding tiebreak can be offered right after a completed set left the
    /// players tied on sets (any tie: 1-1 in best-of-3 or best-of-5, 2-2 in
    /// best-of-5), before any point of the next set is played.
    static func canOfferDecidingTiebreak(_ score: MatchSnapshot) -> Bool {
        !score.isMatchOver &&
            score.decidingTiebreakTarget == nil &&
            !score.isTiebreak &&
            score.playerA.sets == score.playerB.sets &&
            score.playerA.sets > 0 &&
            score.playerA.games == 0 && score.playerB.games == 0 &&
            score.playerA.points == 0 && score.playerB.points == 0
    }

    /// Replace the upcoming set with a standalone tiebreak to the given points
    /// target (7 = regular, 10 = super). Whoever wins it wins the match.
    /// No-op if the current state does not allow it.
    static func startDecidingTiebreak(_ score: MatchSnapshot, targetPoints: Int) -> MatchSnapshot {
        guard canOfferDecidingTiebreak(score), targetPoints >= 1 else { return score }
        var updated = score
        updated.isTiebreak = true
        updated.decidingTiebreakTarget = targetPoints
        return updated
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
        let targetPoints = score.decidingTiebreakTarget ?? (isSuperTiebreak(score) ? 10 : format.tiebreakPoints)
        let takesTiebreak = winnerPoints >= targetPoints && winnerPoints - loserPoints >= 2

        guard takesTiebreak else {
            var updatedWinner = winner
            updatedWinner.points = winnerPoints
            return PointResult(newWinner: updatedWinner, newLoser: loser)
        }

        // Tiebreak won -> set is won. A regular tiebreak counts as the winning
        // game (7-6); a deciding tiebreak records its own points (e.g. 10-7)
        // so history reads "6-4 | 3-6 | 10-7".
        let isDeciding = score.decidingTiebreakTarget != nil
        let setGamesWinner = isDeciding ? winnerPoints : winner.games + 1
        let setGamesLoser = isDeciding ? loserPoints : loser.games

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

/// Snapshot of an in-progress tennis match, persisted so a killed/relaunched
/// app (watchOS or iOS) can resume exactly where it left off instead of
/// restarting cold at 0-0. See `ScoreboardController.restoreIfAvailable()`.
struct ActiveMatchSessionBlob: Codable {
    var pointEvents: [PointEventRecord]
    var playerAName: String
    var playerBName: String
    var format: MatchFormat
    var initialServerIsPlayerA: Bool
    var updatedAt: Date
    var lastMode: String
    /// Score before `pointEvents` (a fresh match, or the board after Reset Game).
    /// Nil on sessions saved before this field existed; those still replay events
    /// from 0-0. Optional so older blobs decode.
    var baseline: MatchSnapshot? = nil
    /// Nil on sessions saved before the timer was persisted.
    var elapsedSeconds: Int? = nil
    var isTimerRunning: Bool? = nil
    var hasTimerStarted: Bool? = nil
}

/// Device-local (UserDefaults) persistence for the in-progress match. Purely
/// a *live working session* — distinct from `MatchHistoryStore`, which holds
/// finished, saved results — so it is cleared as soon as the match resets or
/// finishes (see `ScoreboardController.resetMatch()`/`finishMatch()`).
enum ActiveMatchSessionStore {
    private static let key = "playce.activeMatchSession"
    /// A session older than this is treated as stale and ignored by `read()`,
    /// e.g. the app was killed mid-match days ago and the score is no longer
    /// meaningfully "current".
    private static let maxAge: TimeInterval = 12 * 60 * 60

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save(
        pointEvents: [PointEventRecord],
        playerAName: String,
        playerBName: String,
        format: MatchFormat,
        initialServerIsPlayerA: Bool,
        lastMode: String,
        baseline: MatchSnapshot? = nil,
        elapsedSeconds: Int? = nil,
        isTimerRunning: Bool? = nil,
        hasTimerStarted: Bool? = nil,
        defaults: UserDefaults = .standard
    ) {
        let blob = ActiveMatchSessionBlob(
            pointEvents: pointEvents,
            playerAName: playerAName,
            playerBName: playerBName,
            format: format,
            initialServerIsPlayerA: initialServerIsPlayerA,
            updatedAt: Date(),
            lastMode: lastMode,
            baseline: baseline,
            elapsedSeconds: elapsedSeconds,
            isTimerRunning: isTimerRunning,
            hasTimerStarted: hasTimerStarted
        )
        guard let data = try? encoder.encode(blob) else { return }
        defaults.set(data, forKey: key)
    }

    /// The persisted session, or nil if there is none or it is older than `maxAge`.
    static func read(defaults: UserDefaults = .standard) -> ActiveMatchSessionBlob? {
        guard let data = defaults.data(forKey: key),
              let blob = try? decoder.decode(ActiveMatchSessionBlob.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(blob.updatedAt) <= maxAge else { return nil }
        return blob
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class ScoreboardController: ObservableObject {
    @Published private(set) var state: MatchSnapshot = .init()
    @Published private(set) var playerAName = "Player A"
    @Published private(set) var playerBName = "Player B"
    @Published private(set) var finishedSummary: MobileFinishedSummary?
    /// True once `restoreIfAvailable()` has successfully rebuilt state from a
    /// persisted `ActiveMatchSessionBlob`. Callers (the mode selector) use
    /// this to skip straight to the scoreboard instead of showing the picker.
    @Published private(set) var didRestoreActiveMatch = false

    private var pointHistory: [ScoringEngine.MatchEvent] = []
    private var baseline = MatchSnapshot()
    private var timer: Timer?
    private var timerAnchor = Date()
    private var elapsedBase = 0
    private var finishedIdempotencyKey = UUID().uuidString

    init() {
        startTicker()
    }

    var canOfferDecidingTiebreak: Bool {
        ScoringEngine.canOfferDecidingTiebreak(state)
    }

    /// True when a match is under way in memory (not yet won/finished) —
    /// used by the mode selector to skip straight to the scoreboard even if
    /// `restoreIfAvailable()` was never called (e.g. app never backgrounded).
    var hasActiveMatchInMemory: Bool {
        !pointHistory.isEmpty && !state.isMatchOver && finishedSummary == nil
    }

    func addPoint(to side: PlayerSide) {
        guard !state.isMatchOver else { return }
        let timestampMillis = Int64(Date().timeIntervalSince1970 * 1000)
        pointHistory.append(.point(isPlayerA: side == .a, timestampMillis: timestampMillis))
        state = ScoringEngine.scorePoint(state, isPlayerA: side == .a)
        persistActiveSession()
        if state.isMatchOver {
            finishMatch()
        }
    }

    @discardableResult
    func undoLastPoint(for side: PlayerSide) -> Bool {
        let isPlayerA = side == .a
        guard let index = pointHistory.lastIndex(where: { event in
            if case .point(let eventIsPlayerA, _) = event { return eventIsPlayerA == isPlayerA }
            return false
        }) else {
            return false
        }
        pointHistory.remove(at: index)
        rebuildFromHistory()
        persistActiveSession()
        return true
    }

    /// Offers to end the upcoming set as a standalone tiebreak (see
    /// `ScoringEngine.canOfferDecidingTiebreak`). No-op if not currently offerable.
    func startDecidingTiebreak(targetPoints: Int) {
        guard ScoringEngine.canOfferDecidingTiebreak(state) else { return }
        let timestampMillis = Int64(Date().timeIntervalSince1970 * 1000)
        pointHistory.append(.decidingTiebreakStarted(targetPoints: targetPoints, timestampMillis: timestampMillis))
        state = ScoringEngine.startDecidingTiebreak(state, targetPoints: targetPoints)
        persistActiveSession()
    }

    /// Restores an in-progress match persisted by a previous run of the app
    /// (see `ActiveMatchSessionStore`), replaying its events to rebuild
    /// state. No-op (returns false) if there is nothing to restore, the
    /// stored session is stale, or a match is already under way here — never
    /// clobber live in-memory state with a disk copy.
    @discardableResult
    func restoreIfAvailable() -> Bool {
        guard pointHistory.isEmpty, finishedSummary == nil,
              let blob = ActiveMatchSessionStore.read() else {
            return false
        }

        let events = PointEventRecord.toMatchEvents(blob.pointEvents)
        pointHistory = events
        // Reset Game keeps sets and games on `baseline` and drops point history.
        // Replaying events from 0-0 would bring those points back and lose the sets.
        baseline = blob.baseline ?? MatchSnapshot(
            format: blob.format,
            initialServerIsPlayerA: blob.initialServerIsPlayerA
        )
        let elapsed = blob.elapsedSeconds ?? 0
        elapsedBase = elapsed
        timerAnchor = Date()
        var rebuilt = baseline
        rebuilt.elapsedSeconds = elapsed
        rebuilt.isTimerRunning = blob.isTimerRunning ?? false
        rebuilt.hasTimerStarted = blob.hasTimerStarted ?? false
        state = pointHistory.reduce(rebuilt) { score, event in
            switch event {
            case .point(let isPlayerA, _):
                return ScoringEngine.scorePoint(score, isPlayerA: isPlayerA)
            case .decidingTiebreakStarted(let targetPoints, _):
                return ScoringEngine.startDecidingTiebreak(score, targetPoints: targetPoints)
            }
        }
        playerAName = Self.normalizedPlayerName(blob.playerAName, fallback: "Player A")
        playerBName = Self.normalizedPlayerName(blob.playerBName, fallback: "Player B")
        didRestoreActiveMatch = true
        return true
    }

    func setInitialServer(isPlayerA: Bool) {
        guard pointHistory.isEmpty, finishedSummary == nil else { return }
        state.initialServerIsPlayerA = isPlayerA
        baseline.initialServerIsPlayerA = isPlayerA
        // Setup applies the server after names and format, and those earlier
        // saves would otherwise keep the previous server in the session blob.
        persistActiveSession()
    }

    func resetGame() {
        pointHistory.removeAll()
        baseline = state
        baseline.playerA.points = 0
        baseline.playerB.points = 0
        baseline.isTiebreak = false
        baseline.decidingTiebreakTarget = nil
        state.playerA.points = 0
        state.playerB.points = 0
        state.isTiebreak = false
        state.decidingTiebreakTarget = nil
        // History is empty and the remaining score lives on `baseline`. Persist
        // that, or the next launch replays the pre-reset points.
        persistActiveSession()
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
        didRestoreActiveMatch = false
        ActiveMatchSessionStore.clear()
    }

    func setPlayerNames(_ playerAName: String, _ playerBName: String) {
        self.playerAName = Self.normalizedPlayerName(playerAName, fallback: "Player A")
        self.playerBName = Self.normalizedPlayerName(playerBName, fallback: "Player B")
        persistActiveSession()
    }

    func setMatchFormat(_ format: MatchFormat) {
        guard pointHistory.isEmpty, finishedSummary == nil else { return }
        state.format = format
        baseline.format = format
        persistActiveSession()
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
        persistActiveSession()
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
        } else if current.isMatchOver {
            // Match decided on the last completed set: the residual 0-0 game adds nothing.
            detail = completed
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
        ActiveMatchSessionStore.clear()
    }

    func finishMatchRecord(
        source: String,
        caloriesKcal: Double? = nil,
        avgHeartRateBpm: Double? = nil,
        maxHeartRateBpm: Double? = nil
    ) -> FinishedMatchRecord {
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
            idempotencyKey: finishedIdempotencyKey,
            playerAName: playerAName,
            playerBName: playerBName,
            caloriesKcal: caloriesKcal,
            avgHeartRateBpm: avgHeartRateBpm,
            maxHeartRateBpm: maxHeartRateBpm,
            pointEvents: PointEventRecord.from(pointHistory)
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
            persistActiveSession()
        }
    }

    /// Writes the current match to `ActiveMatchSessionStore` so a relaunch
    /// can resume it (see `restoreIfAvailable()`). Also called once a second
    /// while the match timer is running, so the saved elapsed time stays current.
    private func currentElapsedSeconds() -> Int {
        guard state.isTimerRunning else { return state.elapsedSeconds }
        return elapsedBase + Int(Date().timeIntervalSince(timerAnchor))
    }

    private func persistActiveSession() {
        ActiveMatchSessionStore.save(
            pointEvents: PointEventRecord.from(pointHistory),
            playerAName: playerAName,
            playerBName: playerBName,
            format: state.format,
            initialServerIsPlayerA: state.initialServerIsPlayerA,
            lastMode: PlayMode.match.rawValue,
            baseline: baseline,
            elapsedSeconds: currentElapsedSeconds(),
            isTimerRunning: state.isTimerRunning,
            hasTimerStarted: state.hasTimerStarted
        )
    }

    private func rebuildFromHistory() {
        var rebuilt = baseline
        rebuilt.elapsedSeconds = state.elapsedSeconds
        rebuilt.isTimerRunning = state.isTimerRunning
        rebuilt.hasTimerStarted = state.hasTimerStarted
        state = pointHistory.reduce(rebuilt) { score, event in
            switch event {
            case .point(let isPlayerA, _):
                return ScoringEngine.scorePoint(score, isPlayerA: isPlayerA)
            case .decidingTiebreakStarted(let targetPoints, _):
                return ScoringEngine.startDecidingTiebreak(score, targetPoints: targetPoints)
            }
        }
    }

    private static func normalizedPlayerName(_ rawValue: String, fallback: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(12))
    }
}
