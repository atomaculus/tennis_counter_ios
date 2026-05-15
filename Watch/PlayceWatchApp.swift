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
            connectivity.consumeMatchConfig()
            transientMessage = "Config applied"
            WKInterfaceDevice.current().play(.click)
        }
        .onChange(of: controller.state.elapsedSeconds) { _, _ in
            guard controller.state.isTimerRunning, finishedRecord == nil else { return }
            connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
        }
    }

    private var liveCounter: some View {
        VStack(spacing: 10) {
            statusLabel(connectivity.syncStatus)
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
                roundAction("+A") { score(.a) }
                roundAction("+B") { score(.b) }
            }

            HStack(spacing: 8) {
                smallButton("Undo A") {
                    if controller.undoLastPoint(for: .a) {
                        connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
                    }
                }
                smallButton("Undo B") {
                    if controller.undoLastPoint(for: .b) {
                        connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
                    }
                }
            }

            HStack(spacing: 8) {
                smallButton("Reset Game") {
                    controller.resetGame()
                    connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
                }
                smallButton("Timer") {
                    controller.toggleTimer()
                    connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: nil)
                }
            }

            smallButton("Finish Match", accent: true) {
                finishMatch()
            }

            smallButton("New Match", danger: true) {
                controller.resetMatch()
                finishedRecord = nil
                savedFinishedRecord = false
                connectivity.clearLiveMatch()
                workoutManager.startMatchWorkoutIfPossible()
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

            smallButton(savedFinishedRecord ? "Saved" : "Save Match", accent: !savedFinishedRecord) {
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
                connectivity.clearLiveMatch()
                workoutManager.startMatchWorkoutIfPossible()
            }
        }
    }

    private func score(_ side: PlayerSide) {
        controller.addPoint(to: side)
        connectivity.broadcastLive(snapshot: controller.state, lastScoredPlayer: side)
        WKInterfaceDevice.current().play(side == .a ? .click : .directionUp)
        if controller.finishedSummary != nil {
            finishMatch()
        }
    }

    private func finishMatch() {
        if controller.finishedSummary == nil {
            controller.finishMatch()
        }
        finishedRecord = controller.finishMatchRecord(source: "watchOS")
        savedFinishedRecord = false
        connectivity.clearLiveMatch()
        workoutManager.endWorkout()
        WKInterfaceDevice.current().play(.success)
    }

    private var serveStatus: some View {
        HStack(spacing: 6) {
            compactPill(
                controller.state.isTiebreak ? "TB" : "SRV",
                controller.state.currentServerIsPlayerA ? controller.playerAName : controller.playerBName,
                accented: controller.state.isTiebreak
            )
            compactPill(
                "SIDE",
                controller.state.serveStartsOnLeftSide ? "Left" : "Right",
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
            return "TRANSMITIENDO"
        }
        if status.contains("config") {
            return "CONFIGURACION LISTA"
        }
        if status.contains("saved") || status.contains("stored") || status.contains("inserted") || status.contains("duplicate") || status.contains("match sync") {
            return "PARTIDO GUARDADO"
        }
        if status.contains("queued") || status.contains("sending") || status.contains("retry") {
            return "SINCRONIZANDO"
        }
        return "RELOJ LISTO"
    }

    private func compactStat(_ title: String, _ value: String) -> some View {
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

    private func compactPill(_ title: String, _ value: String, accented: Bool) -> some View {
        VStack(spacing: 1) {
            Text(title)
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

    private func roundAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline.weight(.black))
                .foregroundStyle(.black)
                .frame(width: 58, height: 58)
                .background(Color(red: 0.72, green: 1.0, blue: 0.17), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func smallButton(_ title: String, accent: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func prepareAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        try? await healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType])
    }

    func startMatchWorkoutIfPossible() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tennis
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.session = session
            self.builder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    func endWorkout() {
        let builder = builder
        builder?.endCollection(withEnd: Date()) { _, _ in
            builder?.finishWorkout { _, _ in }
        }
        session?.end()
        session = nil
        self.builder = nil
    }
}
