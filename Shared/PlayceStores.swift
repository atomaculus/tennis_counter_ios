import Foundation
import StoreKit
import WatchConnectivity
import SwiftUI

@MainActor
final class PremiumStore: ObservableObject {
    static let premiumProductID = "premium_unlock"

    @Published private(set) var isPremiumUnlocked: Bool
    @Published private(set) var isBillingReady: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var isPurchaseInProgress: Bool = false
    @Published private(set) var productPriceLabel: String?
    @Published var message: String?

    private let defaults: UserDefaults
    private let key = "playce.premium.unlocked"
    private var product: Product?
    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isPremiumUnlocked = defaults.bool(forKey: key)
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true
        observeTransactionUpdates()
        await refreshEntitlements()
        await loadProducts()
        isLoading = false
    }

    func unlockPremium() {
        Task { await purchasePremium() }
    }

    func restorePurchases() {
        Task { await restoreStoreKitPurchases() }
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.premiumProductID])
            product = products.first
            productPriceLabel = product?.displayPrice
            isBillingReady = product != nil
            if product == nil {
#if DEBUG
                message = isPremiumUnlocked ? nil : Self.localized("Premium can be unlocked locally in Debug.")
#else
                message = Self.localized("Premium is not available yet. Try again later.")
#endif
            }
        } catch {
            isBillingReady = false
#if DEBUG
            message = isPremiumUnlocked ? nil : Self.localized("Premium can be unlocked locally in Debug.")
#else
            message = Self.localized("Could not load premium price.")
#endif
        }
    }

    private func purchasePremium() async {
        clearMessage()
        guard let product else {
#if DEBUG
            setPremiumUnlocked(true)
            message = Self.localized("Premium unlocked locally for Debug. Configure StoreKit/App Store Connect for production.")
#else
            message = Self.localized("Premium is not available yet. Try again later.")
            await loadProducts()
#endif
            return
        }

        isPurchaseInProgress = true
        defer { isPurchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = verifiedTransaction(from: verification) {
                    setPremiumUnlocked(true)
                    message = Self.localized("Premium unlocked.")
                    await transaction.finish()
                } else {
                    message = Self.localized("Purchase could not be verified.")
                }
            case .userCancelled:
                message = Self.localized("Purchase canceled.")
            case .pending:
                message = Self.localized("Purchase is pending approval.")
            @unknown default:
                message = Self.localized("Purchase failed.")
            }
        } catch {
            message = Self.localized("Purchase failed.")
        }
    }

    private func restoreStoreKitPurchases() async {
        clearMessage()
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremiumUnlocked ? Self.localized("Premium restored.") : Self.localized("No active premium purchase found.")
        } catch {
            message = Self.localized("Could not restore purchases.")
        }
    }

    private func refreshEntitlements() async {
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(from: entitlement),
                  transaction.productID == Self.premiumProductID else {
                continue
            }
            unlocked = true
        }
        if unlocked || !defaults.bool(forKey: key) {
            setPremiumUnlocked(unlocked)
        }
    }

    private func observeTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(update)
            }
        }
    }

    private func handleTransactionUpdate(_ verification: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = verifiedTransaction(from: verification),
              transaction.productID == Self.premiumProductID else {
            return
        }
        setPremiumUnlocked(true)
        await transaction.finish()
    }

    private func verifiedTransaction(from verification: VerificationResult<StoreKit.Transaction>) -> StoreKit.Transaction? {
        switch verification {
        case .verified(let transaction):
            return transaction
        case .unverified:
            return nil
        }
    }

    private func setPremiumUnlocked(_ value: Bool) {
        isPremiumUnlocked = value
        defaults.set(value, forKey: key)
    }

    private func clearMessage() {
        message = nil
    }

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}

@MainActor
final class MatchHistoryStore: ObservableObject {
    @Published private(set) var matches: [FinishedMatchRecord] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let customStorageURL: URL?
    private let archiveVersion = 1

    init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL
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

    func contains(idempotencyKey: String) -> Bool {
        matches.contains { $0.idempotencyKey == idempotencyKey }
    }

    var stats: MatchStats {
        MatchStats.calculate(from: matches)
    }

    func record(id: FinishedMatchRecord.ID) -> FinishedMatchRecord? {
        matches.first { $0.id == id }
    }

    func delete(_ record: FinishedMatchRecord) {
        matches.removeAll { $0.id == record.id }
        if let photoURL = photoURL(for: record) {
            try? FileManager.default.removeItem(at: photoURL)
        }
        save()
    }

    func delete(at offsets: IndexSet) {
        let records = offsets.compactMap { index in
            matches.indices.contains(index) ? matches[index] : nil
        }
        records.forEach(delete)
    }

    func updatePhotoBookmark(_ bookmark: Data?, for record: FinishedMatchRecord) {
        guard let index = matches.firstIndex(where: { $0.id == record.id }) else { return }
        if bookmark == nil, let photoURL = photoURL(for: matches[index]) {
            try? FileManager.default.removeItem(at: photoURL)
        }
        matches[index].photoBookmark = bookmark
        save()
    }

    func attachPhotoData(_ data: Data, fileExtension: String, to record: FinishedMatchRecord) throws {
        guard let index = matches.firstIndex(where: { $0.id == record.id }) else { return }
        let safeExtension = fileExtension.isEmpty ? "jpg" : fileExtension
        let destinationURL = photosFolderURL().appendingPathComponent("\(record.id.uuidString).\(safeExtension)")
        if let existingURL = photoURL(for: matches[index]), existingURL != destinationURL {
            try? FileManager.default.removeItem(at: existingURL)
        }
        try data.write(to: destinationURL, options: .atomic)
        matches[index].photoBookmark = Data(destinationURL.path.utf8)
        save()
    }

    func photoURL(for record: FinishedMatchRecord) -> URL? {
        guard let bookmark = record.photoBookmark,
              let path = String(data: bookmark, encoding: .utf8) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func storageURL() -> URL {
        if let customStorageURL { return customStorageURL }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("Playce", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("matches.json")
    }

    private func photosFolderURL() -> URL {
        let folder = storageURL().deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func load() {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url) else {
            matches = []
            return
        }

        if let archive = try? decoder.decode(MatchHistoryArchive.self, from: data) {
            matches = archive.matches.sorted { $0.createdAt > $1.createdAt }
            return
        }

        if let legacyMatches = try? decoder.decode([FinishedMatchRecord].self, from: data) {
            matches = legacyMatches.sorted { $0.createdAt > $1.createdAt }
            save()
            return
        }

        matches = []
    }

    private func save() {
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let archive = MatchHistoryArchive(version: archiveVersion, matches: matches)
        guard let data = try? encoder.encode(archive) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum MatchCSVExporter {
    static let header = "Date,Score,Sets Detail,Duration (min)"

    static func csvString(for matches: [FinishedMatchRecord]) -> String {
        var rows = [header]
        rows.append(contentsOf: matches.map(csvRow))
        return rows.joined(separator: "\n") + "\n"
    }

    static func export(matches: [FinishedMatchRecord], date: Date = Date()) throws -> URL? {
        guard !matches.isEmpty else { return nil }
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("playce-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let fileName = "playce_matches_\(Int(date.timeIntervalSince1970 * 1000)).csv"
        let url = exportDir.appendingPathComponent(fileName)
        try csvString(for: matches).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvRow(for match: FinishedMatchRecord) -> String {
        [
            exportDateFormatter.string(from: match.createdAt),
            match.finalScoreText,
            match.setScoresText ?? "",
            String(format: "%.1f", Double(match.durationSeconds) / 60.0)
        ].map(escape).joined(separator: ",")
    }

    private static func escape(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ",", with: ";")
        if normalized.contains("\"") {
            return "\"\(normalized.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return normalized
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale.current
        return formatter
    }()
}

@MainActor
final class ConnectivityCoordinator: NSObject, ObservableObject {
    static let shared = ConnectivityCoordinator()

    @Published private(set) var liveMatch: LiveMatchPayload?
    @Published private(set) var receivedMatchConfig: MatchConfigPayload?
    @Published private(set) var syncStatus: String = "Idle"
    @Published private(set) var pendingFinishedMatch: PendingFinishedMatch?

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let pendingDefaultsKey = "playce.sync.pendingFinishedMatch"

    private weak var historyStore: MatchHistoryStore?
    private weak var premiumStore: PremiumStore?
    private var retryTimer: Timer?

    private override init() {
        super.init()
    }

    func configure(historyStore: MatchHistoryStore?, premiumStore: PremiumStore?) {
        self.historyStore = historyStore
        self.premiumStore = premiumStore
        loadPendingFinishedMatch()
        startRetryTicker()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        retryPendingFinishedMatch(force: true, reason: "activate")
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

    @discardableResult
    func sendMatchConfig(playerAName: String, playerBName: String, format: MatchFormat) -> WatchConfigSendResult {
        guard let session else {
            syncStatus = "WatchConnectivity unavailable"
            return .unavailable
        }

        guard session.activationState == .activated else {
            syncStatus = "Session pending"
            return .unavailable
        }

#if os(iOS)
        guard session.isPaired else {
            syncStatus = "Watch not paired"
            return .unavailable
        }

        guard session.isWatchAppInstalled else {
            syncStatus = "Watch app unavailable"
            return .unavailable
        }
#endif

        let payload = MatchConfigPayload(
            playerAName: playerAName,
            playerBName: playerBName,
            format: format
        )
        guard let encoded = try? encoder.encode(payload) else {
            syncStatus = "Failed to encode config"
            return .unavailable
        }

        do {
            try session.updateApplicationContext(["matchConfig": encoded])
        } catch {
            syncStatus = "Config sync unavailable"
            return .unavailable
        }

        if session.isReachable {
            syncStatus = "Config sent to Watch"
            session.sendMessageData(encoded, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.syncStatus = "Config queued for Watch"
                }
            }
            return .sent
        }

        syncStatus = "Config queued for Watch"
        return .queued
    }

    func consumeMatchConfig() {
        receivedMatchConfig = nil
    }

    func queueFinishedMatch(_ record: FinishedMatchRecord) {
        guard let session else { return }
        pendingFinishedMatch = PendingFinishedMatch(record: record, lastStatus: session.isReachable ? "Sending" : "Queued offline")
        savePendingFinishedMatch()
        retryPendingFinishedMatch(force: true, reason: "queue")
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

    private func sendApplicationContext(_ payload: MatchConfigPayload) {
        guard let session else { return }
        guard let encoded = try? encoder.encode(payload) else { return }
        do {
            try session.updateApplicationContext(["matchConfig": encoded])
        } catch {
            syncStatus = "Config sync unavailable"
        }
    }

    private func sendApplicationContext(_ payload: MatchSyncAckPayload) {
        guard let session else { return }
        guard let encoded = try? encoder.encode(payload) else { return }
        do {
            try session.updateApplicationContext(["matchAck": encoded])
        } catch {
            syncStatus = "ACK sync unavailable"
        }
    }

    @discardableResult
    private func consumeFinishedMatchData(_ data: Data) -> MatchSyncAckPayload? {
        guard let record = try? decoder.decode(FinishedMatchRecord.self, from: data) else {
            syncStatus = "Received invalid match"
            return nil
        }

        guard premiumStore?.isPremiumUnlocked ?? true else {
            syncStatus = "Premium locked: match not stored"
            return MatchSyncAckPayload(idempotencyKey: record.idempotencyKey, status: "premium_locked")
        }

        let wasDuplicate = historyStore?.contains(idempotencyKey: record.idempotencyKey) ?? false
        historyStore?.upsert(record)
        let status = wasDuplicate ? "duplicate" : "inserted"
        syncStatus = wasDuplicate ? "Duplicate match ignored" : "Match stored"
        return MatchSyncAckPayload(idempotencyKey: record.idempotencyKey, status: status)
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

    private func consumeMatchConfigData(_ data: Data) {
        guard let payload = try? decoder.decode(MatchConfigPayload.self, from: data) else {
            syncStatus = "Received invalid config"
            return
        }

        receivedMatchConfig = payload
        syncStatus = "Config received"
    }

    private func consumeAckData(_ data: Data) {
        guard let ack = try? decoder.decode(MatchSyncAckPayload.self, from: data) else {
            syncStatus = "Received invalid ACK"
            return
        }
        clearPendingFinishedMatchIfNeeded(idempotencyKey: ack.idempotencyKey, status: ack.status)
    }

    private func retryPendingFinishedMatch(force: Bool = false, reason: String) {
        guard var pending = pendingFinishedMatch else { return }
        guard let session else {
            syncStatus = "WatchConnectivity unavailable"
            return
        }
        let now = Date()
        guard force || now >= pending.nextRetryAt else {
            syncStatus = pending.lastStatus
            return
        }
        guard let encoded = try? encoder.encode(pending.record) else {
            syncStatus = "Failed to encode match"
            return
        }

        pending.attemptCount += 1
        pending.lastStatus = session.isReachable ? "Sending match" : "Queued, waiting for device"
        pending.nextRetryAt = now.addingTimeInterval(retryDelay(forAttempt: pending.attemptCount))
        pendingFinishedMatch = pending
        savePendingFinishedMatch()
        syncStatus = pending.lastStatus

        if session.isReachable {
            session.sendMessageData(encoded) { [weak self] replyData in
                Task { @MainActor in
                    self?.consumeAckData(replyData)
                }
            } errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.markPendingRetryScheduled(status: "Send failed, retry scheduled")
                }
            }
        }

        session.transferUserInfo(["finishedMatch": encoded])
        if !session.isReachable {
            markPendingRetryScheduled(status: "Queued for background transfer")
        }
    }

    private func markPendingRetryScheduled(status: String) {
        guard var pending = pendingFinishedMatch else { return }
        pending.lastStatus = status
        pending.nextRetryAt = Date().addingTimeInterval(retryDelay(forAttempt: pending.attemptCount))
        pendingFinishedMatch = pending
        syncStatus = status
        savePendingFinishedMatch()
    }

    private func clearPendingFinishedMatchIfNeeded(idempotencyKey: String, status: String) {
        guard pendingFinishedMatch?.record.idempotencyKey == idempotencyKey else {
            syncStatus = "ACK \(status)"
            return
        }
        pendingFinishedMatch = nil
        savePendingFinishedMatch()
        syncStatus = "Match sync \(status)"
    }

    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let capped = max(0, min(attempt, 4))
        return TimeInterval(5 * (1 << capped))
    }

    private func startRetryTicker() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.retryPendingFinishedMatch(reason: "timer")
            }
        }
    }

    private func loadPendingFinishedMatch() {
        guard let data = UserDefaults.standard.data(forKey: pendingDefaultsKey),
              let pending = try? decoder.decode(PendingFinishedMatch.self, from: data) else {
            pendingFinishedMatch = nil
            return
        }
        pendingFinishedMatch = pending
    }

    private func savePendingFinishedMatch() {
        if let pendingFinishedMatch,
           let data = try? encoder.encode(pendingFinishedMatch) {
            UserDefaults.standard.set(data, forKey: pendingDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
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
                guard activationState == .activated else {
                    self.syncStatus = "Session pending"
                    return
                }
#if os(iOS)
                if !session.isPaired {
                    self.syncStatus = "Watch not paired"
                } else if !session.isWatchAppInstalled {
                    self.syncStatus = "Watch app unavailable"
                } else if session.isReachable {
                    self.syncStatus = "Watch reachable"
                } else {
                    self.syncStatus = "Watch not reachable"
                }
#else
                self.syncStatus = session.isReachable ? "iPhone reachable" : "iPhone not reachable"
#endif
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let liveData = applicationContext["liveMatch"] as? Data
        let configData = applicationContext["matchConfig"] as? Data
        let ackData = applicationContext["matchAck"] as? Data
        Task { @MainActor in
            if let liveData {
                self.consumeLiveData(liveData)
            }
            if let configData {
                self.consumeMatchConfigData(configData)
            }
            if let ackData {
                self.consumeAckData(ackData)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            if (try? self.decoder.decode(MatchConfigPayload.self, from: messageData)) != nil {
                self.consumeMatchConfigData(messageData)
            } else {
                self.consumeFinishedMatchData(messageData)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        Task { @MainActor in
            if let ack = self.consumeFinishedMatchData(messageData),
               let data = try? self.encoder.encode(ack) {
                replyHandler(data)
                self.sendApplicationContext(ack)
            } else {
                replyHandler(Data())
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["finishedMatch"] as? Data else { return }
        Task { @MainActor in
            if let ack = self.consumeFinishedMatchData(data) {
                self.sendApplicationContext(ack)
            }
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
