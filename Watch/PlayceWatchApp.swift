import SwiftUI
import WatchKit
import HealthKit

@main
struct PlayceWatchApp: App {
    @StateObject private var connectivity = ConnectivityCoordinator.shared
    @StateObject private var historyStore = MatchHistoryStore()
    @StateObject private var trainingHistoryStore = TrainingHistoryStore()
    @StateObject private var premiumStore = PremiumStore()
    @StateObject private var controller = ScoreboardController()
    @StateObject private var workoutManager = WorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: controller)
                .environmentObject(connectivity)
                .environmentObject(historyStore)
                .environmentObject(trainingHistoryStore)
                .environmentObject(premiumStore)
                .environmentObject(workoutManager)
                .task {
                    connectivity.configure(historyStore: historyStore, premiumStore: premiumStore)
                    connectivity.activate()
                    await workoutManager.prepareAuthorization()
                    workoutManager.startMatchWorkoutIfPossible()
                    WKExtension.shared().isFrontmostTimeoutExtended = true
                }
        }
    }
}

struct WatchRootView: View {
    @ObservedObject var controller: ScoreboardController
    @EnvironmentObject private var connectivity: ConnectivityCoordinator
    @EnvironmentObject private var workoutManager: WorkoutSessionManager
    @EnvironmentObject private var historyStore: MatchHistoryStore
    /// True when the wrist is down / the display is in Always-On low-power
    /// mode. Drives the simplified, button-less scoreboard in `liveCounter`.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// nil = show `ModeSelectView`. Cold start resolves this once (see
    /// `resolveInitialModeIfNeeded()`): straight to the scoreboard when a
    /// match is already under way (restored from disk or still in memory),
    /// otherwise the picker.
    @State private var mode: PlayMode?
    @State private var hasResolvedInitialMode = false

    @State private var finishedRecord: FinishedMatchRecord?
    @State private var transientMessage: String?
    @State private var savedFinishedRecord = false
    /// Player whose last point is pending undo confirmation; non-nil drives
    /// the undo `.confirmationDialog` below.
    @State private var pendingUndoSide: PlayerSide? = nil

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
        Group {
            switch mode {
            case .match:
                matchScoreboardView
            case .veintiuno:
                VeintiunoWatchView(onExit: { mode = nil })
            case .wall:
                #if DEBUG
                ParedonStubWatchView(onBack: { mode = nil })
                #else
                ModeSelectView(lastMode: PlayModePrefs.lastMode(), onSelect: selectMode)
                #endif
            case nil:
                ModeSelectView(lastMode: PlayModePrefs.lastMode(), onSelect: selectMode)
            }
        }
        .task {
            resolveInitialModeIfNeeded()
        }
        .onChange(of: connectivity.receivedMatchConfig) { _, config in
            guard let config else { return }
            controller.setPlayerNames(config.playerAName, config.playerBName)
            controller.setMatchFormat(config.format)
            controller.setInitialServer(isPlayerA: config.initialServerIsPlayerA)
            serveFixedByPhone = true
            serveQuestionAnswered = true
            connectivity.consumeMatchConfig()
            transientMessage = "Config applied"
            mode = .match
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
        // Long-press on a point button stages an undo here instead of firing
        // it immediately; Cancel is added automatically by watchOS.
        .confirmationDialog(
            "Undo last point?",
            isPresented: Binding(
                get: { pendingUndoSide != nil },
                set: { isPresented in
                    if !isPresented { pendingUndoSide = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingUndoSide {
                let name = pendingUndoSide == .a ? controller.playerAName : controller.playerBName
                Button(
                    String(format: NSLocalizedString("Undo (%@)", comment: "Confirmation button to undo the last point, with the player's name"), name),
                    role: .destructive
                ) {
                    undo(pendingUndoSide)
                    self.pendingUndoSide = nil
                }
            }
        }
    }

    /// Resolves the cold-start screen exactly once per launch: straight to
    /// the scoreboard if a match is already under way (either restored from
    /// `ActiveMatchSessionStore` or still live in memory, e.g. after a scene
    /// reconnect), otherwise leaves `mode` nil so `ModeSelectView` shows.
    private func resolveInitialModeIfNeeded() {
        guard !hasResolvedInitialMode else { return }
        hasResolvedInitialMode = true
        let restored = controller.restoreIfAvailable()
        if restored || controller.hasActiveMatchInMemory {
            mode = .match
            // The serve choice (if any) was already made before this launch —
            // don't re-ask "who serves first?" on top of a resumed match.
            serveFixedByPhone = true
            serveQuestionAnswered = true
        }
    }

    private func selectMode(_ selected: PlayMode) {
        guard PlayMode.isWallStubAvailable || selected != .wall else { return }
        PlayModePrefs.setLastMode(selected)
        mode = selected
    }

    /// The existing scoreboard screen (live counter / finished-match result),
    /// unchanged from before the mode selector was introduced — just moved
    /// out of `body` so it can sit behind the `PlayMode.match` case.
    private var matchScoreboardView: some View {
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
                    if isLuminanceReduced {
                        Text(PlayceFormatting.elapsedNoSeconds(controller.state.elapsedSeconds))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        Text(PlayceFormatting.elapsed(controller.state.elapsedSeconds))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Text("\(controller.state.pointLabel(for: .a)) - \(controller.state.pointLabel(for: .b))")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    serveStatus
                }
            }

            // Always-on Display: no interactive controls (can't be tapped
            // without waking the screen) and no neon-bright buttons.
            if !isLuminanceReduced {
                HStack(spacing: 8) {
                    PointButton(
                        label: "+A",
                        accessibilityName: controller.playerAName,
                        onTap: { score(.a) },
                        onLongPress: { pendingUndoSide = .a }
                    )
                    PointButton(
                        label: "+B",
                        accessibilityName: controller.playerBName,
                        onTap: { score(.b) },
                        onLongPress: { pendingUndoSide = .b }
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

/// Minimal shared building blocks for the mode-selector and practice-mode
/// screens (`ModeSelectView`, `VeintiunoWatchView`, `ParedonStubWatchView`).
/// Deliberately kept separate from `WatchRootView`'s own `compactStat`/
/// `smallButton` (which are `private` to that type, so not reachable from
/// these sibling views) rather than widening their access, to avoid touching
/// the existing scoreboard screen's code at all.
private func sharedCompactStat(_ title: LocalizedStringKey, _ value: String) -> some View {
    VStack(spacing: 2) {
        Text(title)
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

private func sharedSmallButton(_ title: LocalizedStringKey, danger: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(danger ? Color.red : .white)
            .background(
                danger ? Color.red.opacity(0.18) : Color(red: 0.10, green: 0.10, blue: 0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(danger ? Color.red.opacity(0.35) : Color(red: 0.17, green: 0.17, blue: 0.17), lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
}

/// Cold-start / "back" screen: score a match, or count to 21. Paredón is
/// listed only when `PlayMode.isWallStubAvailable` (Debug). Match is always
/// the visually primary option (large, accented); whichever mode was last
/// picked (see `PlayModePrefs`) gets a subtle highlight so a returning
/// player lands back where they left off with one fewer tap. No `ScrollView`:
/// long-press elsewhere in this app means undo, so scroll gestures would
/// conflict (see `WatchRootView`'s `liveCounter`) — same constraint here.
private struct ModeSelectView: View {
    let lastMode: PlayMode
    let onSelect: (PlayMode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("PLAYCE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                .textCase(.uppercase)

            modeButton(.match, title: "Match", isPrimary: true)

            HStack(spacing: 8) {
                if PlayMode.isWallStubAvailable {
                    modeButton(.wall, title: "Wall", isPrimary: false)
                }
                modeButton(.veintiuno, title: LocalizedStringKey("21"), isPrimary: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func modeButton(_ target: PlayMode, title: LocalizedStringKey, isPrimary: Bool) -> some View {
        let isLastUsed = target == lastMode
        return Button(action: { onSelect(target) }) {
            Text(title)
                .font(.system(size: isPrimary ? 20 : 15, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: isPrimary ? 58 : 46)
                .foregroundStyle(isPrimary ? Color.black : Color.white)
                .background(
                    isPrimary ? Color(red: 0.72, green: 1.0, blue: 0.17) : Color(red: 0.10, green: 0.10, blue: 0.10),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isLastUsed && !isPrimary
                                ? Color(red: 0.72, green: 1.0, blue: 0.17).opacity(0.7)
                                : Color(red: 0.17, green: 0.17, blue: 0.17),
                            lineWidth: isLastUsed && !isPrimary ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

/// Free-standing "21" counter: tap +1 to build a streak, MISS drops the
/// count back to zero and logs a failed attempt. Reaching 21 accents the
/// number, plays a success haptic, saves the session and returns to the
/// mode selector automatically. No `ScrollView`, same reasoning as
/// `ModeSelectView`.
private struct VeintiunoWatchView: View {
    let onExit: () -> Void

    @EnvironmentObject private var trainingHistoryStore: TrainingHistoryStore

    @State private var count = 0
    @State private var bestStreak = 0
    @State private var attempts = 0
    @State private var startedAt = Date()
    /// Guards against double-saving/double-exiting once 21 is reached and
    /// `onExit()` has already been called (SwiftUI may still deliver a queued
    /// tap before the parent swaps this view out).
    @State private var didFinish = false

    private static let target = 21

    var body: some View {
        VStack(spacing: 10) {
            Text(LocalizedStringKey("21"))
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                .textCase(.uppercase)

            HStack(spacing: 8) {
                sharedCompactStat("STREAK", "\(bestStreak)")
                sharedCompactStat("ATTEMPTS", "\(attempts)")
            }

            Text("\(count)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(count >= Self.target ? Color(red: 0.72, green: 1.0, blue: 0.17) : .white)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button(action: addPoint) {
                    Text("+1")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 58, height: 58)
                        .background(Color(red: 0.72, green: 1.0, blue: 0.17), in: Circle())
                }
                .buttonStyle(.plain)

                sharedSmallButton("MISS", danger: true, action: miss)
            }

            sharedSmallButton("Exit", action: exit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func addPoint() {
        guard !didFinish else { return }
        count += 1
        bestStreak = max(bestStreak, count)
        if count >= Self.target {
            didFinish = true
            WKInterfaceDevice.current().play(.success)
            saveSession()
            onExit()
        }
    }

    private func miss() {
        guard !didFinish else { return }
        attempts += 1
        count = 0
        WKInterfaceDevice.current().play(.retry)
    }

    private func exit() {
        guard !didFinish else { return }
        didFinish = true
        if count > 0 || attempts > 0 || bestStreak > 0 {
            saveSession()
        }
        onExit()
    }

    private func saveSession() {
        trainingHistoryStore.append(
            TrainingSession(
                modality: TrainingSession.Modality.veintiuno,
                createdAt: startedAt,
                durationSeconds: max(0, Int(Date().timeIntervalSince(startedAt))),
                targetPoints: Self.target,
                finalCount: count,
                bestStreak: bestStreak,
                attempts: attempts
            )
        )
    }
}

#if DEBUG
/// Placeholder for the paredón (wall-practice) mode: swing/hit-count
/// detection isn't implemented yet, so this just explains what's coming and
/// lets the user return to the picker. Debug-only; Release does not compile
/// this screen (see `PlayMode.isWallStubAvailable`).
private struct ParedonStubWatchView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Wall")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                .textCase(.uppercase)
            Text("Wall mode is coming soon — the watch will count your hits.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            sharedSmallButton("Back", action: onBack)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
#endif

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
                Text("Match stays visible")
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("See your score with your wrist down. Hold now asks to confirm before undo.")
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
