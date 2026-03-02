import Foundation

enum PlayerSide: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
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
    var elapsedSeconds: Int = 0
    var isTimerRunning: Bool = true

    func pointLabel(for side: PlayerSide) -> String {
        switch side {
        case .a:
            return MatchSnapshot.pointLabel(player: playerA.points, rival: playerB.points)
        case .b:
            return MatchSnapshot.pointLabel(player: playerB.points, rival: playerA.points)
        }
    }

    static func pointLabel(player: Int, rival: Int) -> String {
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
