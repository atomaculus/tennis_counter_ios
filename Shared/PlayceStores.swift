import Foundation
import WatchConnectivity
import SwiftUI

@MainActor
final class PremiumStore: ObservableObject {
    @Published private(set) var isPremiumUnlocked: Bool
    @Published var message: String?

    private let defaults: UserDefaults
    private let key = "playce.premium.unlocked"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPremiumUnlocked = defaults.bool(forKey: key)
    }

    func unlockPremium() {
        isPremiumUnlocked = true
        defaults.set(true, forKey: key)
        message = "Premium unlocked locally. Replace with StoreKit in production."
    }

    func restorePurchases() {
        isPremiumUnlocked = defaults.bool(forKey: key)
        message = isPremiumUnlocked ? "Premium restored." : "No local purchase found."
    }
}

@MainActor
final class MatchHistoryStore: ObservableObject {
    @Published private(set) var matches: [FinishedMatchRecord] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func upsert(_ record: FinishedMatchRecord) {
        if let existingIndex = matches.firstIndex(where: { $0.idempotencyKey == record.idempotencyKey }) {
            matches[existingIndex] = record
        } else {
            matches.insert(record, at: 0)
        }
        matches.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func updatePhotoBookmark(_ bookmark: Data?, for record: FinishedMatchRecord) {
        guard let index = matches.firstIndex(where: { $0.id == record.id }) else { return }
        matches[index].photoBookmark = bookmark
        save()
    }

    private func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("Playce", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("matches.json")
    }

    private func load() {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([FinishedMatchRecord].self, from: data) else {
            matches = []
            return
        }
        matches = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        let url = storageURL()
        guard let data = try? encoder.encode(matches) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class ConnectivityCoordinator: NSObject, ObservableObject {
    static let shared = ConnectivityCoordinator()

    @Published private(set) var liveMatch: LiveMatchPayload?
    @Published private(set) var syncStatus: String = "Idle"

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private weak var historyStore: MatchHistoryStore?
    private weak var premiumStore: PremiumStore?

    private override init() {
        super.init()
    }

    func configure(historyStore: MatchHistoryStore?, premiumStore: PremiumStore?) {
        self.historyStore = historyStore
        self.premiumStore = premiumStore
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func broadcastLive(snapshot: MatchSnapshot, lastScoredPlayer: PlayerSide?) {
        let payload = LiveMatchPayload(
            snapshot: snapshot,
            lastScoredPlayer: lastScoredPlayer?.rawValue ?? ""
        )
        liveMatch = payload
        syncStatus = "Broadcasting live"
        sendApplicationContext(payload)
    }

    func clearLiveMatch() {
        let payload = LiveMatchPayload(
            snapshot: .init(),
            lastScoredPlayer: "",
            isMatchActive: false
        )
        liveMatch = nil
        sendApplicationContext(payload)
    }

    func queueFinishedMatch(_ record: FinishedMatchRecord) {
        guard let session else { return }
        guard let encoded = try? encoder.encode(record) else {
            syncStatus = "Failed to encode match"
            return
        }

        syncStatus = "Queueing match"
        if session.isReachable {
            session.sendMessageData(encoded, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.syncStatus = "Live send failed, using background transfer"
                }
            }
        }
        session.transferUserInfo(["finishedMatch": encoded])
    }

    private func sendApplicationContext(_ payload: LiveMatchPayload) {
        guard let session else { return }
        guard let encoded = try? encoder.encode(payload) else { return }
        do {
            try session.updateApplicationContext(["liveMatch": encoded])
        } catch {
            syncStatus = "Live sync unavailable"
        }
    }

    private func consumeFinishedMatchData(_ data: Data) {
        guard let record = try? decoder.decode(FinishedMatchRecord.self, from: data) else {
            syncStatus = "Received invalid match"
            return
        }

        guard premiumStore?.isPremiumUnlocked ?? true else {
            syncStatus = "Premium locked: match not stored"
            return
        }

        historyStore?.upsert(record)
        syncStatus = "Match stored"
    }

    private func consumeLiveData(_ data: Data) {
        guard let payload = try? decoder.decode(LiveMatchPayload.self, from: data) else {
            syncStatus = "Received invalid live score"
            return
        }

        if payload.isMatchActive {
            liveMatch = payload
            syncStatus = "Watching live"
        } else {
            liveMatch = nil
            syncStatus = "Idle"
        }
    }
}

extension ConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.syncStatus = "Session error: \(error.localizedDescription)"
            } else {
                self.syncStatus = activationState == .activated ? "Session ready" : "Session pending"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["liveMatch"] as? Data else { return }
        Task { @MainActor in
            self.consumeLiveData(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.consumeFinishedMatchData(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["finishedMatch"] as? Data else { return }
        Task { @MainActor in
            self.consumeFinishedMatchData(data)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
