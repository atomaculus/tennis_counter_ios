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
    /// When non-nil, the match is being decided by a standalone tiebreak
    /// (played instead of a full set after tied sets); value is the points
    /// target (7 or 10). Winning it wins the match regardless of sets won.
    var decidingTiebreakTarget: Int? = nil

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
        !(playerA.points + playerB.points).isMultiple(of: 2)
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

/// A single scored point or deciding-tiebreak-start event, as persisted with a
/// finished match. Mirrors `ScoringEngine.MatchEvent` but flattened for Codable
/// storage (Swift does not allow default values on enum associated values).
struct PointEventRecord: Codable, Hashable {
    let type: String        // "point" | "deciding_tb"
    let isPlayerA: Bool?    // only for type == "point"
    let targetPoints: Int?  // only for type == "deciding_tb"
    let t: Int64            // epoch millis; 0 = unknown

    static let pointType = "point"
    static let decidingTiebreakType = "deciding_tb"

    /// Maps engine-level match events to their persisted representation.
    static func from(_ events: [ScoringEngine.MatchEvent]) -> [PointEventRecord] {
        events.map { event in
            switch event {
            case .point(let isPlayerA, let timestampMillis):
                return PointEventRecord(type: pointType, isPlayerA: isPlayerA, targetPoints: nil, t: timestampMillis)
            case .decidingTiebreakStarted(let targetPoints, let timestampMillis):
                return PointEventRecord(type: decidingTiebreakType, isPlayerA: nil, targetPoints: targetPoints, t: timestampMillis)
            }
        }
    }

    /// Inverse of `from(_:)`: rebuilds engine-level match events from their
    /// persisted representation, e.g. to feed `ScoringEngine.replayEvents`.
    /// Records with an unrecognized `type`, or missing the field their type
    /// requires (`isPlayerA` for `.point`, `targetPoints` for `.decidingTb`),
    /// are skipped rather than crashing, so a record written by a future app
    /// version with an unknown event kind is silently ignored today.
    static func toMatchEvents(_ records: [PointEventRecord]) -> [ScoringEngine.MatchEvent] {
        records.compactMap { record -> ScoringEngine.MatchEvent? in
            switch record.type {
            case pointType:
                guard let isPlayerA = record.isPlayerA else { return nil }
                return .point(isPlayerA: isPlayerA, timestampMillis: record.t)
            case decidingTiebreakType:
                guard let targetPoints = record.targetPoints else { return nil }
                return .decidingTiebreakStarted(targetPoints: targetPoints, timestampMillis: record.t)
            default:
                return nil
            }
        }
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
    // Older records (or ones synced before this field existed) decode these as nil.
    var playerAName: String? = nil
    var playerBName: String? = nil
    // Populated from the HealthKit workout when available at save time; nil otherwise.
    var caloriesKcal: Double? = nil
    var avgHeartRateBpm: Double? = nil
    var maxHeartRateBpm: Double? = nil
    // Full per-point history, added in N1. Records saved before this field
    // existed (or synced from a peer that predates it) decode this as nil.
    var pointEvents: [PointEventRecord]? = nil
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

/// Vertical anchor presets for the movable stat block on a share card.
enum ShareCardAnchor: String, Codable, CaseIterable, Hashable {
    case top
    case center
    case bottom

    /// Vertical placement as a fraction of the card height (0 = top, 1 = bottom).
    var verticalFraction: Double {
        switch self {
        case .top: return 0.20
        case .center: return 0.50
        case .bottom: return 0.80
        }
    }
}

/// User-editable layout + content configuration for a share card.
/// Names are entered at share time because finished matches do not persist them.
struct ShareCardLayout: Codable, Hashable {
    var anchor: ShareCardAnchor = .bottom
    /// Fine-adjustment offset applied on top of the anchor, as a fraction of card size.
    var offsetX: Double = 0
    var offsetY: Double = 0

    var showSetScores: Bool = true
    var showDuration: Bool = true
    var showDate: Bool = false

    var playerAName: String = ""
    var playerBName: String = ""

    var trimmedPlayerA: String { playerAName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedPlayerB: String { playerBName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var showPlayers: Bool { !trimmedPlayerA.isEmpty || !trimmedPlayerB.isEmpty }

    var playersText: String? {
        guard showPlayers else { return nil }
        let left = trimmedPlayerA.isEmpty ? "—" : trimmedPlayerA
        let right = trimmedPlayerB.isEmpty ? "—" : trimmedPlayerB
        return "\(left)  vs  \(right)"
    }

    /// Resets fine offset; used when picking a preset anchor.
    mutating func apply(anchor newAnchor: ShareCardAnchor) {
        anchor = newAnchor
        offsetX = 0
        offsetY = 0
    }
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
    var isTimerRunning: Bool
    var hasTimerStarted: Bool
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
        self.isTimerRunning = snapshot.isTimerRunning
        self.hasTimerStarted = snapshot.hasTimerStarted
        self.isMatchActive = isMatchActive
        self.lastScoredPlayer = lastScoredPlayer
        self.timestamp = timestamp
    }

    init(
        playerAPoints: Int,
        playerAGames: Int,
        playerASets: Int,
        playerBPoints: Int,
        playerBGames: Int,
        playerBSets: Int,
        completedSets: String,
        pointLabelA: String,
        pointLabelB: String,
        elapsedSeconds: Int,
        isTimerRunning: Bool,
        hasTimerStarted: Bool,
        isMatchActive: Bool,
        lastScoredPlayer: String,
        timestamp: Date
    ) {
        self.playerAPoints = playerAPoints
        self.playerAGames = playerAGames
        self.playerASets = playerASets
        self.playerBPoints = playerBPoints
        self.playerBGames = playerBGames
        self.playerBSets = playerBSets
        self.completedSets = completedSets
        self.pointLabelA = pointLabelA
        self.pointLabelB = pointLabelB
        self.elapsedSeconds = elapsedSeconds
        self.isTimerRunning = isTimerRunning
        self.hasTimerStarted = hasTimerStarted
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
    var initialServerIsPlayerA: Bool = true

    enum CodingKeys: String, CodingKey {
        case playerAName
        case playerBName
        case format
        case timestamp
        case initialServerIsPlayerA
    }

    init(
        playerAName: String,
        playerBName: String,
        format: MatchFormat,
        timestamp: Date = Date(),
        initialServerIsPlayerA: Bool = true
    ) {
        self.playerAName = playerAName
        self.playerBName = playerBName
        self.format = format
        self.timestamp = timestamp
        self.initialServerIsPlayerA = initialServerIsPlayerA
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerAName = try container.decode(String.self, forKey: .playerAName)
        playerBName = try container.decode(String.self, forKey: .playerBName)
        format = try container.decode(MatchFormat.self, forKey: .format)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        // Older senders (or the Garmin bridge) may omit this key; default to true.
        initialServerIsPlayerA = try container.decodeIfPresent(Bool.self, forKey: .initialServerIsPlayerA) ?? true
    }
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

enum WatchConfigSendResult {
    case sent
    case queued
    case unavailable

    func merged(with other: WatchConfigSendResult) -> WatchConfigSendResult {
        if self == .sent || other == .sent { return .sent }
        if self == .queued || other == .queued { return .queued }
        return .unavailable
    }
}

/// A single bullet shown in the "What's new" prompt. `title`/`description`
/// are used as localization keys (see `Localizable.strings`), mirroring how
/// `OnboardingPage` content is looked up in `PlayceIOSApp.swift`.
struct WhatsNewEntry: Hashable {
    let title: String
    let description: String
}

/// Content shown in the "What's new" prompt (iOS sheet, watchOS overlay)
/// after an update that changes user-facing behavior. Bump `currentVersion`
/// and replace `entries` whenever a new change needs surfacing to existing
/// users; only the entries for the current version are ever shown.
enum WhatsNewContent {
    static let currentVersion = 2

    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(
            title: "Always-on scoreboard",
            description: "The watch keeps your match on screen during the workout, with a simplified scoreboard when you lower your wrist."
        ),
        WhatsNewEntry(
            title: "Safer undo",
            description: "Press and hold now asks for confirmation before undoing the point."
        )
    ]
}

/// Tracks the last "What's new" version a user has seen, in
/// `playce.whatsnew.lastSeenVersion`. iOS and watchOS each call this with
/// their own (device-local) `UserDefaults.standard`, so the flag is
/// independent per platform even though the code is shared.
enum WhatsNewPrefs {
    private static let lastSeenVersionKey = "playce.whatsnew.lastSeenVersion"

    static func lastSeenVersion(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: lastSeenVersionKey)
    }

    static func shouldShow(currentVersion: Int = WhatsNewContent.currentVersion, defaults: UserDefaults = .standard) -> Bool {
        lastSeenVersion(defaults: defaults) < currentVersion
    }

    static func markSeen(version: Int = WhatsNewContent.currentVersion, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: lastSeenVersionKey)
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

    /// Always-on Display variant of `elapsed(_:)`: no seconds, since AOD
    /// updates at most once a minute. `"h:mm"` once an hour has elapsed,
    /// otherwise `"m min"` (e.g. 754s -> "12 min", 3900s -> "1:05").
    static func elapsedNoSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: NSLocalizedString("%d min", comment: "Elapsed match time without seconds, always-on display"), minutes)
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
