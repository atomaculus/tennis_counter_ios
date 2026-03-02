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

    var body: some View {
        Group {
            if let live = connectivity.liveMatch, live.isMatchActive {
                LiveScoreView(payload: live)
                    .navigationTitle("Live")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        PremiumHeaderCard()
                        TimerCard(
                            elapsed: controller.state.elapsedSeconds,
                            isRunning: controller.state.isTimerRunning,
                            onToggle: controller.toggleTimer
                        )
                        ScoreboardCard(
                            snapshot: controller.state,
                            onAddA: { controller.addPoint(to: .a) },
                            onAddB: { controller.addPoint(to: .b) },
                            onUndoA: { _ = controller.undoLastPoint(for: .a) },
                            onUndoB: { _ = controller.undoLastPoint(for: .b) }
                        )
                        HStack(spacing: 12) {
                            PlayceButton("Reset Game", style: .outline, action: controller.resetGame)
                            PlayceButton("New Match", style: .danger, action: controller.resetMatch)
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
                }
            }
        }
    }
}

struct TimerCard: View {
    let elapsed: Int
    let isRunning: Bool
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
                PlayceButton(isRunning ? "Pause" : "Resume", style: .outline, action: onToggle)
            }
        }
    }
}

struct ScoreboardCard: View {
    let snapshot: MatchSnapshot
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
                    name: "Player A",
                    accent: PlaycePalette.accent,
                    sets: snapshot.playerA.sets,
                    games: snapshot.playerA.games,
                    points: snapshot.pointLabel(for: .a),
                    onAdd: onAddA,
                    onUndo: onUndoA
                )
                PlayerRow(
                    name: "Player B",
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
                TimerCard(elapsed: payload.elapsedSeconds, isRunning: true, onToggle: {})
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
                List(historyStore.matches) { record in
                    Button {
                        selectedRecord = record
                    } label: {
                        MatchRow(record: record)
                    }
                    .listRowBackground(PlaycePalette.surface)
                }
                .scrollContentBackground(.hidden)
                .background(PlaycePalette.background)
                .navigationTitle("History")
                .sheet(item: $selectedRecord) { record in
                    NavigationStack {
                        MatchDetailView(record: record)
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
                PlayceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PLAYCE Premium")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textPrimary)
                        Text("Unlock match save, history, detail and share card on mobile.")
                            .foregroundStyle(PlaycePalette.textSecondary)
                        PlayceButton("Unlock Premium", style: .solid) {
                            premiumStore.unlockPremium()
                        }
                        PlayceButton("Restore Purchase", style: .outline) {
                            premiumStore.restorePurchases()
                        }
                    }
                }
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
    let record: FinishedMatchRecord

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: MatchHistoryStore
    @EnvironmentObject private var premiumStore: PremiumStore

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var shareImage: ShareImageItem?
    @State private var shareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.finalScoreText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(PlaycePalette.textPrimary)
                    Text("\(PlayceFormatting.timestamp(record.createdAt)) | Duration \(PlayceFormatting.elapsed(record.durationSeconds))")
                        .foregroundStyle(PlaycePalette.textSecondary)
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
                        Text("ID: \(record.id.uuidString)")
                            .font(.footnote)
                            .foregroundStyle(PlaycePalette.textSecondary)
                    }
                }

                ShareCardView(record: record)
                    .frame(height: 400)

                PlayceButton("Share your Playce", style: .solid) {
                    renderShareCard()
                }

                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text("Add photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlayceButtonStyle(style: .outline))

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
        }
        .sheet(item: $shareImage) { image in
            ShareSheet(items: [image.image])
        }
        .task(id: pickedPhoto) {
            guard let pickedPhoto else { return }
            do {
                _ = try await pickedPhoto.loadTransferable(type: Data.self)
                let bookmark = try URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .bookmarkData()
                historyStore.updatePhotoBookmark(bookmark, for: record)
                shareError = nil
            } catch {
                shareError = "Failed to attach photo."
            }
        }
    }

    private func renderShareCard() {
        let renderer = ImageRenderer(
            content: ShareCardView(record: record)
                .frame(width: 1080, height: 1920)
        )
        renderer.scale = 1
        if let image = renderer.uiImage {
            shareImage = ShareImageItem(image: image)
            shareError = nil
        } else {
            shareError = "Failed to render share card."
        }
    }
}

struct ShareCardView: View {
    let record: FinishedMatchRecord

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    WordmarkView(font: .system(size: 18, weight: .bold, design: .rounded))
                    Text("MATCH RESULT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlaycePalette.textSecondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text(record.finalScoreText.replacingOccurrences(of: " / ", with: "\n"))
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .foregroundStyle(PlaycePalette.textPrimary)
                    if let setScores = record.setScoresText {
                        Text(PlayceFormatting.completedSets(setScores))
                            .font(.title3)
                            .foregroundStyle(PlaycePalette.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(PlaycePalette.accent.opacity(0.2))
                        .frame(height: 2)
                    HStack {
                        Text(PlayceFormatting.timestamp(record.createdAt))
                            .foregroundStyle(PlaycePalette.textSecondary)
                        Spacer()
                        Text(PlayceFormatting.elapsed(record.durationSeconds))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(PlaycePalette.textPrimary)
                    }
                    Text("Tracked with PLAYCE")
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
    let title: String
    let style: PlayceButtonVisualStyle
    let action: () -> Void

    init(_ title: String, style: PlayceButtonVisualStyle, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
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

    var body: some View {
        (
            Text("PLAY")
                .foregroundStyle(PlaycePalette.textPrimary) +
            Text("CE")
                .foregroundStyle(PlaycePalette.accent)
        )
        .font(font)
        .tracking(1.5)
    }
}

struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
