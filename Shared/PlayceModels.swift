import Foundation

enum PlayerSide: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
}

struct MatchFormat: Codable, Hashable, Equatable {
    var setsToWin: Int = 2
    var tiebreakAtSixAll: Bool = true
    var tiebreakPoints: Int = 7
    var superTiebreakInFinalSet: Bool = false
    var noAdScoring: Bool = false

    static let standard = MatchFormat()
    static let grandSlam = MatchFormat(setsToWin: 3)
    static let fast4 = MatchFormat(superTiebreakInFinalSet: true, noAdScoring: true)
}

enum FormatPreset: String, CaseIterable, Identifiable {
    case standard
    case grandSlam
    case fast4

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .grandSlam: return "Grand Slam"
        case .fast4: return "Fast4"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Best of 3"
        case .grandSlam: return "Best of 5"
        case .fast4: return "No-Ad + STB"
        }
    }

    var format: MatchFormat {
        switch self {
        case .standard: return .standard
        case .grandSlam: return .grandSlam
        case .fast4: return .fast4
        }
    }
}

struct SetScore: Codable, Hashable {
    let a: Int
    let b: Int
}

struct PlayerScore: Codable, Hashable {
    var points: Int = 0
    var games: Int = 0
    var sets: Int = 0
}

struct MatchSnapshot: Codable, Hashable {
    var playerA: PlayerScore = .init()
    var playerB: PlayerScore = .init()
    var completedSets: [SetScore] = []
    var isTiebreak: Bool = false
    var isMatchOver: Bool = false
    var format: MatchFormat = .standard
    var initialServerIsPlayerA: Bool = true
    var elapsedSeconds: Int = 0
    var isTimerRunning: Bool = false
    var hasTimerStarted: Bool = false

    func pointLabel(for side: PlayerSide) -> String {
        switch side {
        case .a:
            return MatchSnapshot.pointLabel(player: playerA.points, rival: playerB.points, isTiebreak: isTiebreak)
        case .b:
            return MatchSnapshot.pointLabel(player: playerB.points, rival: playerA.points, isTiebreak: isTiebreak)
        }
    }

    static func pointLabel(player: Int, rival: Int, isTiebreak: Bool) -> String {
        if isTiebreak { return "\(player)" }

        let labels = ["0", "15", "30", "40", "AD"]
        if player >= 3 && rival >= 3 {
            if player == rival { return "40" }
            if player == rival + 1 { return "AD" }
            return "40"
        }
        return labels[max(0, min(player, 4))]
    }

    var finalSetsScore: String {
        "\(playerA.sets)-\(playerB.sets)"
    }

    var setDetailLine: String {
        let completed = completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: " ")
        let live = "G \(playerA.games)-\(playerB.games) P \(pointLabel(for: .a))-\(pointLabel(for: .b))"
        return completed.isEmpty ? live : "\(completed) | \(live)"
    }

    var currentServerIsPlayerA: Bool {
        let completedGames = completedSets.reduce(0) { $0 + $1.a + $1.b }
        let totalGamesPlayed = completedGames + playerA.games + playerB.games

        if isTiebreak {
            let tiebreakPoints = playerA.points + playerB.points
            let serverChanges = tiebreakPoints == 0 ? 0 : ((tiebreakPoints - 1) / 2) + 1
            let baseServer = totalGamesPlayed.isMultiple(of: 2) ? initialServerIsPlayerA : !initialServerIsPlayerA
            return serverChanges.isMultiple(of: 2) ? baseServer : !baseServer
        }

        return totalGamesPlayed.isMultiple(of: 2) ? initialServerIsPlayerA : !initialServerIsPlayerA
    }

    var serveStartsOnLeftSide: Bool {
        (playerA.points + playerB.points).isMultiple(of: 2)
    }
}

struct MobileFinishedSummary: Hashable {
    var createdAt: Date
    var durationSeconds: Int
    var setsScore: String
    var setsDetail: String
    var playerAName: String
    var playerBName: String
}

struct FinishedMatchRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date
    var durationSeconds: Int
    var finalScoreText: String
    var setScoresText: String?
    var detailText: String
    var photoBookmark: Data?
    var source: String
    var idempotencyKey: String
}

struct MatchHistoryArchive: Codable, Hashable {
    var version: Int
    var matches: [FinishedMatchRecord]
}

struct MatchStats: Codable, Hashable {
    var totalMatches: Int = 0
    var totalPlayTimeSeconds: Int = 0
    var avgDurationSeconds: Int = 0
    var longestMatchSeconds: Int = 0
    var shortestMatchSeconds: Int = 0
    var playerAWins: Int = 0
    var playerBWins: Int = 0

    static func calculate(from matches: [FinishedMatchRecord]) -> MatchStats {
        guard !matches.isEmpty else { return MatchStats() }

        let durations = matches.map(\.durationSeconds)
        let totalDuration = durations.reduce(0, +)
        let winners = matches.map { MatchStats.winnerSide(for: $0.finalScoreText) }

        return MatchStats(
            totalMatches: matches.count,
            totalPlayTimeSeconds: totalDuration,
            avgDurationSeconds: totalDuration / matches.count,
            longestMatchSeconds: durations.max() ?? 0,
            shortestMatchSeconds: durations.min() ?? 0,
            playerAWins: winners.filter { $0 == .a }.count,
            playerBWins: winners.filter { $0 == .b }.count
        )
    }

    static func winnerSide(for finalScoreText: String) -> PlayerSide? {
        let parts = finalScoreText
            .split(separator: "-")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 2, parts[0] != parts[1] else { return nil }
        return parts[0] > parts[1] ? .a : .b
    }
}

struct MatchShareCardData: Codable, Hashable {
    static let exportWidth = 1080
    static let exportHeight = 1920

    var scoreText: String
    var setScoresText: String?
    var durationText: String
    var dateText: String
    var brandText: String = "Tracked with PLAYCE"

    init(record: FinishedMatchRecord) {
        self.scoreText = record.finalScoreText
        self.setScoresText = record.setScoresText
        self.durationText = MatchShareCardData.formatDuration(record.durationSeconds)
        self.dateText = MatchShareCardData.formatDate(record.createdAt)
    }

    static func formatDate(_ date: Date) -> String {
        shareDateFormatter.string(from: date)
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var displayScore: String {
        scoreText.replacingOccurrences(of: " ", with: "\n")
    }

    var displaySetScores: String? {
        guard let setScoresText else { return nil }
        let normalized = setScoresText
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "  ·  ")
        return normalized.isEmpty ? nil : normalized
    }

    private static let shareDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        formatter.locale = Locale.current
        return formatter
    }()
}

struct LiveMatchPayload: Codable, Hashable {
    var playerAPoints: Int
    var playerAGames: Int
    var playerASets: Int
    var playerBPoints: Int
    var playerBGames: Int
    var playerBSets: Int
    var completedSets: String
    var pointLabelA: String
    var pointLabelB: String
    var elapsedSeconds: Int
    var isMatchActive: Bool
    var lastScoredPlayer: String
    var timestamp: Date

    init(
        snapshot: MatchSnapshot,
        lastScoredPlayer: String,
        isMatchActive: Bool = true,
        timestamp: Date = Date()
    ) {
        self.playerAPoints = snapshot.playerA.points
        self.playerAGames = snapshot.playerA.games
        self.playerASets = snapshot.playerA.sets
        self.playerBPoints = snapshot.playerB.points
        self.playerBGames = snapshot.playerB.games
        self.playerBSets = snapshot.playerB.sets
        self.completedSets = snapshot.completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: ",")
        self.pointLabelA = snapshot.pointLabel(for: .a)
        self.pointLabelB = snapshot.pointLabel(for: .b)
        self.elapsedSeconds = snapshot.elapsedSeconds
        self.isMatchActive = isMatchActive
        self.lastScoredPlayer = lastScoredPlayer
        self.timestamp = timestamp
    }
}

struct MatchConfigPayload: Codable, Hashable {
    var playerAName: String
    var playerBName: String
    var format: MatchFormat
    var timestamp: Date = Date()
}

struct MatchSyncAckPayload: Codable, Hashable {
    var idempotencyKey: String
    var status: String
    var timestamp: Date = Date()
}

struct PendingFinishedMatch: Codable, Hashable {
    var record: FinishedMatchRecord
    var attemptCount: Int = 0
    var nextRetryAt: Date = Date()
    var lastStatus: String = "Pending"
}

enum PlayceFormatting {
    static func elapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func elapsedLong(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    static func completedSets(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " | ")
    }
}
