import Foundation

/// A completed practice/training session outside a scored match (paredón,
/// veintiuno, ...). Mirrors `FinishedMatchRecord`'s role for `MatchHistoryStore`
/// but is deliberately simpler: no sync, no photo, no idempotency key, since
/// training sessions are device-local only (see `TrainingHistoryStore`).
struct TrainingSession: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    let modality: String        // "paredon" | "veintiuno"
    let createdAt: Date
    let durationSeconds: Int
    let targetPoints: Int       // 21 for veintiuno (field requested by product); 0 for paredón
    let finalCount: Int
    let bestStreak: Int
    let attempts: Int

    enum Modality {
        static let paredon = "paredon"
        static let veintiuno = "veintiuno"
    }
}

struct TrainingHistoryArchive: Codable, Hashable {
    var version: Int
    var sessions: [TrainingSession]
}

/// Device-local JSON store for `TrainingSession`s, mirroring the
/// `MatchHistoryStore` pattern in `PlayceStores.swift` (versioned archive file
/// under Application Support, load/save on mutation) but without any of the
/// WatchConnectivity sync machinery: training sessions are never sent between
/// iPhone and Watch, each device keeps its own history.
@MainActor
final class TrainingHistoryStore: ObservableObject {
    @Published private(set) var sessions: [TrainingSession] = []

    /// Oldest sessions beyond this count are dropped on every append, mirroring
    /// the cap requested for this store (there is no equivalent cap on
    /// `MatchHistoryStore`, which keeps full match history).
    private let maxStoredSessions = 200

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let customStorageURL: URL?
    private let archiveVersion = 1

    init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func append(_ session: TrainingSession) {
        sessions.insert(session, at: 0)
        sessions.sort { $0.createdAt > $1.createdAt }
        if sessions.count > maxStoredSessions {
            sessions.removeLast(sessions.count - maxStoredSessions)
        }
        save()
    }

    private func storageURL() -> URL {
        if let customStorageURL { return customStorageURL }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("Playce", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("trainings.json")
    }

    private func load() {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url),
              let archive = try? decoder.decode(TrainingHistoryArchive.self, from: data) else {
            sessions = []
            return
        }
        sessions = archive.sessions.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let archive = TrainingHistoryArchive(version: archiveVersion, sessions: sessions)
        guard let data = try? encoder.encode(archive) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The three things a user can do from the on-device mode selector, shared by
/// the watchOS `ModeSelectView` and the iOS "Play" tab's selection screen.
enum PlayMode: String, Codable, CaseIterable {
    case match
    case wall
    case veintiuno
}

/// Remembers the last mode picked from the selector, per device (each of
/// iPhone/Watch calls this with its own local `UserDefaults.standard`, so the
/// "last used" highlight is independent per platform — mirrors `WhatsNewPrefs`).
enum PlayModePrefs {
    private static let lastModeKey = "playce.play.lastMode"

    static func lastMode(defaults: UserDefaults = .standard) -> PlayMode {
        guard let raw = defaults.string(forKey: lastModeKey), let mode = PlayMode(rawValue: raw) else {
            return .match
        }
        return mode
    }

    static func setLastMode(_ mode: PlayMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: lastModeKey)
    }
}
