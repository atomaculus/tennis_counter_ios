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

    @State private var finishedRecord: FinishedMatchRecord?
    @State private var transientMessage: String?

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
    }

    private var liveCounter: some View {
        VStack(spacing: 10) {
            statusLabel(connectivity.syncStatus)
            watchCard(accented: true) {
                VStack(spacing: 8) {
                    Text("LIVE MATCH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.72, green: 1.0, blue: 0.17))
                    Text("\(controller.state.pointLabel(for: .a)) - \(controller.state.pointLabel(for: .b))")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        compactStat("SETS", "\(controller.state.playerA.sets)-\(controller.state.playerB.sets)")
                        compactStat("GAMES", "\(controller.state.playerA.games)-\(controller.state.playerB.games)")
                    }
                    Text(PlayceFormatting.elapsed(controller.state.elapsedSeconds))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 8) {
                roundAction("+A") { score(.a) }
                roundAction("+B") { score(.b) }
            }

            HStack(spacing: 8) {
                smallButton("Undo A") { _ = controller.undoLastPoint(for: .a) }
                smallButton("Undo B") { _ = controller.undoLastPoint(for: .b) }
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
                finishedRecord = controller.finishMatchRecord(source: "watchOS")
                connectivity.clearLiveMatch()
                workoutManager.endWorkout()
                WKInterfaceDevice.current().play(.success)
            }

            smallButton("New Match", danger: true) {
                controller.resetMatch()
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

            smallButton("Save Match", accent: true) {
                connectivity.queueFinishedMatch(record)
                transientMessage = "Queued for iPhone"
                WKInterfaceDevice.current().play(.click)
            }

            smallButton("Start New", danger: true) {
                finishedRecord = nil
                transientMessage = nil
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
    }

    private func statusLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color(red: 0.10, green: 0.10, blue: 0.10), in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.17, green: 0.17, blue: 0.17), lineWidth: 1))
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
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        session?.end()
        session = nil
        builder = nil
    }
}
