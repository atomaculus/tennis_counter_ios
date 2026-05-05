import SwiftUI
import PhotosUI
import UIKit

@main
struct PlayceIOSApp: App {
    @StateObject private var historyStore = MatchHistoryStore()
    @StateObject private var premiumStore = PremiumStore()
    @StateObject private var connectivity = ConnectivityCoordinator.shared

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(historyStore)
                .environmentObject(premiumStore)
                .environmentObject(connectivity)
                .task {
                    await premiumStore.start()
                    connectivity.configure(historyStore: historyStore, premiumStore: premiumStore)
                    connectivity.activate()
                }
        }
    }
}

struct PhoneRootView: View {
    @StateObject private var localCounter = ScoreboardController()

    var body: some View {
        TabView {
            NavigationStack {
                CounterTabView(controller: localCounter)
            }
            .tabItem {
                Label("Counter", systemImage: "plus.forwardslash.minus")
            }

            NavigationStack {
                HistoryTabView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }

            NavigationStack {
                StatsTabView()
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.xaxis")
            }
        }
        .tint(PlaycePalette.accent)
        .preferredColorScheme(.dark)
    }
}

enum PlaycePalette {
    static let background = Color.black
    static let surface = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surfaceElevated = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let textSecondary = Color(red: 0.71, green: 0.71, blue: 0.71)
    static let accent = Color(red: 0.72, green: 1.00, blue: 0.17)
    static let accentMuted = Color(red: 0.72, green: 1.00, blue: 0.17).opacity(0.15)
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.42)
}

struct CounterTabView: View {
    @ObservedObject var controller: ScoreboardController
    @EnvironmentObject private var connectivity: ConnectivityCoordinator
    @EnvironmentObject private var historyStore: MatchHistoryStore

    var body: some View {
        Group {
            if let live = connectivity.liveMatch, live.isMatchActive {
                LiveScoreView(payload: live)
                    .navigationTitle("Live")
            } else if let summary = controller.finishedSummary {
                MobileMatchFinishedContent(
                    summary: summary,
                    onSave: {
                        historyStore.upsert(controller.finishMatchRecord(source: "iPhone"))
                    },
                    onNewMatch: controller.resetMatch
                )
                .navigationTitle("Result")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        PremiumHeaderCard()
                        SyncStatusCard(
                            status: connectivity.syncStatus,
                            hasPendingMatch: connectivity.pendingFinishedMatch != nil
                        )
                        MatchSetupCard(
                            onApplyConfig: { nameA, nameB, preset in
                                controller.setPlayerNames(nameA, nameB)
                                controller.setMatchFormat(preset.format)
                            },
                            onSendToWatch: { nameA, nameB, preset in
                                controller.setPlayerNames(nameA, nameB)
                                controller.setMatchFormat(preset.format)
                                connectivity.sendMatchConfig(
                                    playerAName: controller.playerAName,
                                    playerBName: controller.playerBName,
                                    format: preset.format
                                )
                            }
                        )
                        TimerCard(
                            elapsed: controller.state.elapsedSeconds,
                            isRunning: controller.state.isTimerRunning,
                            hasStarted: controller.state.hasTimerStarted,
                            onToggle: controller.toggleTimer
                        )
                        ScoreboardCard(
                            snapshot: controller.state,
                            playerAName: controller.playerAName,
                            playerBName: controller.playerBName,
                            onAddA: { controller.addPoint(to: .a) },
                            onAddB: { controller.addPoint(to: .b) },
                            onUndoA: { _ = controller.undoLastPoint(for: .a) },
                            onUndoB: { _ = controller.undoLastPoint(for: .b) }
                        )
                        HStack(spacing: 12) {
                            PlayceButton("Reset Game", style: .outline, action: controller.resetGame)
                            PlayceButton("New Match", style: .danger, action: controller.resetMatch)
                        }
                        if controller.state.hasTimerStarted {
                            PlayceButton("End Match", style: .solid, action: controller.finishMatch)
                        }
                    }
                    .padding(16)
                }
                .background(PlaycePalette.background.ignoresSafeArea())
                .navigationTitle("Counter")
            }
        }
        .background(PlaycePalette.background.ignoresSafeArea())
    }
}

struct SyncStatusCard: View {
    let status: String
    let hasPendingMatch: Bool

    var body: some View {
        PlayceCard {
            HStack(spacing: 12) {
                Image(systemName: hasPendingMatch ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasPendingMatch ? PlaycePalette.accent : PlaycePalette.textSecondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SYNC")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textSecondary)
                    Text(LocalizedStringKey(status))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(PlaycePalette.textPrimary)
                }

                Spacer(minLength: 8)
            }
        }
    }
}

struct PremiumHeaderCard: View {
    @EnvironmentObject private var premiumStore: PremiumStore

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 12) {
                WordmarkView()
                Text(premiumStore.isPremiumUnlocked ? "Counter + premium tools unlocked" : "Free live counter on iPhone")
                    .foregroundStyle(PlaycePalette.textSecondary)
                if !premiumStore.isPremiumUnlocked {
                    PlayceButton("Premium", style: .solid) {
                        premiumStore.unlockPremium()
                    }
                    .disabled(premiumStore.isPurchaseInProgress)
                }
                PremiumStatusMessageView()
            }
        }
    }
}

struct PremiumUpsellCard: View {
    let description: String

    @EnvironmentObject private var premiumStore: PremiumStore

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("PLAYCE Premium")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PlaycePalette.textPrimary)
                Text(description)
                    .foregroundStyle(PlaycePalette.textSecondary)
                if let productPriceLabel = premiumStore.productPriceLabel {
                    Text("One-time purchase: \(productPriceLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textPrimary)
                }
                PlayceButton(premiumStore.isPurchaseInProgress ? "Opening purchase..." : "Unlock Premium", style: .solid) {
                    premiumStore.unlockPremium()
                }
                .disabled(premiumStore.isPurchaseInProgress)

                PlayceButton("Restore Purchase", style: .outline) {
                    premiumStore.restorePurchases()
                }
                .disabled(!premiumStore.isBillingReady || premiumStore.isPurchaseInProgress)

                PremiumStatusMessageView()
            }
        }
    }
}

struct PremiumStatusMessageView: View {
    @EnvironmentObject private var premiumStore: PremiumStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if premiumStore.isLoading {
                Text("Loading Premium...")
                    .font(.footnote)
                    .foregroundStyle(PlaycePalette.textSecondary)
            }
            if let message = premiumStore.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(PlaycePalette.textSecondary)
            }
        }
    }
}

struct MatchSetupCard: View {
    let onApplyConfig: (String, String, FormatPreset) -> Void
    let onSendToWatch: (String, String, FormatPreset) -> Void

    @State private var isExpanded = false
    @State private var playerAName = ""
    @State private var playerBName = ""
    @State private var selectedPreset: FormatPreset = .standard
    @State private var sentToWatch = false

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MATCH SETUP")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PlaycePalette.textSecondary)
                            Text(isExpanded ? "Names, format and watch sync" : "Player names and match format")
                                .font(.body)
                                .foregroundStyle(PlaycePalette.textPrimary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(PlaycePalette.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PLAYER NAMES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textSecondary)
                        HStack(spacing: 10) {
                            PlayceNameField(placeholder: "Player A", text: $playerAName)
                            PlayceNameField(placeholder: "Player B", text: $playerBName)
                        }

                        Text("MATCH FORMAT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(FormatPreset.allCases) { preset in
                                FormatChip(
                                    preset: preset,
                                    isSelected: selectedPreset == preset,
                                    action: {
                                        selectedPreset = preset
                                        sentToWatch = false
                                    }
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            PlayceButton("Apply", style: .outline) {
                                onApplyConfig(playerAName, playerBName, selectedPreset)
                                sentToWatch = false
                            }
                            PlayceButton(sentToWatch ? "Sent" : "Send Watch", style: .solid) {
                                onSendToWatch(playerAName, playerBName, selectedPreset)
                                sentToWatch = true
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

struct PlayceNameField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { text },
            set: { text = String($0.prefix(12)) }
        ))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .font(.body.weight(.semibold))
        .foregroundStyle(PlaycePalette.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(PlaycePalette.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }
}

struct FormatChip: View {
    let preset: FormatPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(preset.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? PlaycePalette.accent : PlaycePalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(preset.subtitle)
                    .font(.caption2)
                    .foregroundStyle(PlaycePalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 6)
            .background(isSelected ? PlaycePalette.accentMuted : PlaycePalette.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? PlaycePalette.accent : PlaycePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TimerCard: View {
    let elapsed: Int
    let isRunning: Bool
    let hasStarted: Bool
    let onToggle: () -> Void

    var body: some View {
        PlayceCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MATCH TIMER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textSecondary)
                    Text(PlayceFormatting.elapsed(elapsed))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(isRunning ? PlaycePalette.accent : PlaycePalette.textPrimary)
                }
                Spacer()
                PlayceButton(timerButtonTitle, style: hasStarted ? .outline : .solid, action: onToggle)
            }
        }
    }

    private var timerButtonTitle: String {
        if isRunning { return "Pause" }
        return hasStarted ? "Resume" : "Start"
    }
}

struct ScoreboardCard: View {
    let snapshot: MatchSnapshot
    let playerAName: String
    let playerBName: String
    let onAddA: () -> Void
    let onAddB: () -> Void
    let onUndoA: () -> Void
    let onUndoB: () -> Void

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("LIVE SCORE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlaycePalette.textSecondary)
                HeaderRow()
                PlayerRow(
                    name: playerAName,
                    accent: PlaycePalette.accent,
                    sets: snapshot.playerA.sets,
                    games: snapshot.playerA.games,
                    points: snapshot.pointLabel(for: .a),
                    onAdd: onAddA,
                    onUndo: onUndoA
                )
                PlayerRow(
                    name: playerBName,
                    accent: PlaycePalette.textPrimary,
                    sets: snapshot.playerB.sets,
                    games: snapshot.playerB.games,
                    points: snapshot.pointLabel(for: .b),
                    onAdd: onAddB,
                    onUndo: onUndoB
                )
                if !snapshot.completedSets.isEmpty {
                    Text(snapshot.completedSets.map { "\($0.a)-\($0.b)" }.joined(separator: " | "))
                        .font(.subheadline)
                        .foregroundStyle(PlaycePalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(PlaycePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
                MatchStatusRow(snapshot: snapshot, playerAName: playerAName, playerBName: playerBName)
            }
        }
    }
}

struct HeaderRow: View {
    var body: some View {
        HStack {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            SmallHeader("Sets")
            SmallHeader("Games")
            SmallHeader("Pts")
        }
    }
}

struct MatchStatusRow: View {
    let snapshot: MatchSnapshot
    let playerAName: String
    let playerBName: String

    var body: some View {
        HStack(spacing: 10) {
            StatusPill(
                title: snapshot.isTiebreak ? "Tiebreak" : "Server",
                value: snapshot.currentServerIsPlayerA ? playerAName : playerBName,
                highlighted: snapshot.isTiebreak
            )
            StatusPill(
                title: "Serve side",
                value: snapshot.serveStartsOnLeftSide ? "Left" : "Right",
                highlighted: false
            )
        }
    }
}

struct StatusPill: View {
    let title: String
    let value: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(PlaycePalette.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlighted ? PlaycePalette.accent : PlaycePalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(PlaycePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SmallHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(PlaycePalette.textSecondary)
            .frame(width: 54)
    }
}

struct PlayerRow: View {
    let name: String
    let accent: Color
    let sets: Int
    let games: Int
    let points: String
    let onAdd: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
            VStack(spacing: 12) {
                HStack {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(PlaycePalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer()
                    ScoreValue("\(sets)")
                    ScoreValue("\(games)")
                    ScoreValue(points)
                }
                HStack(spacing: 10) {
                    PlayceButton("+ Point", style: .solid, action: onAdd)
                    PlayceButton("Undo", style: .outline, action: onUndo)
                }
            }
            .padding(12)
        }
        .background(PlaycePalette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }
}

struct ScoreValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.headline)
            .foregroundStyle(PlaycePalette.textPrimary)
            .frame(width: 54)
    }
}

struct MobileMatchFinishedContent: View {
    let summary: MobileFinishedSummary
    let onSave: () -> Void
    let onNewMatch: () -> Void

    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("MATCH FINISHED")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PlaycePalette.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(PlaycePalette.accentMuted, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    Text(summary.playerAName)
                        .foregroundStyle(PlaycePalette.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(summary.setsScore)
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(PlaycePalette.textPrimary)
                        .minimumScaleFactor(0.75)
                    Text(summary.playerBName)
                        .foregroundStyle(PlaycePalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                PlayceCard {
                    VStack(spacing: 10) {
                        Text(summary.setsDetail)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textSecondary)
                            .frame(maxWidth: .infinity)
                        Text("Duration \(PlayceFormatting.elapsed(summary.durationSeconds))")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PlaycePalette.textPrimary)
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: 10) {
                    PlayceButton(saved ? "Saved" : "Save Match", style: saved ? .outline : .solid) {
                        guard !saved else { return }
                        onSave()
                        saved = true
                    }
                    PlayceButton("New Match", style: .danger, action: onNewMatch)
                }
            }
            .padding(16)
        }
        .background(PlaycePalette.background.ignoresSafeArea())
    }
}

struct LiveScoreView: View {
    let payload: LiveMatchPayload

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PlayceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            WordmarkView()
                            Text("Watching live from watch")
                                .foregroundStyle(PlaycePalette.textSecondary)
                        }
                        Spacer()
                        LiveBadge()
                    }
                }
                TimerCard(elapsed: payload.elapsedSeconds, isRunning: true, hasStarted: true, onToggle: {})
                PlayceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("LIVE SCORE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textSecondary)
                        HeaderRow()
                        LivePlayerRow(name: "Player A", accent: PlaycePalette.accent, sets: payload.playerASets, games: payload.playerAGames, points: payload.pointLabelA)
                        LivePlayerRow(name: "Player B", accent: PlaycePalette.textPrimary, sets: payload.playerBSets, games: payload.playerBGames, points: payload.pointLabelB)
                        let completed = PlayceFormatting.completedSets(payload.completedSets.replacingOccurrences(of: ",", with: " "))
                        if !completed.isEmpty {
                            Text(completed)
                                .font(.subheadline)
                                .foregroundStyle(PlaycePalette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(PlaycePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(PlaycePalette.background.ignoresSafeArea())
    }
}

struct LivePlayerRow: View {
    let name: String
    let accent: Color
    let sets: Int
    let games: Int
    let points: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(PlaycePalette.textPrimary)
                Spacer()
                ScoreValue("\(sets)")
                ScoreValue("\(games)")
                ScoreValue(points)
            }
            .padding(12)
        }
        .background(PlaycePalette.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }
}

struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PlaycePalette.accent)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1.0)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(PlaycePalette.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PlaycePalette.accentMuted, in: Capsule())
        .task {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct HistoryTabView: View {
    @EnvironmentObject private var historyStore: MatchHistoryStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @State private var selectedRecord: FinishedMatchRecord?

    var body: some View {
        Group {
            if !premiumStore.isPremiumUnlocked {
                PremiumLockedHistoryView()
                    .navigationTitle("History")
            } else if historyStore.matches.isEmpty {
                EmptyHistoryView()
                    .navigationTitle("History")
            } else {
                List {
                    ForEach(historyStore.matches) { record in
                        Button {
                            selectedRecord = record
                        } label: {
                            MatchRow(record: record)
                        }
                        .listRowBackground(PlaycePalette.surface)
                    }
                    .onDelete(perform: historyStore.delete)
                }
                .scrollContentBackground(.hidden)
                .background(PlaycePalette.background)
                .navigationTitle("History")
                .sheet(item: $selectedRecord) { record in
                    NavigationStack {
                        MatchDetailView(recordID: record.id)
                    }
                    .preferredColorScheme(.dark)
                }
            }
        }
        .background(PlaycePalette.background.ignoresSafeArea())
    }
}

struct PremiumLockedHistoryView: View {
    @EnvironmentObject private var premiumStore: PremiumStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordmarkView()
                Text("Free mode on watch. Unlock Premium to save and view your matches on iPhone.")
                    .foregroundStyle(PlaycePalette.textSecondary)
                PremiumUpsellCard(description: "Unlock match save, history, detail and share card on mobile.")
            }
            .padding(20)
        }
        .background(PlaycePalette.background)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No Playces yet")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(PlaycePalette.textPrimary)
            Text("Capture your next match highlight and build your history here.")
                .foregroundStyle(PlaycePalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(PlaycePalette.background)
    }
}

struct MatchRow: View {
    let record: FinishedMatchRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.finalScoreText)
                .font(.headline)
                .foregroundStyle(PlaycePalette.textPrimary)
            Text(PlayceFormatting.timestamp(record.createdAt))
                .font(.subheadline)
                .foregroundStyle(PlaycePalette.textSecondary)
            Text("Duration \(PlayceFormatting.elapsed(record.durationSeconds))")
                .font(.caption)
                .foregroundStyle(PlaycePalette.textSecondary)
            if let setScores = record.setScoresText {
                Text(PlayceFormatting.completedSets(setScores))
                    .font(.caption)
                    .foregroundStyle(PlaycePalette.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct MatchDetailView: View {
    let recordID: FinishedMatchRecord.ID

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: MatchHistoryStore
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var shareCardURL: ShareURLItem?
    @State private var shareError: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if !premiumStore.isPremiumUnlocked {
                PremiumLockedDetailView()
                    .navigationTitle("Match")
            } else if let record = historyStore.record(id: recordID) {
                detailContent(record: record)
            } else {
                EmptyHistoryView()
                    .navigationTitle("History")
            }
        }
    }

    private func detailContent(record: FinishedMatchRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.finalScoreText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(PlaycePalette.textPrimary)
                    Text("\(PlayceFormatting.timestamp(record.createdAt)) | Duration \(PlayceFormatting.elapsed(record.durationSeconds))")
                        .foregroundStyle(PlaycePalette.textSecondary)
                }

                if let photoURL = historyStore.photoURL(for: record) {
                    AttachedPhotoView(photoURL: photoURL)
                }

                PlayceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Score recap")
                            .font(.headline)
                            .foregroundStyle(PlaycePalette.textPrimary)
                        Text(record.finalScoreText)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textPrimary)
                        if let setScores = record.setScoresText {
                            Text(PlayceFormatting.completedSets(setScores))
                                .foregroundStyle(PlaycePalette.textSecondary)
                        }
                        Text(record.detailText)
                            .font(.footnote)
                            .foregroundStyle(PlaycePalette.textSecondary)
                    }
                }

                PlayceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Metadata")
                            .font(.headline)
                            .foregroundStyle(PlaycePalette.textPrimary)
                        Text("Source: \(record.source)")
                            .foregroundStyle(PlaycePalette.textSecondary)
                        Text("Photo: \(record.photoBookmark == nil ? "No photo" : "Attached")")
                            .foregroundStyle(PlaycePalette.textSecondary)
                        Text("ID: \(record.id.uuidString)")
                            .font(.footnote)
                            .foregroundStyle(PlaycePalette.textSecondary)
                    }
                }

                ShareCardView(data: MatchShareCardData(record: record), photoURL: historyStore.photoURL(for: record))
                    .frame(height: 400)

                PlayceButton("Share your Playce", style: .solid) {
                    renderShareCard(record: record)
                }

                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text("Add photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlayceButtonStyle(style: .outline))

                if record.photoBookmark != nil {
                    PlayceButton("Remove photo", style: .outline) {
                        historyStore.updatePhotoBookmark(nil, for: record)
                    }
                }

                if let message = premiumStore.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(PlaycePalette.textSecondary)
                }

                if let shareError {
                    Text(shareError)
                        .foregroundStyle(PlaycePalette.danger)
                }
            }
            .padding(20)
        }
        .background(PlaycePalette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { dismiss() }
                    .foregroundStyle(PlaycePalette.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(PlaycePalette.danger)
            }
        }
        .alert("Delete match?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                historyStore.delete(record)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareCardURL) { item in
            ShareSheet(items: [item.url])
        }
        .task(id: pickedPhoto) {
            guard let pickedPhoto else { return }
            do {
                guard let data = try await pickedPhoto.loadTransferable(type: Data.self) else {
                    shareError = "Failed to attach photo."
                    return
                }
                let fileExtension = pickedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                try historyStore.attachPhotoData(data, fileExtension: fileExtension, to: record)
                shareError = nil
            } catch {
                shareError = "Failed to attach photo."
            }
        }
    }

    private func renderShareCard(record: FinishedMatchRecord) {
        let renderer = ImageRenderer(
            content: ShareCardView(data: MatchShareCardData(record: record), photoURL: historyStore.photoURL(for: record))
                .frame(
                    width: CGFloat(MatchShareCardData.exportWidth),
                    height: CGFloat(MatchShareCardData.exportHeight)
                )
        )
        renderer.scale = 1
        if let image = renderer.uiImage {
            do {
                shareCardURL = ShareURLItem(url: try SharePNGExporter.export(image: image, matchID: record.id))
                shareError = nil
            } catch {
                shareError = "Failed to render share card."
            }
        } else {
            shareError = "Failed to render share card."
        }
    }
}

struct PremiumLockedDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordmarkView()
                Text("Premium required")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(PlaycePalette.textPrimary)
                Text("Unlock Premium to view match details, add photos and share your Playce card.")
                    .foregroundStyle(PlaycePalette.textSecondary)
                PremiumUpsellCard(description: "Match details, photo attachment and share cards are part of the mobile premium toolkit.")
            }
            .padding(20)
        }
        .background(PlaycePalette.background)
    }
}

struct AttachedPhotoView: View {
    let photoURL: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: photoURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PlaycePalette.surfaceElevated
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(PlaycePalette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }
}

struct StatsTabView: View {
    @EnvironmentObject private var historyStore: MatchHistoryStore
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var exportURL: ShareURLItem?
    @State private var exportError: String?

    var body: some View {
        Group {
            if !premiumStore.isPremiumUnlocked {
                PremiumLockedStatsView()
                    .navigationTitle("Stats")
            } else if historyStore.matches.isEmpty {
                EmptyStatsView()
                    .navigationTitle("Stats")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Stats")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(PlaycePalette.textPrimary)

                        StatsGridView(stats: historyStore.stats)
                        ResultDistributionView(stats: historyStore.stats)
                        ExportCSVCard(
                            onExport: exportMatches,
                            error: exportError
                        )
                    }
                    .padding(16)
                }
                .background(PlaycePalette.background.ignoresSafeArea())
                .navigationTitle("Stats")
            }
        }
        .background(PlaycePalette.background.ignoresSafeArea())
        .sheet(item: $exportURL) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func exportMatches() {
        do {
            guard let url = try MatchCSVExporter.export(matches: historyStore.matches) else {
                exportError = "No matches to export."
                return
            }
            exportError = nil
            exportURL = ShareURLItem(url: url)
        } catch {
            exportError = "Failed to export CSV."
        }
    }
}

struct PremiumLockedStatsView: View {
    @EnvironmentObject private var premiumStore: PremiumStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordmarkView()
                Text("Unlock Premium to review match stats and export your history.")
                    .foregroundStyle(PlaycePalette.textSecondary)
                PremiumUpsellCard(description: "Stats and CSV export are part of the mobile premium toolkit.")
            }
            .padding(20)
        }
        .background(PlaycePalette.background)
    }
}

struct EmptyStatsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No stats yet")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(PlaycePalette.textPrimary)
            Text("Save a match to unlock totals, duration insights and CSV export.")
                .foregroundStyle(PlaycePalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(PlaycePalette.background)
    }
}

struct StatsGridView: View {
    let stats: MatchStats

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(label: "Matches played", value: "\(stats.totalMatches)", accent: true)
                StatCard(label: "Total time", value: PlayceFormatting.elapsedLong(stats.totalPlayTimeSeconds))
            }
            HStack(spacing: 12) {
                StatCard(label: "Avg duration", value: PlayceFormatting.elapsed(stats.avgDurationSeconds))
                StatCard(label: "Longest", value: PlayceFormatting.elapsed(stats.longestMatchSeconds))
            }
            HStack(spacing: 12) {
                StatCard(label: "Shortest", value: PlayceFormatting.elapsed(stats.shortestMatchSeconds))
                StatCard(label: "Known results", value: "\(stats.playerAWins + stats.playerBWins)")
            }
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var accent = false

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 5) {
                Text(value)
                    .font(.title.weight(.bold))
                    .foregroundStyle(accent ? PlaycePalette.accent : PlaycePalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlaycePalette.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        }
    }
}

struct ResultDistributionView: View {
    let stats: MatchStats

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("RESULT DISTRIBUTION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PlaycePalette.textSecondary)
                HStack(spacing: 12) {
                    DistributionPill(title: "Player A", value: stats.playerAWins, accent: PlaycePalette.accent)
                    DistributionPill(title: "Player B", value: stats.playerBWins, accent: PlaycePalette.textPrimary)
                }
            }
        }
    }
}

struct DistributionPill: View {
    let title: String
    let value: Int
    let accent: Color

    var body: some View {
        HStack {
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PlaycePalette.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(PlaycePalette.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(PlaycePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ExportCSVCard: View {
    let onExport: () -> Void
    let error: String?

    var body: some View {
        PlayceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export match history")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PlaycePalette.textPrimary)
                Text("CSV with date, score, sets detail and duration in minutes.")
                    .foregroundStyle(PlaycePalette.textSecondary)
                PlayceButton("Export CSV", style: .solid, action: onExport)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(PlaycePalette.danger)
                }
            }
        }
    }
}

struct ShareCardView: View {
    let data: MatchShareCardData
    let photoURL: URL?

    var body: some View {
        ZStack {
            background

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .black.opacity(0.35),
                    .black.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    WordmarkView(font: .system(size: 18, weight: .bold, design: .rounded), width: 104)
                    Text("MATCH RESULT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textSecondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text(data.displayScore)
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .foregroundStyle(PlaycePalette.textPrimary)
                        .minimumScaleFactor(0.64)
                    if let setScores = data.displaySetScores {
                        Text(setScores)
                            .font(.title3)
                            .foregroundStyle(PlaycePalette.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(PlaycePalette.accent.opacity(0.2))
                        .frame(height: 2)
                    HStack {
                        Text(data.dateText)
                            .foregroundStyle(PlaycePalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer()
                        Text(data.durationText)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textPrimary)
                            .lineLimit(1)
                    }
                    Text(data.brandText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textSecondary)
                }
            }
            .padding(44)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var background: some View {
        if let photoURL, let image = UIImage(contentsOfFile: photoURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct PlayceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlaycePalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(PlaycePalette.border, lineWidth: 1)
        )
    }
}

enum PlayceButtonVisualStyle {
    case solid
    case outline
    case danger
}

struct PlayceButton: View {
    let title: LocalizedStringKey
    let style: PlayceButtonVisualStyle
    let action: () -> Void

    init(_ title: String, style: PlayceButtonVisualStyle, action: @escaping () -> Void) {
        self.title = LocalizedStringKey(title)
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(PlayceButtonStyle(style: style))
    }
}

struct PlayceButtonStyle: ButtonStyle {
    let style: PlayceButtonVisualStyle

    func makeBody(configuration: Configuration) -> some View {
        let background: Color
        let foreground: Color
        let stroke: Color

        switch style {
        case .solid:
            background = PlaycePalette.accent
            foreground = .black
            stroke = PlaycePalette.accent.opacity(0.35)
        case .outline:
            background = PlaycePalette.surfaceElevated
            foreground = PlaycePalette.textPrimary
            stroke = PlaycePalette.border
        case .danger:
            background = PlaycePalette.danger.opacity(0.18)
            foreground = PlaycePalette.danger
            stroke = PlaycePalette.danger.opacity(0.35)
        }

        return configuration.label
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

struct WordmarkView: View {
    var font: Font = .system(size: 22, weight: .bold, design: .rounded)
    var width: CGFloat = 122

    var body: some View {
        Image("PlayceWordmark")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: width)
            .accessibilityLabel("PLAYCE")
    }
}

struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum SharePNGExporter {
    static func export(image: UIImage, matchID: UUID, date: Date = Date()) throws -> URL {
        guard let pngData = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("playce-share-cards", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let timestamp = Int(date.timeIntervalSince1970 * 1000)
        let url = exportDir.appendingPathComponent("playce_match_\(matchID.uuidString)_\(timestamp).png")
        try pngData.write(to: url, options: .atomic)
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
