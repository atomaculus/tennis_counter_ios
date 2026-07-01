import Foundation
@preconcurrency import ConnectIQ

enum GarminSdkState: String {
    case uninitialized
    case ready
    case selectingDevices
    case connectMobileRequired
    case noDevices
    case error
}

struct GarminDeviceSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var model: String
    var status: String
}

@MainActor
final class GarminConnectivityCoordinator: NSObject, ObservableObject {
    static let shared = GarminConnectivityCoordinator()

    @Published private(set) var sdkState: GarminSdkState = .uninitialized
    @Published private(set) var devices: [GarminDeviceSummary] = []
    @Published private(set) var connectedDeviceCount: Int = 0
    @Published private(set) var statusMessage: String = "Garmin not connected"

    private static let appID = "c4f18a72-b93e-4d6f-a1c8-e5b2079d3a44"
    private static let urlScheme = "playce-ciq"
    private static let stateRestorationIdentifier = "com.agm.playce.connectiq"

    private enum Keys {
        static let path = "path"
        static let kind = "kind"
        static let payload = "payload"
        static let idempotencyKey = "idempotencyKey"
        static let timestamp = "timestamp"

        static let pathMatchConfig = "/playce/match-config"
        static let pathLive = "/playce/live"
        static let pathFinished = "/match_finished"
        static let pathAck = "/match_finished_ack"

        static let kindMatchConfig = "match_config"
        static let kindLive = "live_score"
        static let kindFinished = "finished_match"
        static let kindAck = "finished_match_ack"
    }

    private weak var connectivity: ConnectivityCoordinator?
    private var selectedDevices: [IQDevice] = []
    private var appsByDeviceID: [String: IQApp] = [:]
    private var hasInitialized = false
    private var connectIQ: ConnectIQ { ConnectIQ.sharedInstance()! }

    private override init() {
        super.init()
    }

    func configure(connectivity: ConnectivityCoordinator) {
        self.connectivity = connectivity
        guard !hasInitialized else { return }
        hasInitialized = true

        connectIQ.initialize(
            withUrlScheme: Self.urlScheme,
            uiOverrideDelegate: self,
            stateRestorationIdentifier: Self.stateRestorationIdentifier
        )
        sdkState = .ready
        statusMessage = "Select Garmin device"
    }

    func requestDeviceSelection() {
        sdkState = .selectingDevices
        statusMessage = "Opening Garmin Connect"
        connectIQ.showDeviceSelection()
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        guard let parsedDevices = connectIQ.parseDeviceSelectionResponse(from: url) as? [IQDevice] else {
            sdkState = .error
            statusMessage = "Garmin device selection failed"
            return true
        }

        selectedDevices = parsedDevices
        appsByDeviceID.removeAll()
        for device in selectedDevices {
            register(device)
        }
        refreshDeviceSummaries()
        sdkState = selectedDevices.isEmpty ? .noDevices : .ready
        statusMessage = selectedDevices.isEmpty ? "No Garmin device selected" : "Garmin devices selected"
        return true
    }

    @discardableResult
    func sendMatchConfig(playerAName: String, playerBName: String, format: MatchFormat) -> WatchConfigSendResult {
        guard !appsByDeviceID.isEmpty else {
            statusMessage = selectedDevices.isEmpty ? "Select Garmin device" : "Garmin app unavailable"
            return .unavailable
        }

        let timestamp = currentMillis()
        let payload: NSDictionary = [
            "playerAName": playerAName as NSString,
            "playerBName": playerBName as NSString,
            "setsToWin": NSNumber(value: format.setsToWin),
            "tiebreakAtSixAll": NSNumber(value: format.tiebreakAtSixAll),
            "tiebreakPoints": NSNumber(value: format.tiebreakPoints),
            "superTiebreakInFinalSet": NSNumber(value: format.superTiebreakInFinalSet),
            "noAdScoring": NSNumber(value: format.noAdScoring),
            Keys.timestamp: NSNumber(value: timestamp)
        ]
        let envelope: NSDictionary = [
            Keys.path: Keys.pathMatchConfig as NSString,
            Keys.kind: Keys.kindMatchConfig as NSString,
            Keys.payload: payload,
            Keys.timestamp: NSNumber(value: timestamp)
        ]

        send(envelope, transient: false)
        statusMessage = "Garmin config sent"
        return .sent
    }

    func openStoreForSelectedDevice() {
        guard let app = appsByDeviceID.values.first else {
            requestDeviceSelection()
            return
        }
        connectIQ.showStore(for: app)
    }

    private func register(_ device: IQDevice) {
        connectIQ.register(forDeviceEvents: device, delegate: self)

        guard let appUUID = UUID(uuidString: Self.appID) else {
            sdkState = .error
            statusMessage = "Invalid Garmin app id"
            return
        }

        let app = IQApp(uuid: appUUID, store: appUUID, device: device)
        appsByDeviceID[device.uuid.uuidString] = app

        connectIQ.getAppStatus(app) { [weak self] appStatus in
            Task { @MainActor in
                guard let self else { return }
                if appStatus?.isInstalled == true {
                    self.connectIQ.register(forAppMessages: app, delegate: self)
                    self.statusMessage = "Garmin app ready"
                } else {
                    self.statusMessage = "Install PLAYCE on Garmin"
                }
                self.refreshDeviceSummaries()
            }
        }
    }

    private func send(_ message: NSDictionary, to app: IQApp? = nil, transient: Bool) {
        let targets = app.map { [$0] } ?? Array(appsByDeviceID.values)
        guard !targets.isEmpty else {
            statusMessage = "No Garmin app target"
            return
        }
        for target in targets {
            connectIQ.sendMessage(
                message,
                to: target,
                progress: { _, _ in },
                completion: { [weak self] result in
                    Task { @MainActor in
                        self?.statusMessage = result == .success ? "Garmin message sent" : "Garmin send failed"
                    }
                },
                isTransient: transient
            )
        }
    }

    private func route(_ message: Any, from app: IQApp) {
        if let envelope = message as? [String: Any] {
            routeEnvelope(envelope, from: app)
            return
        }
        if let envelopes = message as? [[String: Any]] {
            envelopes.forEach { routeEnvelope($0, from: app) }
            return
        }
        statusMessage = "Ignored unknown Garmin message"
    }

    private func routeEnvelope(_ envelope: [String: Any], from app: IQApp) {
        let path = string(envelope[Keys.path])
        guard !path.isEmpty,
              let payload = envelope[Keys.payload] as? [String: Any] else {
            statusMessage = "Invalid Garmin envelope"
            return
        }

        switch path {
        case Keys.pathLive:
            handleLive(payload)
        case Keys.pathFinished:
            handleFinished(payload, envelope: envelope, from: app)
        default:
            statusMessage = "Ignored Garmin path \(path)"
        }
    }

    private func handleLive(_ payload: [String: Any]) {
        let isActive = bool(payload["isMatchActive"])
        let timestamp = millisDate(long(payload[Keys.timestamp]))
        let live = LiveMatchPayload(
            playerAPoints: int(payload["playerA_points"]),
            playerAGames: int(payload["playerA_games"]),
            playerASets: int(payload["playerA_sets"]),
            playerBPoints: int(payload["playerB_points"]),
            playerBGames: int(payload["playerB_games"]),
            playerBSets: int(payload["playerB_sets"]),
            completedSets: string(payload["completedSets"]),
            pointLabelA: string(payload["pointLabelA"], default: "0"),
            pointLabelB: string(payload["pointLabelB"], default: "0"),
            elapsedSeconds: int(payload["elapsedSeconds"]),
            isTimerRunning: isActive,
            hasTimerStarted: int(payload["elapsedSeconds"]) > 0,
            isMatchActive: isActive,
            lastScoredPlayer: string(payload["lastScoredPlayer"]),
            timestamp: timestamp
        )
        connectivity?.receiveExternalLiveMatch(live, source: "Garmin")
        statusMessage = isActive ? "Garmin live score" : "Garmin live cleared"
    }

    private func handleFinished(_ payload: [String: Any], envelope: [String: Any], from app: IQApp) {
        let createdAt = long(payload["createdAt"], default: -1)
        let durationSeconds = int(payload["durationSeconds"], default: -1)
        let finalScoreText = string(payload["finalScoreText"])
        let idempotencyKey = string(payload["idempotencyKey"]).isEmpty
            ? string(envelope[Keys.idempotencyKey])
            : string(payload["idempotencyKey"])

        guard createdAt > 0, durationSeconds >= 0, !finalScoreText.isEmpty, !idempotencyKey.isEmpty else {
            statusMessage = "Invalid Garmin finished match"
            return
        }

        let playerAName = string(payload["playerAName"], default: "Player A")
        let playerBName = string(payload["playerBName"], default: "Player B")
        let record = FinishedMatchRecord(
            createdAt: millisDate(createdAt),
            durationSeconds: durationSeconds,
            finalScoreText: finalScoreText,
            setScoresText: optionalString(payload["setScoresText"]),
            detailText: "\(playerAName) vs \(playerBName)",
            source: "Garmin",
            idempotencyKey: idempotencyKey
        )

        let ack = connectivity?.receiveExternalFinishedMatch(record, source: "Garmin")
            ?? MatchSyncAckPayload(idempotencyKey: idempotencyKey, status: "inserted")
        sendAck(ack, to: app)
        statusMessage = "Garmin match \(ack.status)"
    }

    private func sendAck(_ ack: MatchSyncAckPayload, to app: IQApp) {
        let timestamp = currentMillis()
        let payload: NSDictionary = [
            "idempotencyKey": ack.idempotencyKey as NSString,
            "status": ack.status as NSString
        ]
        let envelope: NSDictionary = [
            Keys.path: Keys.pathAck as NSString,
            Keys.kind: Keys.kindAck as NSString,
            Keys.payload: payload,
            Keys.idempotencyKey: ack.idempotencyKey as NSString,
            Keys.timestamp: NSNumber(value: timestamp)
        ]
        send(envelope, to: app, transient: false)
    }

    private func refreshDeviceSummaries() {
        var summaries: [GarminDeviceSummary] = []
        var connected = 0
        for device in selectedDevices {
            let status = connectIQ.getDeviceStatus(device)
            if status == .connected { connected += 1 }
            summaries.append(
                GarminDeviceSummary(
                    id: device.uuid.uuidString,
                    name: device.friendlyName,
                    model: device.modelName,
                    status: label(for: status)
                )
            )
        }
        devices = summaries
        connectedDeviceCount = connected
    }

    private func label(for status: IQDeviceStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .notConnected: return "offline"
        case .notFound: return "not found"
        case .bluetoothNotReady: return "Bluetooth off"
        case .invalidDevice: return "invalid"
        @unknown default: return "unknown"
        }
    }

    private func currentMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func millisDate(_ value: Int64) -> Date {
        guard value > 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(value) / 1000)
    }

    private func string(_ value: Any?, default defaultValue: String = "") -> String {
        if let value = value as? String { return value.isEmpty ? defaultValue : value }
        if let value = value as? NSString { return value.length == 0 ? defaultValue : value as String }
        if let value { return String(describing: value) }
        return defaultValue
    }

    private func optionalString(_ value: Any?) -> String? {
        let normalized = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func int(_ value: Any?, default defaultValue: Int = 0) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? defaultValue }
        return defaultValue
    }

    private func long(_ value: Any?, default defaultValue: Int64 = 0) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? defaultValue }
        return defaultValue
    }

    private func bool(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value.lowercased() == "true" }
        return defaultValue
    }
}

extension GarminConnectivityCoordinator: IQUIOverrideDelegate {
    nonisolated func needsToInstallConnectMobile() {
        Task { @MainActor in
            self.sdkState = .connectMobileRequired
            self.statusMessage = "Install Garmin Connect"
        }
    }
}

extension GarminConnectivityCoordinator: IQDeviceEventDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor in
            self.refreshDeviceSummaries()
            self.statusMessage = "Garmin \(self.label(for: status))"
        }
    }

    nonisolated func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        Task { @MainActor in
            self.refreshDeviceSummaries()
            self.statusMessage = "Garmin ready"
        }
    }
}

extension GarminConnectivityCoordinator: IQAppMessageDelegate {
    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        Task { @MainActor in
            guard let message, let app else { return }
            self.route(message, from: app)
        }
    }
}
