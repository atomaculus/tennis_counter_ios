import SwiftUI
import WatchKit
import HealthKit

@main
struct PlayceWatchApp: App {
    @StateObject private var connectivity = ConnectivityCoordinator.shared
    @StateObject private var historyStore = MatchHistoryStore()
    @StateObject private var premiumStore = PremiumStore()
    @StateObject private var controller = ScoreboardController()
    @StateObject private var workoutManager = WorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: controller)
                .environmentObject(connectivity)
                .environmentObject(historyStore)
                .environmentObject(premiumStore)
                .environmentObject(workoutManager)
                .task {
                    connectivity.configure(historyStore: historyStore, premiumStore: premiumStore)
                    connectivity.activate()
                    await workoutManager.prepareAuthorization()
                    workoutManager.startMatchWorkoutIfPossible()
                }
        }
    }
}

struct WatchRootView: View {
    @ObservedObject var controller: ScoreboardController
    @EnvironmentObject private var connectivity: ConnectivityCoordinator
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var historyStore: MatchHistoryStore

    @State private var finishedRecord: FinishedMatchRecord?
    @State private var transientMessage: String?
    @State private var savedFinishedRecord = false

    /// True once the iPhone has pushed a match config that already fixed who
    /// serves first, so the on-watch prompt should not ask again.
    @State private var serveFixedByPhone = false
    /// True once the user answered the on-watch "who serves first" prompt, or
    /// started scoring before answering (the prompt is ignorable).
    @State private var serveQuestionAnswered = false
    @State private var decidingTiebreakDeclined = false
    /// D9: match actions (Finish / Reset Game / New Match) live in one menu,
    /// mirroring the Wear OS and Garmin admin sheets.
    @State private var showActionsMenu = false

    /// True on first appearance after an update that changed on-watch
    /// behavior (see `WhatsNewPrefs`); dismissing marks it seen so it is not
    /// shown again until the next content bump. Independent from the iOS
    /// app's own flag (separate `UserDefaults.standard` per device).
    @State private var showWhatsNew = WhatsNewPrefs.shouldShow()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let finishedRecord {
                    finishedState(finishedRecord)
                } else {
                    liveCounter
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: connectivity.receivedMatchConfig) { _, config in
            guard let config else { return }
            controller.setPlayerNames(config.playerAName, config.playerBName)
            controller.setMatchFormat(config.format)
            controller.setInitialServer(isPlayerA: config.initialServerIsPlayerA)
            serveFixedByPhone = true
            serveQuestionAnswered = true
            connectivity.consumeMatchConfig()
            transientMessage = "Config applied"
            WKInterfaceDevice.current().play(.click)
        }
        .onChange(of: controller.state.elapsedSeconds) { _, _ in
            guard controller.state.isTimerRunning, finishedRecord == nil else { return }
            connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
        }
        .onChange(of: controller.state.setDetailLine) { _, _ in
            decidingTiebreakDeclined = false
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewWatchView {
                WhatsNewPrefs.markSeen()
                showWhatsNew = false
            }
        }
        // D9 action menu: Cancel is added automatically by watchOS.
        .confirmationDialog("Match actions", isPresented: $showActionsMenu, titleVisibility: .visible) {
            Button("Finish Match") {
                Task { await finishMatch() }
            }
            Button("Reset Game") {
                controller.resetGame()
                connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
            }
            Button("New Match", role: .destructive) {
                controller.resetMatch()
                finishedRecord = nil
                savedFinishedRecord = false
                serveFixedByPhone = false
                serveQuestionAnswered = false
                decidingTiebreakDeclined = false
                connectivity.clearLiveMatch()
                workoutManager.startMatchWorkoutIfPossible()
            }
        }
    }

    private var liveCounter: some View {
        VStack(spacing: 10) {
            statusLabel(connectivity.syncStatus)
            if showServeFirstPrompt {
                serveFirstCard
            }
            if controller.canOfferDecidingTiebreak && !decidingTiebreakDeclined {
                decidingTiebreakCard
            }
            watchCard(accented: true) {
                VStack(spacing: 8) {
                    Text("LIVE MATCH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    HStack(spacing: 6) {
                        playerNameChip(controller.playerAName, accented: true)
                        playerNameChip(controller.playerBName, accented: false)
                    }
                    HStack(spacing: 8) {
                        compactStat("SETS", "\(controller.state.playerA.sets)-\(controller.state.playerB.sets)")
                        compactStat("GAMES", "\(controller.state.playerA.games)-\(controller.state.playerB.games)")
                    }
                    Text(PlayceFormatting.elapsed(controller.state.elapsedSeconds))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(controller.state.pointLabel(for: .a)) - \(controller.state.pointLabel(for: .b))")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    serveStatus
                }
            }

            HStack(spacing: 8) {
                PointButton(
                    label: "+A",
                    accessibilityName: controller.playerAName,
                    onTap: { score(.a) },
                    onLongPress: { undo(.a) }
                )
                PointButton(
                    label: "+B",
                    accessibilityName: controller.playerBName,
                    onTap: { score(.b) },
                    onLongPress: { undo(.b) }
                )
            }

            HStack(spacing: 8) {
                smallButton("Timer") {
                    controller.toggleTimer()
                    connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
                }
                smallButton("Actions") {
                    showActionsMenu = true
                }
            }

            if let transientMessage {
                Text(transientMessage)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
    }

    private func finishedState(_ record: FinishedMatchRecord) -> some View {
        VStack(spacing: 10) {
            statusLabel(connectivity.syncStatus)
            watchCard(accented: true) {
                VStack(spacing: 8) {
                    Text("MATCH FINISHED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    Text(record.finalScoreText)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(record.detailText)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                    Text(PlayceFormatting.elapsed(record.durationSeconds))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            smallButton(LocalizedStringKey(savedFinishedRecord ? "Saved" : "Save Match"), accent: !savedFinishedRecord) {
                guard !savedFinishedRecord else { return }
                historyStore.upsert(record)
                connectivity.queueFinishedMatch(record)
                savedFinishedRecord = true
                transientMessage = "Saved and queued"
                WKInterfaceDevice.current().play(.click)
            }

            smallButton("Start New", danger: true) {
                finishedRecord = nil
                transientMessage = nil
                savedFinishedRecord = false
                controller.resetMatch()
                serveFixedByPhone = false
                serveQuestionAnswered = false
                decidingTiebreakDeclined = false
                connectivity.clearLiveMatch()
                workoutManager.startMatchWorkoutIfPossible()
            }
        }
    }

    /// The match is untouched: no points, games, sets or completed sets yet.
    private var isVirginMatch: Bool {
        controller.state.playerA == PlayerScore() &&
            controller.state.playerB == PlayerScore() &&
            controller.state.completedSets.isEmpty
    }

    private var showServeFirstPrompt: Bool {
        !serveFixedByPhone && !serveQuestionAnswered && isVirginMatch
    }

    /// Ignorable prompt: scoring a point (see `score(_:)`) dismisses it with
    /// the default server (Player A) already in effect, so it never blocks play.
    private var serveFirstCard: some View {
        watchCard(accented: true) {
            VStack(spacing: 8) {
                Text("Who serves first?")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    smallButton(controller.playerAName, accent: true) {
                        controller.setInitialServer(isPlayerA: true)
                        serveQuestionAnswered = true
                        WKInterfaceDevice.current().play(.click)
                    }
                    smallButton(controller.playerBName) {
                        controller.setInitialServer(isPlayerA: false)
                        serveQuestionAnswered = true
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
        }
    }

    private var decidingTiebreakCard: some View {
        watchCard(accented: true) {
            VStack(spacing: 8) {
                Text("Sets tied")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    .textCase(.uppercase)
                Text("Decide the match by tiebreak?")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                smallButton("Tiebreak to 7", accent: true) {
                    controller.startDecidingTiebreak(targetPoints: 7)
                }
                smallButton("Super tiebreak to 10", accent: true) {
                    controller.startDecidingTiebreak(targetPoints: 10)
                }
                smallButton("Continue normal set") {
                    decidingTiebreakDeclined = true
                }
            }
        }
    }

    private func score(_ side: PlayerSide) {
        serveQuestionAnswered = true
        controller.addPoint(to: side)
        connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: side)
        WKInterfaceDevice.current().play(side == .a ? .click : .directionUp)
        if controller.finishedSummary != nil {
            Task { await finishMatch() }
        }
    }

    /// Long-press on a player's point button: undo their last point. Uses a
    /// distinct `.retry` haptic so it's clearly different from scoring.
    private func undo(_ side: PlayerSide) {
        guard controller.undoLastPoint(for: side) else { return }
        connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
        WKInterfaceDevice.current().play(.retry)
    }

    @MainActor
    private func finishMatch() async {
        if controller.finishedSummary == nil {
            controller.finishMatch()
        }
        let metrics = await workoutManager.endWorkout()
        finishedRecord = controller.finishMatchRecord(
            source: "watchOS",
            caloriesKcal: metrics.caloriesKcal,
            avgHeartRateBpm: metrics.avgHeartRateBpm,
            maxHeartRateBpm: metrics.maxHeartRateBpm
        )
        savedFinishedRecord = false
        connectivity.clearLiveMatch()
        WKInterfaceDevice.current().play(.success)
    }

    private var serveStatus: some View {
        HStack(spacing: 6) {
            compactPill(
                LocalizedStringKey(controller.state.isTiebreak ? "TB" : "SRV"),
                controller.state.currentServerIsPlayerA ? controller.playerAName : controller.playerBName,
                accented: controller.state.isTiebreak
            )
            compactPill(
                "SIDE",
                String(localized: controller.state.serveStartsOnLeftSide ? "Left" : "Right"),
                accented: false
            )
        }
    }

    private func statusLabel(_ text: String) -> some View {
        Text(userFacingStatus(text))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.17, green: 0.17, blue: 0.17), lineWidth: 1))
    }

    private func userFacingStatus(_ text: String) -> String {
        let status = text.lowercased()
        if status.contains("broadcast") || status.contains("watching live") {
            return String(localized: "BROADCASTING")
        }
        if status.contains("config") {
            return String(localized: "CONFIG READY")
        }
        if status.contains("saved") || status.contains("stored") || status.contains("inserted") || status.contains("duplicate") || status.contains("match sync") {
            return String(localized: "MATCH SAVED")
        }
        if status.contains("queued") || status.contains("sending") || status.contains("retry") {
            return String(localized: "SYNCING")
        }
        return String(localized: "WATCH READY")
    }

    private func compactStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        compactStatLabel(Text(title), value: value)
    }

    @_disfavoredOverload
    private func compactStat<S: StringProtocol>(_ title: S, _ value: String) -> some View {
        compactStatLabel(Text(verbatim: String(title)), value: value)
    }

    private func compactStatLabel(_ title: Text, value: String) -> some View {
        VStack(spacing: 2) {
            title
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func compactPill(_ title: LocalizedStringKey, _ value: String, accented: Bool) -> some View {
        compactPillLabel(Text(title), value: value, accented: accented)
    }

    @_disfavoredOverload
    private func compactPill<S: StringProtocol>(_ title: S, _ value: String, accented: Bool) -> some View {
        compactPillLabel(Text(verbatim: String(title)), value: value, accented: accented)
    }

    private func compactPillLabel(_ title: Text, value: String, accented: Bool) -> some View {
        VStack(spacing: 1) {
            title
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(accented ? Color(red: 0.72, green: 1.0, blue: 0.17) : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func playerNameChip(_ name: String, accented: Bool) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .foregroundStyle(accented ? Color(red: 0.72, green: 1.0, blue: 0.17) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: Capsule())
    }

    private func smallButton(_ title: LocalizedStringKey, accent: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        smallButtonLabel(Text(title), accent: accent, danger: danger, action: action)
    }

    @_disfavoredOverload
    private func smallButton<S: StringProtocol>(_ title: S, accent: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        smallButtonLabel(Text(verbatim: String(title)), accent: accent, danger: danger, action: action)
    }

    private func smallButtonLabel(_ title: Text, accent: Bool, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(accent ? .black : (danger ? Color.red : .white))
                .background(
                    accent
                        ? Color(red: 0.72, green: 1.0, blue: 0.17)
                        : (danger ? Color.red.opacity(0.18) : Color(red: 0.10, green: 0.10, blue: 0.10)),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            accent ? Color(red: 0.72, green: 1.0, blue: 0.17).opacity(0.35) : Color(red: 0.17, green: 0.17, blue: 0.17),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func watchCard<Content: View>(accented: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack { content() }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color(red: 0.06, green: 0.06, blue: 0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(accented ? Color(red: 0.72, green: 1.0, blue: 0.17).opacity(0.25) : Color(red: 0.17, green: 0.17, blue: 0.17), lineWidth: 1)
            )
    }
}

/// Big round point button: tap scores a point, long-press undoes the last
/// point for that player (mirrors the Wear OS sibling app's gesture pattern).
///
/// Uses a `simultaneousGesture(LongPressGesture)` alongside the `Button`'s own
/// tap action rather than two exclusive gestures, then guards the tap with
/// `isLongPressing` so a completed long-press never also fires the tap: the
/// long-press's `onEnded` always runs first (while the finger/crown-press is
/// still down, as soon as `minimumDuration` elapses), so by the time the
/// touch is released and the Button's action would fire, the flag is already
/// set and the tap is skipped.
private struct PointButton: View {
    let label: String
    let accessibilityName: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isLongPressing = false

    var body: some View {
        Button(action: handleTap) {
            Text(label)
                .font(.headline.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 58, height: 58)
                .background(Color(red: 0.72, green: 1.0, blue: 0.17), in: Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    isLongPressing = true
                    onLongPress()
                }
        )
        .accessibilityLabel(Text("Point for \(accessibilityName)"))
        .accessibilityHint(Text("Double tap and hold to undo the last point"))
    }

    private func handleTap() {
        if isLongPressing {
            // Long-press already handled this press; swallow the trailing tap.
            isLongPressing = false
            return
        }
        onTap()
    }
}

/// Single-screen "what's new" overlay shown once on the Watch after an update
/// that changed the on-watch gestures (see `WhatsNewPrefs`).
private struct WhatsNewWatchView: View {
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("What's new")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    .textCase(.uppercase)
                Text("New watch controls")
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("Tap = point. Hold = undo.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                Button(action: onDismiss) {
                    Text("OK")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(.black)
                        .background(Color(red: 0.72, green: 1.0, blue: 0.17), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func prepareAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        var shareTypes: Set<HKSampleType> = [workoutType]
        var readTypes: Set<HKObjectType> = [workoutType]

        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            shareTypes.insert(activeEnergy)
            readTypes.insert(activeEnergy)
        }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }

        try? await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func startMatchWorkoutIfPossible() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            self.session = session
            self.builder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    /// Ends the active workout session and returns the calories/heart-rate
    /// metrics collected during it. Returns an empty snapshot when no workout
    /// was running or HealthKit data is unavailable, so callers can always
    /// pass the result straight into `finishMatchRecord`.
    func endWorkout() async -> WorkoutHealthMetrics {
        guard let builder, let session else { return WorkoutHealthMetrics() }

        await withCheckedContinuation { continuation in
            builder.endCollection(withEnd: Date()) { _, _ in
                continuation.resume()
            }
        }

        let metrics = WorkoutHealthMetrics(
            caloriesKcal: statisticValue(from: builder, identifier: .activeEnergyBurned, unit: .kilocalorie()) { $0.sumQuantity() },
            avgHeartRateBpm: statisticValue(from: builder, identifier: .heartRate, unit: Self.heartRateUnit) { $0.averageQuantity() },
            maxHeartRateBpm: statisticValue(from: builder, identifier: .heartRate, unit: Self.heartRateUnit) { $0.maximumQuantity() }
        )

        await withCheckedContinuation { continuation in
            builder.finishWorkout { _, _ in
                continuation.resume()
            }
        }

        session.end()
        self.session = nil
        self.builder = nil
        return metrics
    }

    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

    private func statisticValue(
        from builder: HKLiveWorkoutBuilder,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        quantity: (HKStatistics) -> HKQuantity?
    ) -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier),
              let statistics = builder.statistics(for: type) else {
            return nil
        }
        return quantity(statistics)?.doubleValue(for: unit)
    }
}

/// Calories/heart-rate summary collected from the HealthKit workout, if any.
struct WorkoutHealthMetrics {
    var caloriesKcal: Double?
    var avgHeartRateBpm: Double?
    var maxHeartRateBpm: Double?
}
